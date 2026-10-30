// SPDX-FileCopyrightText: Copyright (c) 2024-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
//
`ifndef NV_SOCV_CMDLINE_PROCESSOR_SV
`define NV_SOCV_CMDLINE_PROCESSOR_SV

import uvm_pkg::*;
`include "nv_socv_report_macros.sv"

/**
 * @brief Refreshes UVM command-line state for checkpoint restore invocations.
 *
 * @details
 * UVM captures command-line arguments during simulator startup. In a save/restore
 * flow, the save invocation and each restore invocation can have different
 * plusargs. This file provides APIs that either replace stale UVM command-line
 * state before test launch or merge restore arguments into existing state and
 * reapply UVM settings that were originally consumed before the checkpoint.
 *
 * @startuml
 * title Restore Command-Line Refresh
 *
 * participant "restore simv -r argv" as RestoreArgv
 * participant "uvm_dpi_get_next_arg" as DpiArgv
 * participant "nv_socv_cmdline_processor" as CLP
 * participant "uvm_cmdline_processor singleton" as UvmClp
 * participant "UVM factory/config/report state" as UvmState
 * participant "run_test" as RunTest
 *
 * RestoreArgv -> DpiArgv : fresh restore invocation arguments
 * alt delayed test launch
 *   CLP -> UvmClp : clear stale argv tables
 * else save-context restore
 *   CLP -> UvmClp : preserve existing argv tables
 * end
 * loop until empty argument
 *   CLP -> DpiArgv : get next arg
 *   DpiArgv --> CLP : arg
 *   alt repeatable +uvm_set_* switch
 *     CLP -> UvmClp : append independent setting
 *   else argument key already exists
 *     CLP -> UvmClp : replace matching entries
 *   else new argument key
 *     CLP -> UvmClp : append argument
 *   end
 * end
 * opt save-context restore
 *   CLP -> UvmState : reapply global/report verbosity
 *   CLP -> UvmState : apply report action and severity
 *   CLP -> UvmState : apply factory overrides
 *   CLP -> UvmState : publish config/default sequence
 *   CLP -> UvmState : apply timeout/max quit count
 * end
 * RunTest -> UvmClp : consume refreshed command line
 * @enduml
 */
class nv_socv_cmdline_processor extends uvm_cmdline_processor;
    /** @brief Guards against multiple repopulation attempts in one simulation. */
    static local bit m_cmdline_repopulated = 0;
    /** @brief Guards against multiple append attempts in one simulation. */
    static local bit m_cmdline_appended = 0;

    /**
     * @brief Protected constructor; use static refresh API only.
     * @param name Instance name passed to `uvm_cmdline_processor`.
     */
    protected function new(string name="nv_socv_cmdline_processor");
        super.new(name);
    endfunction

    /**
     * @brief Identity of a plusarg, for keeping only its first occurrence.
     *
     * @details
     * Two plusargs with the same identity set the same thing. For `+uvm_set_*`
     * settings the identity is the setting name plus the fields naming its
     * target (not the value):
     *   - `type_override`: requested type
     *   - `inst_override`: requested type, instance path
     *   - `config_int` / `config_string`: instance path, field
     *   - `verbosity`: every field except the verbosity
     *   - `action` / `severity`: component, id, severity
     *   - `default_sequence`: instance path, phase
     * Other `+uvm_set_*` switches are identified by their full text. Every other
     * plusarg is identified by `get_arg_key()` (`+NAME` of `+NAME=value`).
     *
     * @param arg Plusarg to inspect.
     * @return Identity string.
     */
    static local function string get_setting_key(string arg);
        string name;
        string prefix;
        string fields[$];
        int field_start;

        name = get_arg_key(arg);
        if (name.len() < 9)
            return name;
        prefix = name.substr(0, 8);
        if (prefix.tolower() != "+uvm_set_")
            return name;
        if (name.len() == arg.len())
            return arg;

        field_start = name.len() + 1;
        for (int idx = field_start; idx <= arg.len(); idx++) begin
            if ((idx == arg.len()) || (arg[idx] == ",")) begin
                fields.push_back((idx > field_start) ? arg.substr(field_start, idx - 1) : "");
                field_start = idx + 1;
            end
        end

        name = name.tolower();
        case (name)
            "+uvm_set_type_override":
                return (fields.size() >= 1) ? {name, ":", fields[0]} : arg;
            "+uvm_set_inst_override":
                return (fields.size() >= 3) ? {name, ":", fields[0], ",", fields[2]} : arg;
            "+uvm_set_config_int",
            "+uvm_set_config_string",
            "+uvm_set_default_sequence":
                return (fields.size() >= 2) ? {name, ":", fields[0], ",", fields[1]} : arg;
            "+uvm_set_action",
            "+uvm_set_severity":
                return (fields.size() >= 3) ? {name, ":", fields[0], ",", fields[1], ",", fields[2]} : arg;
            "+uvm_set_verbosity": begin
                if (fields.size() < 4)
                    return arg;
                fields.delete(2);
                get_setting_key = name;
                foreach (fields[idx])
                    get_setting_key = {get_setting_key, (idx == 0) ? ":" : ",", fields[idx]};
                return get_setting_key;
            end
            default:
                return arg;
        endcase
    endfunction

    /**
     * @brief Read the current command line through `uvm_dpi_get_next_arg()`.
     *
     * @details
     * A setting given more than once (same `get_setting_key()` identity) is
     * kept once. `+NV_SOCV_CMDLINE_PRECEDENCE=first` (default) keeps the first
     * occurrence, the rule `$value$plusargs` follows; `=last` keeps the last
     * one, at its position. After an Xcelium restart the reported argv holds
     * the new command line followed by the saving run's plusargs, so `first`
     * makes the new values win and `last` the saving run's. Tokens that are
     * not plusargs are kept as they are.
     *
     * @param args Current command line, one occurrence per setting.
     */
    static local function void read_dpi_cmdline(output string args[$]);
        string s;
        string precedence;
        string all_args[$];
        int keep_idx[string];
        int doInit;
        bit last;

        doInit = 1;
        do begin
            s = uvm_dpi_get_next_arg(doInit);
            doInit = 0;
            if (s != "")
                all_args.push_back(s);
        end while (s != "");

        last = 0;
        if ($value$plusargs("NV_SOCV_CMDLINE_PRECEDENCE=%s", precedence)) begin
            precedence = precedence.tolower();
            if (precedence == "last")
                last = 1;
            else if (precedence != "first")
                `nv_uvm_warning("NV_SOCV_CMDLINE_PROCESSOR/PRECEDENCE",
                                $sformatf("+NV_SOCV_CMDLINE_PRECEDENCE=%s: expected first or last; using first", precedence))
        end

        foreach (all_args[idx]) begin
            s = all_args[idx];
            if ((s[0] == "+") && (last || !keep_idx.exists(get_setting_key(s))))
                keep_idx[get_setting_key(s)] = idx;
        end

        args.delete();
        foreach (all_args[idx]) begin
            s = all_args[idx];
            if ((s[0] != "+") || (keep_idx[get_setting_key(s)] == idx))
                args.push_back(s);
        end
    endfunction

    /**
     * @brief Rebuild UVM argv/plusarg/uvm_argv tables from DPI command line.
     *
     * @details
     * Clears `m_argv`, `m_plus_argv`, and `m_uvm_argv` on the UVM singleton
     * returned by `get_inst()`, then refills them from `read_dpi_cmdline()`.
     * Entries of the saving run are not kept: before `uvm_test_top` exists,
     * nothing has been built from them.
     * Plusargs (tokens beginning with `+`) are mirrored into `m_plus_argv`;
     * tokens whose first four characters after `+`/`-` spell `UVM` (case
     * insensitive) are also added to `m_uvm_argv`.
     */
    static local function void repopulate_cmdline();
        string s;
        string sub;
        string args[$];
        uvm_cmdline_processor clp;

        if (m_cmdline_repopulated) begin
            `nv_uvm_warning("NV_SOCV_CMDLINE_PROCESSOR/REPOPULATE", "Command line already repopulated, skipping repopulation");
            return;
        end

        m_cmdline_repopulated = 1;
        clp = get_inst();   // the real UVM singleton
        read_dpi_cmdline(args);
        clp.m_argv.delete();
        clp.m_plus_argv.delete();
        clp.m_uvm_argv.delete();

        foreach (args[n]) begin
            s = args[n];
            clp.m_argv.push_back(s);
            if (s[0] == "+")
                clp.m_plus_argv.push_back(s);
            if (s.len() >= 4 && (s[0]=="-" || s[0]=="+")) begin
                sub = s.substr(1,3);
                sub = sub.toupper();
                if (sub == "UVM")
                    clp.m_uvm_argv.push_back(s);
            end
        end
        `nv_uvm_info("NV_SOCV_CMDLINE_PROCESSOR/REPOPULATE", "Command line repopulated", UVM_NONE);
    endfunction

    /**
     * @brief Extract the key used to merge a command-line argument.
     *
     * @details
     * For a switch such as `+NAME=value`, returns `+NAME`. For a switch without
     * an equals sign, returns the complete switch. Positional arguments return
     * an empty key and are therefore always appended.
     *
     * @param arg Command-line argument to inspect.
     * @return Argument key, or an empty string for a positional argument.
     */
    static local function string get_arg_key(string arg);
        int separator_idx;
        int idx;

        get_arg_key = "";
        if ((arg.len() == 0) || ((arg[0] != "+") && (arg[0] != "-")))
            return get_arg_key;

        separator_idx = -1;
        for (idx = 1; idx < arg.len(); idx++) begin
            if (arg[idx] == "=") begin
                separator_idx = idx;
                break;
            end
        end

        if (separator_idx > 0)
            get_arg_key = arg.substr(0, separator_idx - 1);
        else
            get_arg_key = arg;
    endfunction

    /**
     * @brief Identify UVM switches that may legally occur multiple times.
     *
     * @details
     * These switches describe independent settings. They must remain as separate
     * command-line entries so UVM can process every action, override, or config
     * assignment in command-line order.
     *
     * @param arg_key Key returned by `get_arg_key()`.
     * @return 1 when the argument must be appended instead of replaced.
     */
    static local function bit is_repeatable_arg(string arg_key);
        string normalized_key;

        normalized_key = arg_key.tolower();
        return ((normalized_key == "+uvm_set_action") ||
                (normalized_key == "+uvm_set_severity") ||
                (normalized_key == "+uvm_set_verbosity") ||
                (normalized_key == "+uvm_set_inst_override") ||
                (normalized_key == "+uvm_set_type_override") ||
                (normalized_key == "+uvm_set_config_int") ||
                (normalized_key == "+uvm_set_config_string") ||
                (normalized_key == "+uvm_set_default_sequence"));
    endfunction

    /**
     * @brief Merge current DPI command-line args into existing UVM argv tables.
     *
     * @details
     * Unlike `repopulate_cmdline()`, this does **not** clear the existing tables.
     * The current command line comes from `read_dpi_cmdline()`, one occurrence
     * per setting. A new switch replaces every existing entry with the same key, where the key
     * is the portion before the first `=` (for example, `+NAME` is the key of
     * `+NAME=value`). Repeatable `+uvm_set_*` switches, new keys, and positional
     * arguments are appended. Singleton replacements are applied consistently to
     * `m_argv`, `m_plus_argv`, and `m_uvm_argv`. Each changed singleton value is
     * reported to make restore-time overrides visible to the user.
     */
    static local function void append_cmdline();
        string s;
        string sub;
        string arg_key;
        string existing_key;
        string old_arg;
        string args[$];
        bit arg_found;
        bit override_reported;
        uvm_cmdline_processor clp;

        if (m_cmdline_appended) begin
            `nv_uvm_warning("NV_SOCV_CMDLINE_PROCESSOR/APPEND", "Command line already appended, appending again");
        end

        m_cmdline_appended = 1;
        clp = get_inst();   // the real UVM singleton — keep existing argv entries
        read_dpi_cmdline(args);

        foreach (args[n]) begin
            s = args[n];
            arg_key = get_arg_key(s);
            // Preserve every independently processed UVM setting.
            if (is_repeatable_arg(arg_key))
                arg_key = "";
            arg_found = 0;
            override_reported = 0;
            foreach (clp.m_argv[idx]) begin
                existing_key = get_arg_key(clp.m_argv[idx]);
                if ((arg_key != "") && (existing_key == arg_key)) begin
                    old_arg = clp.m_argv[idx];
                    clp.m_argv[idx] = s;
                    arg_found = 1;
                    if (!override_reported && (old_arg != s)) begin
                        `nv_uvm_info("NV_SOCV_CMDLINE_PROCESSOR/OVERRIDE",
                                     $sformatf("Command-line argument overridden: '%s' -> '%s'",
                                               old_arg, s),
                                     UVM_NONE);
                        override_reported = 1;
                    end
                end
            end
            if (!arg_found)
                clp.m_argv.push_back(s);

            if (s[0] == "+") begin
                arg_found = 0;
                foreach (clp.m_plus_argv[idx]) begin
                    existing_key = get_arg_key(clp.m_plus_argv[idx]);
                    if ((arg_key != "") && (existing_key == arg_key)) begin
                        clp.m_plus_argv[idx] = s;
                        arg_found = 1;
                    end
                end
                if (!arg_found)
                    clp.m_plus_argv.push_back(s);
            end

            if (s.len() >= 4 && (s[0]=="-" || s[0]=="+")) begin
                sub = s.substr(1,3);
                sub = sub.toupper();
                if (sub == "UVM") begin
                    arg_found = 0;
                    foreach (clp.m_uvm_argv[idx]) begin
                        existing_key = get_arg_key(clp.m_uvm_argv[idx]);
                        if ((arg_key != "") && (existing_key == arg_key)) begin
                            clp.m_uvm_argv[idx] = s;
                            arg_found = 1;
                        end
                    end
                    if (!arg_found)
                        clp.m_uvm_argv.push_back(s);
                end
            end
        end
        `nv_uvm_info("NV_SOCV_CMDLINE_PROCESSOR/APPEND", "Command-line args merged", UVM_NONE);
    endfunction

    /**
     * @brief Find existing UVM components matching a command-line pattern.
     *
     * @param pattern UVM component glob pattern.
     * @param components Queue populated with matching components.
     */
    static local function void find_matching_components(
        string pattern,
        ref uvm_component components[$]
    );
        uvm_root root;

        root = uvm_root::get();
        components.delete();
        root.find_all(pattern, components);
        if (uvm_is_match(pattern, root.get_full_name()))
            components.push_back(root);
    endfunction

    /**
     * @brief Apply one `+uvm_set_action` value to existing components.
     *
     * @param setting Text after `+uvm_set_action=`.
     */
    static local function void apply_report_action(string setting);
        string fields[$];
        uvm_component components[$];
        uvm_severity severity;
        uvm_action action;

        uvm_split_string(setting, ",", fields);
        if (fields.size() != 4) begin
            `nv_uvm_warning("NV_SOCV_CMDLINE_PROCESSOR/REAPPLY",
                            $sformatf("Ignoring invalid +uvm_set_action=%s", setting));
            return;
        end
        if ((fields[2] != "_ALL_") &&
            !uvm_string_to_severity(fields[2], severity)) begin
            `nv_uvm_warning("NV_SOCV_CMDLINE_PROCESSOR/REAPPLY",
                            $sformatf("Ignoring +uvm_set_action with invalid severity: %s", setting));
            return;
        end
        if (!uvm_string_to_action(fields[3], action)) begin
            `nv_uvm_warning("NV_SOCV_CMDLINE_PROCESSOR/REAPPLY",
                            $sformatf("Ignoring +uvm_set_action with invalid action: %s", setting));
            return;
        end

        find_matching_components(fields[0], components);
        foreach (components[idx]) begin
            if (fields[1] == "_ALL_") begin
                if (fields[2] == "_ALL_") begin
                    components[idx].set_report_severity_action(UVM_INFO, action);
                    components[idx].set_report_severity_action(UVM_WARNING, action);
                    components[idx].set_report_severity_action(UVM_ERROR, action);
                    components[idx].set_report_severity_action(UVM_FATAL, action);
                end
                else
                    components[idx].set_report_severity_action(severity, action);
            end
            else if (fields[2] == "_ALL_")
                components[idx].set_report_id_action(fields[1], action);
            else
                components[idx].set_report_severity_id_action(severity, fields[1], action);
        end
    endfunction

    /**
     * @brief Apply one `+uvm_set_severity` value to existing components.
     *
     * @param setting Text after `+uvm_set_severity=`.
     */
    static local function void apply_report_severity(string setting);
        string fields[$];
        uvm_component components[$];
        uvm_severity original_severity;
        uvm_severity new_severity;

        uvm_split_string(setting, ",", fields);
        if (fields.size() != 4) begin
            `nv_uvm_warning("NV_SOCV_CMDLINE_PROCESSOR/REAPPLY",
                            $sformatf("Ignoring invalid +uvm_set_severity=%s", setting));
            return;
        end
        if ((fields[2] != "_ALL_") &&
            !uvm_string_to_severity(fields[2], original_severity)) begin
            `nv_uvm_warning("NV_SOCV_CMDLINE_PROCESSOR/REAPPLY",
                            $sformatf("Ignoring +uvm_set_severity with invalid original severity: %s", setting));
            return;
        end
        if (!uvm_string_to_severity(fields[3], new_severity)) begin
            `nv_uvm_warning("NV_SOCV_CMDLINE_PROCESSOR/REAPPLY",
                            $sformatf("Ignoring +uvm_set_severity with invalid new severity: %s", setting));
            return;
        end

        find_matching_components(fields[0], components);
        foreach (components[idx]) begin
            if ((fields[1] == "_ALL_") && (fields[2] == "_ALL_")) begin
                components[idx].set_report_severity_override(UVM_INFO, new_severity);
                components[idx].set_report_severity_override(UVM_WARNING, new_severity);
                components[idx].set_report_severity_override(UVM_ERROR, new_severity);
                components[idx].set_report_severity_override(UVM_FATAL, new_severity);
            end
            else if (fields[1] == "_ALL_")
                components[idx].set_report_severity_override(original_severity, new_severity);
            else if (fields[2] == "_ALL_") begin
                components[idx].set_report_severity_id_override(UVM_INFO, fields[1], new_severity);
                components[idx].set_report_severity_id_override(UVM_WARNING, fields[1], new_severity);
                components[idx].set_report_severity_id_override(UVM_ERROR, fields[1], new_severity);
                components[idx].set_report_severity_id_override(UVM_FATAL, fields[1], new_severity);
            end
            else
                components[idx].set_report_severity_id_override(original_severity,
                                                                fields[1],
                                                                new_severity);
        end
    endfunction

    /**
     * @brief Apply one `+uvm_set_verbosity` value to existing components.
     *
     * @details
     * Restore occurs after the original UVM phase/time trigger, so matching
     * settings are applied immediately. This ensures the restored hierarchy uses
     * the requested verbosity without waiting for a phase callback that has
     * already executed.
     *
     * @param setting Text after `+uvm_set_verbosity=`.
     */
    static local function void apply_report_verbosity(string setting);
        string fields[$];
        uvm_component components[$];
        uvm_verbosity verbosity;
        uvm_cmdline_processor clp;

        clp = get_inst();
        uvm_split_string(setting, ",", fields);
        if (((fields.size() != 4) && (fields.size() != 5)) ||
            !clp.m_convert_verb(fields[2], verbosity)) begin
            `nv_uvm_warning("NV_SOCV_CMDLINE_PROCESSOR/REAPPLY",
                            $sformatf("Ignoring invalid +uvm_set_verbosity=%s", setting));
            return;
        end

        find_matching_components(fields[0], components);
        foreach (components[idx]) begin
            if (fields[1] == "_ALL_")
                components[idx].set_report_verbosity_level(verbosity);
            else
                components[idx].set_report_id_verbosity(fields[1], verbosity);
        end
    endfunction

    /**
     * @brief Apply factory type and instance overrides from the command line.
     *
     * @details
     * Mirrors `uvm_root::m_do_factory_settings()` without entering the UVM
     * phasing system. Existing factory entries are retained; see
     * `reapply_cmdline_settings()` for object-lifetime caveats.
     */
    static local function void apply_factory_settings();
        string args[$];
        string fields[$];
        string setting;
        int replace;
        int idx;
        uvm_cmdline_processor clp;
        uvm_factory factory;

        clp = get_inst();
        factory = uvm_coreservice_t::get().get_factory();

        args.delete();
        void'(clp.get_arg_matches("/^\\+(UVM_SET_INST_OVERRIDE|uvm_set_inst_override)=/", args));
        foreach (args[idx]) begin
            setting = args[idx].substr(23, args[idx].len() - 1);
            fields.delete();
            uvm_split_string(setting, ",", fields);
            if (fields.size() != 3) begin
                `nv_uvm_warning("NV_SOCV_CMDLINE_PROCESSOR/REAPPLY",
                                $sformatf("Ignoring invalid +uvm_set_inst_override=%s", setting));
                continue;
            end
            `nv_uvm_info("NV_SOCV_CMDLINE_PROCESSOR/REAPPLY",
                         {"Applying instance override: +uvm_set_inst_override=", setting},
                         UVM_NONE);
            factory.set_inst_override_by_name(fields[0], fields[1], fields[2]);
        end

        args.delete();
        void'(clp.get_arg_matches("/^\\+(UVM_SET_TYPE_OVERRIDE|uvm_set_type_override)=/", args));
        foreach (args[idx]) begin
            setting = args[idx].substr(23, args[idx].len() - 1);
            fields.delete();
            replace = 1;
            uvm_split_string(setting, ",", fields);
            if ((fields.size() > 3) || (fields.size() < 2)) begin
                `nv_uvm_warning("NV_SOCV_CMDLINE_PROCESSOR/REAPPLY",
                                $sformatf("Ignoring invalid +uvm_set_type_override=%s", setting));
                continue;
            end
            if (fields.size() == 3) begin
                if (fields[2] == "0")
                    replace = 0;
                else if (fields[2] == "1")
                    replace = 1;
                else begin
                    `nv_uvm_warning("NV_SOCV_CMDLINE_PROCESSOR/REAPPLY",
                                    $sformatf("Ignoring +uvm_set_type_override with invalid replace: %s",
                                              setting));
                    continue;
                end
            end
            `nv_uvm_info("NV_SOCV_CMDLINE_PROCESSOR/REAPPLY",
                         {"Applying type override: +uvm_set_type_override=", setting},
                         UVM_NONE);
            factory.set_type_override_by_name(fields[0], fields[1], replace);
        end
    endfunction

    /**
     * @brief Apply one config-int or config-string command-line setting.
     *
     * @param setting Text after `+uvm_set_config_int=` / `+uvm_set_config_string=`.
     * @param is_int 1 for integer config, 0 for string config.
     */
    static local function void apply_config_setting(string setting, bit is_int);
        string fields[$];
        string base;
        string extval;
        uvm_bitstream_t value;
        uvm_root root;

        root = uvm_root::get();
        uvm_split_string(setting, ",", fields);
        if (fields.size() != 3) begin
            `nv_uvm_warning("NV_SOCV_CMDLINE_PROCESSOR/REAPPLY",
                            $sformatf("Ignoring invalid +uvm_set_config setting=%s", setting));
            return;
        end

        if (is_int) begin
            if (fields[2].len() > 2) begin
                base = fields[2].substr(0, 1);
                extval = fields[2].substr(2, fields[2].len() - 1);
                case (base)
                    "'b", "0b": void'($sscanf(extval, "%b", value));
                    "'o": void'($sscanf(extval, "%o", value));
                    "'d": void'($sscanf(extval, "%d", value));
                    "'h", "'x", "0x": void'($sscanf(extval, "%h", value));
                    default: void'($sscanf(fields[2], "%d", value));
                endcase
            end
            else
                void'($sscanf(fields[2], "%d", value));

            `nv_uvm_info("NV_SOCV_CMDLINE_PROCESSOR/REAPPLY",
                         {"Applying config int: +uvm_set_config_int=", setting},
                         UVM_NONE);
            uvm_config_int::set(root, fields[0], fields[1], value);
        end
        else begin
            `nv_uvm_info("NV_SOCV_CMDLINE_PROCESSOR/REAPPLY",
                         {"Applying config string: +uvm_set_config_string=", setting},
                         UVM_NONE);
            uvm_config_string::set(root, fields[0], fields[1], fields[2]);
        end
    endfunction

    /**
     * @brief Apply one `+uvm_set_default_sequence` value.
     *
     * @param setting Text after `+uvm_set_default_sequence=`.
     */
    static local function void apply_default_sequence(string setting);
        string fields[$];
        uvm_object_wrapper wrapper;
        uvm_factory factory;

        factory = uvm_coreservice_t::get().get_factory();
        uvm_split_string(setting, ",", fields);
        if (fields.size() != 3) begin
            `nv_uvm_warning("NV_SOCV_CMDLINE_PROCESSOR/REAPPLY",
                            $sformatf("Ignoring invalid +uvm_set_default_sequence=%s", setting));
            return;
        end

        wrapper = factory.find_wrapper_by_name(fields[2]);
        if (wrapper == null) begin
            `nv_uvm_warning("NV_SOCV_CMDLINE_PROCESSOR/REAPPLY",
                            $sformatf("Ignoring +uvm_set_default_sequence with unknown type: %s",
                                      setting));
            return;
        end

        `nv_uvm_info("NV_SOCV_CMDLINE_PROCESSOR/REAPPLY",
                     {"Applying default sequence: +uvm_set_default_sequence=", setting},
                     UVM_NONE);
        uvm_config_db#(uvm_object_wrapper)::set(uvm_root::get(),
                                                {fields[0], ".", fields[1]},
                                                "default_sequence",
                                                wrapper);
    endfunction

    /**
     * @brief Apply config-int, config-string, and default-sequence settings.
     *
     * @details
     * Mirrors `uvm_root::m_do_config_settings()` without entering the UVM
     * phasing system.
     */
    static local function void apply_config_settings();
        string args[$];
        string setting;
        int idx;
        uvm_cmdline_processor clp;

        clp = get_inst();

        args.delete();
        void'(clp.get_arg_matches("/^\\+(UVM_SET_CONFIG_INT|uvm_set_config_int)=/", args));
        foreach (args[idx]) begin
            setting = args[idx].substr(20, args[idx].len() - 1);
            apply_config_setting(setting, 1);
        end

        args.delete();
        void'(clp.get_arg_matches("/^\\+(UVM_SET_CONFIG_STRING|uvm_set_config_string)=/", args));
        foreach (args[idx]) begin
            setting = args[idx].substr(23, args[idx].len() - 1);
            apply_config_setting(setting, 0);
        end

        args.delete();
        void'(clp.get_arg_matches("/^\\+(UVM_SET_DEFAULT_SEQUENCE|uvm_set_default_sequence)=/", args));
        foreach (args[idx]) begin
            setting = args[idx].substr(26, args[idx].len() - 1);
            apply_default_sequence(setting);
        end
    endfunction

    /**
     * @brief Apply `+UVM_TIMEOUT` from the restored command line.
     *
     * @details
     * Mirrors `uvm_root::m_do_timeout_settings()`.
     */
    static local function void apply_timeout_settings();
        string timeout_settings[$];
        string timeout;
        string override_spec;
        time timeout_int;
        int timeout_count;
        uvm_cmdline_processor clp;
        uvm_root root;

        clp = get_inst();
        root = uvm_root::get();
        timeout_count = clp.get_arg_values("+UVM_TIMEOUT=", timeout_settings);
        if (timeout_count == 0)
            return;

        timeout = timeout_settings[0];
        void'($sscanf(timeout, "%d,%s", timeout_int, override_spec));
        `nv_uvm_info("NV_SOCV_CMDLINE_PROCESSOR/REAPPLY",
                     $sformatf("Applying +UVM_TIMEOUT=%s", timeout),
                     UVM_NONE);
        case (override_spec)
            "YES": root.set_timeout(timeout_int, 1);
            "NO": root.set_timeout(timeout_int, 0);
            default: root.set_timeout(timeout_int, 1);
        endcase
    endfunction

    /**
     * @brief Apply `+UVM_MAX_QUIT_COUNT` from the restored command line.
     *
     * @details
     * Mirrors `uvm_root::m_do_max_quit_settings()`.
     */
    static local function void apply_max_quit_settings();
        string max_quit_settings[$];
        string max_quit;
        string split_max_quit[$];
        int max_quit_count;
        int max_quit_int;
        uvm_cmdline_processor clp;
        uvm_report_server srvr;

        clp = get_inst();
        srvr = uvm_report_server::get_server();
        max_quit_count = clp.get_arg_values("+UVM_MAX_QUIT_COUNT=", max_quit_settings);
        if (max_quit_count == 0)
            return;

        max_quit = max_quit_settings[0];
        uvm_split_string(max_quit, ",", split_max_quit);
        void'($sscanf(split_max_quit[0], "%d", max_quit_int));
        `nv_uvm_info("NV_SOCV_CMDLINE_PROCESSOR/REAPPLY",
                     $sformatf("Applying +UVM_MAX_QUIT_COUNT=%s", max_quit),
                     UVM_NONE);
        case ((split_max_quit.size() > 1) ? split_max_quit[1] : "default")
            "YES": srvr.set_max_quit_count(max_quit_int, 1);
            "NO": srvr.set_max_quit_count(max_quit_int, 0);
            default: srvr.set_max_quit_count(max_quit_int, 1);
        endcase
    endfunction

    /**
     * @brief Reapply UVM command-line side effects after checkpoint restore.
     *
     * @details
     * Updating argv tables alone is not enough: UVM normally consumes many
     * switches during root construction / `build_phase()`. This function
     * reapplies those side effects without calling `build_phase()`:
     * - global and component report verbosity
     * - report action and severity overrides
     * - factory type/instance overrides
     * - config int/string and default sequence
     * - timeout and maximum quit count
     *
     * Report action/severity/verbosity are reapplied explicitly because UVM 1.2
     * caches its initial command-line parse. Factory and config state are not
     * cleared first: matching type overrides follow the command-line `replace`
     * flag; instance overrides and unrelated settings remain registered.
     *
     * @warning Factory overrides affect only objects created after this call.
     *          Existing objects are not reconstructed. Config DB consumers that
     *          cached values must perform a new `get()` to observe updates.
     */
    static function void reapply_cmdline_settings();
        string settings[$];
        uvm_root root;
        uvm_cmdline_processor clp;

        root = uvm_root::get();
        clp = get_inst();

        // Global verbosity is normally processed only in uvm_root::new().
        root.m_check_verbosity();

        // Replay factory/config/timeout/quit without calling build_phase().
        apply_factory_settings();
        apply_config_settings();
        apply_timeout_settings();
        apply_max_quit_settings();

        settings.delete();
        void'(clp.get_arg_values("+uvm_set_action=", settings));
        foreach (settings[idx])
            apply_report_action(settings[idx]);

        settings.delete();
        void'(clp.get_arg_values("+uvm_set_severity=", settings));
        foreach (settings[idx])
            apply_report_severity(settings[idx]);

        settings.delete();
        void'(clp.get_arg_values("+uvm_set_verbosity=", settings));
        foreach (settings[idx])
            apply_report_verbosity(settings[idx]);

        `nv_uvm_info("NV_SOCV_CMDLINE_PROCESSOR/REAPPLY",
                     "UVM command-line settings reapplied",
                     UVM_NONE);
    endfunction

    /**
     * @brief Replace UVM command-line state before launching the delayed test.
     *
     * @details
     * Called from `nv_socv_sim_restore::wait_for_test_launch_trigger()` after boot
     * is complete and `test_launch_event` has fired, but **before** `uvm_test_top`
     * is created. It discards stale command-line state and repopulates the UVM
     * parser from the current invocation so `run_test()` sees the intended
     * `+UVM_TESTNAME` and related plusargs.
     *
     * @warning Issues `NV_SOCV_CMDLINE_PROCESSOR` fatal if `uvm_test_top` already exists,
     *          because changing the selected test after construction is unsafe.
     */
    static function void refresh_cmdline_parser_for_test_launch();
        if (uvm_root::get().has_child("uvm_test_top")) begin
            `nv_uvm_fatal("NV_SOCV_CMDLINE_PROCESSOR", "Cannot refresh CLP after uvm_test_top exists");
        end
        repopulate_cmdline();  // local/static, not public API
    endfunction

    /**
     * @brief Merge restore arguments and reapply their UVM side effects.
     *
     * @details
     * Calls `append_cmdline()` to merge the restore invocation into the existing
     * UVM argv tables, then `reapply_cmdline_settings()` to drive the matching
     * live report, factory, and config side effects. Merge rules and reapply
     * caveats are documented on those helpers.
     */
    static function void refresh_cmdline_parser_for_restore();
        append_cmdline();  // local/static, not public API
        reapply_cmdline_settings();
    endfunction

    /** @brief Set once `refresh_cmdline_for_late_build()` has reprocessed the command line. */
    static local bit m_cmdline_late_refreshed = 0;

    /**
     * @brief Has the UVM command line already been refreshed in this invocation?
     * @return 1 after `refresh_cmdline_parser_for_test_launch()`,
     *         `refresh_cmdline_parser_for_restore()` or
     *         `refresh_cmdline_for_late_build()` has reprocessed it.
     */
    static function bit is_cmdline_refreshed();
        return m_cmdline_repopulated || m_cmdline_appended || m_cmdline_late_refreshed;
    endfunction

    /**
     * @brief Reprocess the command line before a UVM tree is built at non-zero time.
     *
     * @details
     * Called by the pre/post domain controllers right before a domain build
     * or the main-test build starts. UVM consumed the command line at time 0
     * (`run_test()`), so a build that starts later (e.g. after a checkpoint
     * restore with new plusargs) must reprocess it first:
     * - at time 0, or if the command line was already refreshed in this
     *   invocation (e.g. by `nv_socv_save_context` on restore): no-op;
     * - `uvm_test_top` does not exist yet:
     *   `refresh_cmdline_parser_for_test_launch()` + `reapply_cmdline_settings()`;
     * - `uvm_test_top` exists: `refresh_cmdline_parser_for_restore()`.
     *
     * The guards of `refresh_cmdline_parser_for_test_launch()` and
     * `refresh_cmdline_parser_for_restore()` are left as they were, so later
     * calls of those APIs behave exactly as without this function.
     *
     * @param who Build about to start; used in the report only.
     */
    static function void refresh_cmdline_for_late_build(string who);
        bit saved_repopulated;
        bit saved_appended;

        if ($time == 0)
            return;
        if (is_cmdline_refreshed()) begin
            `nv_uvm_info("NV_SOCV_CMDLINE_PROCESSOR/LATE_BUILD",
                         {"Command line already refreshed in this invocation; not reprocessed for ", who},
                         UVM_LOW);
            return;
        end
        `nv_uvm_info("NV_SOCV_CMDLINE_PROCESSOR/LATE_BUILD",
                     $sformatf("Reprocessing command line before %s at %0t", who, $time),
                     UVM_NONE);
        saved_repopulated = m_cmdline_repopulated;
        saved_appended    = m_cmdline_appended;
        if (!uvm_root::get().has_child("uvm_test_top")) begin
            refresh_cmdline_parser_for_test_launch();
            reapply_cmdline_settings();
        end
        else
            refresh_cmdline_parser_for_restore();
        m_cmdline_repopulated    = saved_repopulated;
        m_cmdline_appended       = saved_appended;
        m_cmdline_late_refreshed = 1;
    endfunction

    /**
     * @brief Apply command-line factory/config settings to a tree built at time 0
     *        before `uvm_root::build_phase()`.
     *
     * @details
     * UVM applies `+uvm_set_inst_override`, `+uvm_set_type_override`,
     * `+uvm_set_config_int`, `+uvm_set_config_string` and
     * `+uvm_set_default_sequence` in `uvm_root::build_phase()`. A tree built
     * in a domain scheduled before the common build (the pre tree, `pd_build`)
     * would never see them. Called by the pre-domain controller at the start
     * of `pd_build`. No-op at non-zero time or if the command line was
     * refreshed (`refresh_cmdline_for_late_build()` already reapplied them).
     *
     * `uvm_root::build_phase()` applies the same settings again later; type
     * overrides are replaced by identical ones and config settings are
     * written again with the same values.
     *
     * @param who Build about to start; used in the report only.
     */
    static function void apply_build_settings_for_early_build(string who);
        if (($time != 0) || is_cmdline_refreshed())
            return;
        `nv_uvm_info("NV_SOCV_CMDLINE_PROCESSOR/EARLY_BUILD",
                     {"Applying command-line factory/config settings before ", who},
                     UVM_LOW);
        apply_factory_settings();
        apply_config_settings();
    endfunction

    /** @brief The common-domain "build" node, used for config precedence. */
    static local uvm_phase m_common_build_node;

    /**
     * @brief Give config_db sets made from here on standard build-phase precedence.
     *
     * @details
     * `uvm_config_db::set()` lowers a setting's precedence by the depth of its
     * context only while `uvm_root::m_current_phase` is named "build", so that a
     * higher-level set (the command line, the test) wins over a lower-level
     * component's own default. A component built in another domain's build
     * phase (`pd_build`, `ps_build`) gets default precedence for every set, so
     * the latest set wins. Called around each such `build_phase()` call, this
     * points `m_current_phase` at the common "build" node for the duration of
     * the call.
     *
     * @return Previous `m_current_phase`; pass it to `exit_build_config_precedence()`.
     */
    static function uvm_phase enter_build_config_precedence();
        uvm_root root;

        root = uvm_root::get();
        if (m_common_build_node == null)
            m_common_build_node = uvm_domain::get_common_domain().find(uvm_build_phase::get());
        enter_build_config_precedence = root.m_current_phase;
        if (m_common_build_node != null)
            root.m_current_phase = m_common_build_node;
    endfunction

    /**
     * @brief Restore `uvm_root::m_current_phase` after `enter_build_config_precedence()`.
     * @param prev Value returned by `enter_build_config_precedence()`.
     */
    static function void exit_build_config_precedence(uvm_phase prev);
        uvm_root::get().m_current_phase = prev;
    endfunction

    /**
     * @brief Apply report action/severity/verbosity switches to a tree built late.
     *
     * @details
     * `reapply_cmdline_settings()` applies `+uvm_set_action`,
     * `+uvm_set_severity` and `+uvm_set_verbosity` only to components that
     * exist at that moment; components created afterwards get UVM's cached
     * time-0 parse. Called by the pre/post domain controllers once a tree
     * built after a command-line refresh is complete (start of its connect
     * phase), so the refreshed switches also reach the new components.
     * No-op if the command line was not refreshed in this invocation.
     *
     * @param who Tree that was built; used in the report only.
     */
    static function void reapply_report_settings_for_late_build(string who);
        string settings[$];
        uvm_cmdline_processor clp;

        if (!is_cmdline_refreshed())
            return;
        clp = get_inst();

        void'(clp.get_arg_values("+uvm_set_action=", settings));
        foreach (settings[idx])
            apply_report_action(settings[idx]);

        settings.delete();
        void'(clp.get_arg_values("+uvm_set_severity=", settings));
        foreach (settings[idx])
            apply_report_severity(settings[idx]);

        settings.delete();
        void'(clp.get_arg_values("+uvm_set_verbosity=", settings));
        foreach (settings[idx])
            apply_report_verbosity(settings[idx]);

        `nv_uvm_info("NV_SOCV_CMDLINE_PROCESSOR/LATE_BUILD",
                     {"Report action/severity/verbosity switches applied to ", who},
                     UVM_LOW);
    endfunction

endclass
`endif

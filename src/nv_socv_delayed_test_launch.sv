// SPDX-FileCopyrightText: Copyright (c) 2024-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
// SPDX-License-Identifier: Apache-2.0

`ifndef NV_SOCV_DELAYED_TEST_LAUNCH_SV
`define NV_SOCV_DELAYED_TEST_LAUNCH_SV

`include "nv_socv_report_macros.sv"
import uvm_pkg::*;

/**
 * @brief Delayed `run_test()` launcher for boot-level SOCV checkpoint restore.
 *
 * @details
 * Gates UVM topology construction until after the boot/checkpoint milestone.
 * Used by `run_test_p` to wait on the TB `test_launch_event`, suppress
 * `RUNPHSTIME`, and refresh command-line state via
 * `refresh_cmdline_parser_for_test_launch()` before `run_test()`.
 *
 * Also defines `nv_socv_config_db#(T)`, a `%uvm_config_db#(T)` drop-in for
 * code outside UVM phasing (e.g. `module` code) that needs to wait on the
 * same `test_launch_event` gate before reading config_db state.
 *
 * @startuml
 * title Boot-Level Delayed UVM Launch
 *
 * participant "run_test_p" as RunTestP
 * participant "nv_socv_delayed_test_launch" as Launcher
 * participant "SOCV TB" as TB
 * participant "nv_socv_cmdline_processor" as CLP
 * participant "UVM run_test" as UVM
 *
 * RunTestP -> Launcher : wait_for_test_launch_trigger()
 * Launcher -> Launcher : get_event()
 * TB -> Launcher : trigger_test_launch()
 * Launcher -> Launcher : suppress RUNPHSTIME
 * Launcher -> CLP : refresh_cmdline_parser_for_test_launch()
 * RunTestP -> UVM : run_test()
 * @enduml
 */

/** @brief Stateless static utility -- no instance is ever constructed. */
class nv_socv_delayed_test_launch;
    // --- TB-wide boot/checkpoint-readiness event, owned by this class ---

    local static uvm_event s_test_launch_event = null;
    local static bit s_checked_plusarg = 0;
    local static bit s_delayed_launch_active = 0;

    /**
     * @brief Name of the plusarg that gates boot-delayed launch.
     * @details Single source of truth for the literal, documented as a
     *          fixed contract in `save_restore.md`. Kept as one named
     *          constant (rather than the literal repeated at each call
     *          site) so a future rename only touches this line.
     */
    static const string LAUNCH_PLUSARG_NAME = "NV_SOCV_DELAYED_TEST_LAUNCH";

    /** @brief Is boot-delayed launch active (i.e. was `+LAUNCH_PLUSARG_NAME` given)? */
    static function bit is_delayed_launch_active ();
        return $test$plusargs(LAUNCH_PLUSARG_NAME);
    endfunction

    /**
     * @brief Lazily-constructed, process-wide `test_launch_event` handle.
     * @details Whichever side (TB producer or any consumer) calls this first
     *          constructs the event; everyone else gets the same handle. This
     *          replaces publishing/looking the event up through
     *          `uvm_config_db`, which added nothing here since the event was
     *          already stored at global scope (`null` context, `""` inst_name)
     *          -- it only cost a `wait_modified` race if a consumer asked
     *          before the TB had published.
     */
    static function uvm_event get_event ();
        if (s_test_launch_event == null) begin
            s_test_launch_event = new("test_launch_event");
        end
        return s_test_launch_event;
    endfunction

    /**
     * @brief Trigger `test_launch_event`; called by the SOCV TB once boot /
     *        checkpoint settle (Phase 1) is complete.
     */
    static task trigger_test_launch ();
        get_event().trigger();
    endtask

    /**
     * @brief Block until the boot-delayed launch gate has opened.
     * @details No-op when `+LAUNCH_PLUSARG_NAME` is not set. The bare
     *          synchronization primitive underlying `wait_for_test_launch_trigger()`
     *          (which layers `run_test_p`-specific housekeeping on top); any
     *          code that cannot rely on UVM phase ordering relative to that
     *          gate -- e.g. `module` `initial` blocks -- can call this
     *          directly too (see `nv_socv_config_db#(T)` below).
     */
    static task wait_for_test_launch_gate ();
        if (!s_checked_plusarg) begin
            s_delayed_launch_active = is_delayed_launch_active();
            s_checked_plusarg = 1;
        end
        if (!s_delayed_launch_active) begin
            return;
        end
        get_event().wait_on();
    endtask

    /**
     * @brief Wait for boot completion and perform pre-`run_test()` housekeeping.
     *
     * @details
     * No-op when `is_delayed_launch_active()` is false (self-guarded, so
     * callers need not gate the call themselves).
     * 1. Suppresses `RUNPHSTIME` UVM_FATAL so UVM can start at post-boot sim time.
     * 2. Blocks on `wait_for_test_launch_gate()` until Phase 1 completes.
     * 3. Calls `nv_socv_cmdline_processor::refresh_cmdline_parser_for_test_launch()` so
     *    the restore invocation's per-test plusargs are visible before topology build.
     *
     * After this task returns, `run_test()` may safely create the per-test UVM tree.
     */
    static task wait_for_test_launch_trigger ();
        if (!is_delayed_launch_active()) begin
            return;
        end
        uvm_root::get().set_report_severity_id_action(UVM_FATAL, "RUNPHSTIME", UVM_NO_ACTION);
        wait_for_test_launch_gate();
        nv_socv_cmdline_processor::refresh_cmdline_parser_for_test_launch();
        `nv_uvm_info("NV_SOCV_DELAYED_TEST_LUNCH", "Test launch event triggered", UVM_LOW);
    endtask
endclass

/**
 * @brief `%uvm_config_db#(T)` drop-in for call sites that may run before the
 *        SOCV boot-delayed launch gate opens.
 *
 * @details
 * Use in place of `%uvm_config_db#(T)::%get()` at any call site -- especially
 * inside `module` code or other UVM-phase-agnostic code -- where the read
 * must observe the TB's post-boot config_db state. `%get()` first blocks on
 * `nv_socv_delayed_test_launch::wait_for_test_launch_gate()`, then performs
 * the normal `%uvm_config_db#(T)::%get()`.
 *
 * Waiting on the launch gate alone is not sufficient: `test_launch_event`
 * wakes every blocked waiter (this call site and `run_test_p`) in the same
 * time step, and SystemVerilog does not guarantee their relative resumption
 * order. If this call site resumes and calls `%uvm_config_db#(T)::%get()`
 * before `run_test_p` resumes, calls `run_test()`, and reaches the
 * `build_phase` that actually publishes the field, the lookup can still
 * miss. So on a miss, `%get()` falls back to `%uvm_config_db#(T)::%wait_modified()`,
 * which blocks until the field is actually written regardless of process
 * wake-up order, then retries -- bounded by the `TIMEOUT` class parameter
 * so a genuine miss (typo'd field/inst name, `%set()` never called at all)
 * surfaces as a `%nv_uvm_warning` and `success == 0` after `TIMEOUT`, instead
 * of hanging the simulation. As with plain `%uvm_config_db#(T)::%get()`, the
 * caller decides what to do with a failed `success` -- fatal, retry, or
 * tolerate it.
 *
 * `TIMEOUT` defaults to `1fs` -- the smallest resolvable delay at this
 * package's `` `timeunit 1fs ``/`` `timeprecision 1fs `` -- so a genuine miss
 * fails fast by default. Call sites that expect the value to arrive some
 * known time after the launch gate opens should pass an explicit, larger
 * `TIMEOUT`:
 * @code
 * nv_socv_config_db#(virtual my_if, 50us)::get(...);
 * nv_socv_config_db#(.T(virtual my_if), .TIMEOUT(500us))::get(...);
 * @endcode
 *
 * `%get()` is a `task` rather than a `function` because it may block; the
 * success bit is returned via an `output` argument instead of a return
 * value:
 * @code
 * bit found;
 * nv_socv_config_db#(virtual my_if)::get(null, "", "my_if", vif, found);
 * if (!found) ...
 * @endcode
 *
 * `%set()` is a thin pass-through -- publishing config is never ordered
 * against the launch gate, so it does not need to wait.
 */
class nv_socv_config_db#(type T = int, realtime TIMEOUT = 1fs);
    /**
     * @brief Race `%uvm_config_db#(T)::%wait_modified()` against `TIMEOUT` without
     *        writing `%get()`'s `ref`/`output` arguments from inside the fork.
     * @details SystemVerilog forbids writing a task's `ref`/`output` arguments
     *          from inside a `fork...join_any` (they alias the caller's stack
     *          frame, which the compiler cannot prove outlives the fork) --
     *          Xcelium enforces this as a hard compile error. Plain task-local
     *          variables are not subject to that restriction (only the formal
     *          `ref`/`output` port arguments are), so the fork branches write
     *          `found`/`val` instead; `%get()` is declared `automatic` so each
     *          call gets its own independent copies, safe for concurrent
     *          overlapping callers. The real `ref`/`output` arguments are only
     *          assigned once, after `join_any`/`disable fork`, back in `%get()`'s
     *          own (non-forked) flow.
     */
    static task automatic get(uvm_component cntxt, string inst_name, string field_name,
                     ref T value, output bit success);
        bit found = 0;
        T val;
        nv_socv_delayed_test_launch::wait_for_test_launch_gate();
        found = uvm_config_db#(T)::get(cntxt, inst_name, field_name, val);
        if (!found) begin
            fork
                begin
                    uvm_config_db#(T)::wait_modified(cntxt, inst_name, field_name);
                    found = uvm_config_db#(T)::get(cntxt, inst_name, field_name, val);
                end
                begin
                    #(TIMEOUT);
                    if (!found) begin
                        `nv_uvm_warning("NV_SOCV_CONFIG_DB_TIMEOUT",
                            $sformatf("uvm_config_db#(...)::get(\"%s\") timed out after %0t -- was set() ever called for this field/inst_name?",
                                      field_name, TIMEOUT));
                    end
                end
            join_any
            disable fork;
        end
        value = val;
        success = found;
    endtask

    static function void set(uvm_component cntxt, string inst_name, string field_name, T value);
        uvm_config_db#(T)::set(cntxt, inst_name, field_name, value);
    endfunction
endclass

`endif

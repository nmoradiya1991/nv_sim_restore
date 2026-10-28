// SPDX-FileCopyrightText: Copyright (c) 2024-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
`ifndef NV_SOCV_PRE_DOMAIN_SV
`define NV_SOCV_PRE_DOMAIN_SV

`include "uvm_macros.svh"
`include "nv_socv_report_macros.sv"
import uvm_pkg::*;

/**
 * @file nv_socv_pre_domain.sv
 * @brief Pre domain: a pre test whose run phase keeps going while the main
 *        UVM test runs. The main test is built when release_main() is called.
 *
 * @details
 * @code
 *   pd_build -> pd_connect -> pd_eoe -> pd_sos -> pd_gate
 *       -> main build -> ... -> main run (|| uvm runtime) -> ... -> main final
 *       -> pd_extract -> pd_check -> pd_report -> pd_final
 * @endcode
 *
 * - pd_run    : pd_sos -> pd_extract, in parallel with everything between,
 *               so the pre tree's run_phase stays alive through the main test.
 * - pre_sched : pre runtime phases (pre_reset .. post_shutdown), in parallel
 *               with pd_run. They do NOT gate the main test.
 * - pd_gate   : holds the main build until release_main() is called.
 *
 * "pd_" = pre domain. It is unrelated to UVM's own pre_/post_ runtime phases
 * (pre_reset, post_main, ...), which keep their normal names in the pre tree.
 *
 * The pd_* phase classes only call the normal build_phase(), run_phase(), ...
 * methods: components implement the standard methods, nothing pd_-specific.
 * Separate classes keep common.find(uvm_build_phase/uvm_run_phase) on the
 * standard nodes, so main-test creation and domain-aware VIP in the main test
 * behave exactly as in a normal UVM run.
 *
 * Command line: right before pd_build and before the main build, the command
 * line is reprocessed with
 * `nv_socv_cmdline_processor::refresh_cmdline_for_late_build()` (no-op at
 * time 0 or if already refreshed in this invocation). At time 0, pd_build
 * runs before uvm_root::build_phase(), so the command-line factory/config
 * settings are applied for the pre tree at the start of pd_build
 * (`apply_build_settings_for_early_build()`). In pd_build, config_db sets
 * get the standard build-phase precedence (`enter_build_config_precedence()`),
 * so `+uvm_set_config_*` wins over a pre-tree component's own set, as in a
 * normal build. The main test is then
 * `uvm_test_top` if run_test() already created it, else `+UVM_TESTNAME` from
 * the reprocessed command line, else install_pre_domain()'s main_test.
 *
 * Entry point: install_pre_domain() -- call from the top module before
 * run_test(). See the usage section at the end of this file.
 */

typedef class pre_domain_controller;


// ----------------------------------------------------------------------------
// 1. Pre-domain phase classes. Each one calls the standard phase method.
// ----------------------------------------------------------------------------
class pd_build_phase extends uvm_topdown_phase;
  local static pd_build_phase m_inst;
  pre_domain_controller ctl;
  function new(string name = "pd_build");
    super.new(name);
  endfunction
  static function pd_build_phase get();
    if (m_inst == null) m_inst = new();
    return m_inst;
  endfunction
  // Children are visited after this returns, and the domain filter is
  // evaluated per child at that point: adopting here gets them built.
  // Components whose build_phase already ran (a parent called
  // child.build_phase() itself) are skipped, as UVM does for "build" only.
  // config_db sets made by build_phase() get the standard build-phase
  // precedence (higher level wins), as in the common build.
  virtual function void exec_func(uvm_component comp, uvm_phase phase);
    uvm_phase prev;
    if (!comp.m_build_done) begin
      prev = nv_socv_cmdline_processor::enter_build_config_precedence();
      comp.build_phase(phase);
      nv_socv_cmdline_processor::exit_build_config_precedence(prev);
    end
    if (ctl != null)
      ctl.adopt_children(comp);
  endfunction
endclass

class pd_connect_phase extends uvm_bottomup_phase;
  local static pd_connect_phase m_inst;
  function new(string name = "pd_connect");
    super.new(name);
  endfunction
  static function pd_connect_phase get();
    if (m_inst == null) m_inst = new();
    return m_inst;
  endfunction
  virtual function void exec_func(uvm_component comp, uvm_phase phase);
    comp.connect_phase(phase);
  endfunction
endclass

class pd_end_of_elaboration_phase extends uvm_bottomup_phase;
  local static pd_end_of_elaboration_phase m_inst;
  function new(string name = "pd_end_of_elaboration");
    super.new(name);
  endfunction
  static function pd_end_of_elaboration_phase get();
    if (m_inst == null) m_inst = new();
    return m_inst;
  endfunction
  virtual function void exec_func(uvm_component comp, uvm_phase phase);
    comp.end_of_elaboration_phase(phase);
  endfunction
endclass

class pd_start_of_simulation_phase extends uvm_bottomup_phase;
  local static pd_start_of_simulation_phase m_inst;
  function new(string name = "pd_start_of_simulation");
    super.new(name);
  endfunction
  static function pd_start_of_simulation_phase get();
    if (m_inst == null) m_inst = new();
    return m_inst;
  endfunction
  virtual function void exec_func(uvm_component comp, uvm_phase phase);
    comp.start_of_simulation_phase(phase);
  endfunction
endclass

class pd_run_phase extends uvm_task_phase;
  local static pd_run_phase m_inst;
  function new(string name = "pd_run");
    super.new(name);
  endfunction
  static function pd_run_phase get();
    if (m_inst == null) m_inst = new();
    return m_inst;
  endfunction
  virtual task exec_task(uvm_component comp, uvm_phase phase);
    comp.run_phase(phase);
  endtask
endclass

class pd_extract_phase extends uvm_bottomup_phase;
  local static pd_extract_phase m_inst;
  function new(string name = "pd_extract");
    super.new(name);
  endfunction
  static function pd_extract_phase get();
    if (m_inst == null) m_inst = new();
    return m_inst;
  endfunction
  virtual function void exec_func(uvm_component comp, uvm_phase phase);
    comp.extract_phase(phase);
  endfunction
endclass

class pd_check_phase extends uvm_bottomup_phase;
  local static pd_check_phase m_inst;
  function new(string name = "pd_check");
    super.new(name);
  endfunction
  static function pd_check_phase get();
    if (m_inst == null) m_inst = new();
    return m_inst;
  endfunction
  virtual function void exec_func(uvm_component comp, uvm_phase phase);
    comp.check_phase(phase);
  endfunction
endclass

class pd_report_phase extends uvm_bottomup_phase;
  local static pd_report_phase m_inst;
  function new(string name = "pd_report");
    super.new(name);
  endfunction
  static function pd_report_phase get();
    if (m_inst == null) m_inst = new();
    return m_inst;
  endfunction
  virtual function void exec_func(uvm_component comp, uvm_phase phase);
    comp.report_phase(phase);
  endfunction
endclass

class pd_final_phase extends uvm_topdown_phase;
  local static pd_final_phase m_inst;
  function new(string name = "pd_final");
    super.new(name);
  endfunction
  static function pd_final_phase get();
    if (m_inst == null) m_inst = new();
    return m_inst;
  endfunction
  virtual function void exec_func(uvm_component comp, uvm_phase phase);
    comp.final_phase(phase);
  endfunction
endclass


// ----------------------------------------------------------------------------
// 2. No-op imps: silence the pre tree for the standard (main) pass, and the
//    root's standard run_phase (it starts at non-zero time and would fail
//    the RUNPHSTIME check).
// ----------------------------------------------------------------------------
class pre_domain_noop_func_phase extends uvm_bottomup_phase;
  function new(string name = "pre_domain_noop_func");
    super.new(name);
  endfunction
  virtual function void exec_func(uvm_component comp, uvm_phase phase);
  endfunction
endclass

class pre_domain_noop_task_phase extends uvm_task_phase;
  function new(string name = "pre_domain_noop_task");
    super.new(name);
  endfunction
  virtual task exec_task(uvm_component comp, uvm_phase phase);
  endtask
endclass


// ----------------------------------------------------------------------------
// 3. Catcher. The root checks the error count at the standard
//    end_of_elaboration (BUILDERR). Suppressed only if the count is
//    unchanged since the standard build started, i.e. only pre-test errors
//    exist.
// ----------------------------------------------------------------------------
class pre_domain_catcher extends uvm_report_catcher;
  bit guard_builderr;
  int error_baseline;

  function new(string name = "pre_domain_catcher");
    super.new(name);
  endfunction

  virtual function action_e catch();
    if (guard_builderr && get_id() == "BUILDERR") begin
      uvm_report_server srv = uvm_report_server::get_server();
      if (srv.get_severity_count(UVM_ERROR) == error_baseline)
        return CAUGHT;
    end
    return THROW;
  endfunction
endclass


// ----------------------------------------------------------------------------
// 4. Gate: last node in front of the main build. Waits for release_main().
//    Only pre_dom members run pre_dom's nodes, so the work is done on
//    uvm_pre_top.
// ----------------------------------------------------------------------------
class pre_domain_gate_phase extends uvm_task_phase;
  pre_domain_controller ctl;

  function new(string name = "pd_gate");
    super.new(name);
  endfunction

  virtual task exec_task(uvm_component comp, uvm_phase phase);
    if (comp != ctl.pre_top)
      return;
    phase.raise_objection(comp, "holding the main test");
    ctl.wait_for_release();
    phase.drop_objection(comp, "releasing the main test");
  endtask
endclass


// ----------------------------------------------------------------------------
// 5. Controller.
// ----------------------------------------------------------------------------
class pre_domain_controller extends uvm_phase_cb;
  // ---- Pre test
  string                     pre_test;
  string                     pre_inst_name = "uvm_pre_top";
  uvm_component              pre_top;
  uvm_domain                 pre_dom;
  uvm_phase                  pd_build;         // pre_dom nodes
  uvm_phase                  pd_connect;
  uvm_phase                  pd_eoe;
  uvm_phase                  pd_gate;
  uvm_phase                  pd_run;

  // ---- Gate
  uvm_event                  main_go         = new("pre_domain_main_go");
  int unsigned               gate_timeout_ns = 0;  // 0 = wait forever
  time                       released_at;

  // ---- Main test / standard pass
  string                     main_default;      // install argument
  string                     main_test;
  uvm_component              main_top;
  uvm_phase                  std_build, std_connect, std_eoe, std_run, std_final;

  // Builds that started at non-zero time: their trees get the report
  // switches re-applied at the start of their connect phase.
  local bit                  m_pre_build_refreshed;
  local bit                  m_main_build_refreshed;

  pre_domain_catcher         catcher;
  pre_domain_noop_func_phase noop_f;
  pre_domain_noop_task_phase noop_t;

  // ---- Adoption / exclusion (see adopt_into_pre_domain(),
  //      exclude_from_pre_domain())
  string                     adopt_patterns[$];
  bit                        adopt_return[$];
  string                     excluded_patterns[$];

  local uvm_domain           m_adopted_from[uvm_component];
  local bit                  m_return_at_release[uvm_component];

  local bit                  m_bindings_resolved;
  local bit                  m_defseq_reported[uvm_component];
  local bit                  m_inert[uvm_component];

  // ---- Foreign phase callbacks (see m_filter_foreign_cbs()).
  string                     foreign_cb_patterns[$] = '{"uvm_ml_phase_cb*"};
  local uvm_phase_cb         m_foreign_cbs[$];

  function new(string name = "pre_domain_controller");
    super.new(name);
  endfunction

  // --------------------------------------------------------------------------
  // UVM-ML 2.x handles function phases of the "common" and "uvm" domains
  // only: for any other domain it looks the phase up by name in "uvm" and
  // dereferences the null result (NOA in export_transmit_phase). Phase
  // callbacks whose name matches foreign_cb_patterns are switched off
  // while a pd_* node of pre_dom changes state and back on for every other
  // node (including pre_dom's runtime phases, which UVM-ML accepts in any
  // domain). This callback is prepended, so it runs before them.
  // --------------------------------------------------------------------------
  function void m_filter_foreign_cbs(uvm_phase phase);
    bit  hide;
    uvm_phase imp;

    if (m_foreign_cbs.size() == 0) begin
      uvm_callback_iter#(uvm_phase, uvm_phase_cb) it = new(phase);
      for (uvm_phase_cb cb = it.first(); cb != null; cb = it.next())
        if (cb != this)
          foreach (foreign_cb_patterns[i])
            if (uvm_is_match(foreign_cb_patterns[i], cb.get_name())) begin
              m_foreign_cbs.push_back(cb);
              break;
            end
      if (m_foreign_cbs.size() == 0)
        return;
      `uvm_info("PREDOM/FOREIGN_CB", $sformatf(
        "%0d phase callback(s) hidden from the pd_* phases (e.g. '%s')",
        m_foreign_cbs.size(), m_foreign_cbs[0].get_name()), UVM_LOW)
    end

    imp  = phase.get_imp();
    hide = (phase.get_domain() == pre_dom) && imp != null &&
           uvm_is_match("pd_*", imp.get_name());
    foreach (m_foreign_cbs[i])
      void'(m_foreign_cbs[i].callback_mode(!hide));
  endfunction

  // --------------------------------------------------------------------------
  // Adopt pre-tree components that move themselves into their own domain
  // in their constructor (e.g. c_wrapper -> c_phase_domain).
  // Right after the parent's build_phase creates such a component, it is
  // moved back into pre_dom (with its subtree), so it is built and gets
  // all pd_* and pre runtime phases like any other pre-tree component.
  // Its own domain stays in the phase graph with no components.
  // Glob patterns on the full name, e.g. "uvm_pre_top.*.c_test_wrapper".
  // Call before pd_build reaches the parent (tb_top after
  // install_pre_domain(), or the pre test's build_phase).
  //
  // return_at_release = 1: only build .. start_of_simulation and run_phase
  // happen in the pre domain; its runtime phases (pre_reset ..
  // post_shutdown) are no-ops there. When the gate opens, the runtime
  // phase methods are restored and the subtree goes back to its own
  // domain, so its runtime phases run once, with the main test.
  // --------------------------------------------------------------------------
  function void adopt_into_pre_domain(string pattern,
                                      bit    return_at_release = 0);
    adopt_patterns.push_back(pattern);
    adopt_return.push_back(return_at_release);
  endfunction

  virtual function void adopt_children(uvm_component parent);
    uvm_component kids[$];

    if (adopt_patterns.size() == 0 || parent.get_domain() != pre_dom)
      return;
    parent.get_children(kids);
    foreach (kids[i]) begin
      uvm_domain d   = kids[i].get_domain();
      bit        hit = 0;
      bit        ret = 0;

      if (d == pre_dom)
        continue;
      foreach (adopt_patterns[p])
        if (uvm_is_match(adopt_patterns[p], kids[i].get_full_name())) begin
          hit = 1;
          ret |= adopt_return[p];
        end
      if (!hit)
        continue;

      m_adopted_from[kids[i]] = d;
      if (ret)
        m_return_at_release[kids[i]] = 1;
      kids[i].set_domain(pre_dom, 1);
      begin
        string from   = (d == null) ? "<null>" : d.get_name();
        string suffix = "";
        if (ret)
          suffix = " (runtime phases deferred: it returns to its own domain when the gate opens)";
        `uvm_info("PREDOM/ADOPTED", $sformatf({
          "%s moved itself to domain '%s'; adopted back into '%s' before ",
          "pd_build, so it is built and phased as part of the pre test%s."},
          kids[i].get_full_name(), from, pre_dom.get_name(), suffix),
          UVM_LOW)
      end
    end
  endfunction

  // restore = 0: runtime phase methods -> no-op; 1: back to the real ones.
  local function void m_set_runtime_imps(uvm_component c, bit restore);
    uvm_phase imps[$];
    imps.push_back(uvm_pre_reset_phase::get());
    imps.push_back(uvm_reset_phase::get());
    imps.push_back(uvm_post_reset_phase::get());
    imps.push_back(uvm_pre_configure_phase::get());
    imps.push_back(uvm_configure_phase::get());
    imps.push_back(uvm_post_configure_phase::get());
    imps.push_back(uvm_pre_main_phase::get());
    imps.push_back(uvm_main_phase::get());
    imps.push_back(uvm_post_main_phase::get());
    imps.push_back(uvm_pre_shutdown_phase::get());
    imps.push_back(uvm_shutdown_phase::get());
    imps.push_back(uvm_post_shutdown_phase::get());
    foreach (imps[i])
      c.set_phase_imp(imps[i], (restore ? imps[i] : noop_t), 1);
  endfunction

  // At pd_connect (subtree fully built): defer runtime phases.
  virtual function void defer_returning_runtime();
    foreach (m_return_at_release[c])
      m_set_runtime_imps(c, 0);
  endfunction

  // At gate open (main build starting): restore and return.
  virtual function void return_adopted();
    foreach (m_return_at_release[c]) begin
      uvm_domain d = m_adopted_from[c];
      m_set_runtime_imps(c, 1);
      c.set_domain(d, 1);
      `uvm_info("PREDOM/RETURNED", $sformatf({
        "%s returned to domain '%s' at gate open; its runtime phases run ",
        "with the main test."}, c.get_full_name(),
        (d == null ? "<null>" : d.get_name())), UVM_LOW)
    end
  endfunction

  // --------------------------------------------------------------------------
  // Exclude unused pre-tree components (and everything under them) from
  // the pre-domain checks, and make them inert: every phase method, in
  // the pre domain, the main pass and their own domain, becomes a no-op.
  // Use for components the pre test does not need that move themselves
  // into their own domain (e.g. a domain-aware VIP). Glob patterns on the
  // full name, e.g. "uvm_pre_top.*.c_test_wrapper". Call before pd_connect
  // (tb_top after install_pre_domain(), or the pre test's build_phase).
  // --------------------------------------------------------------------------
  function void exclude_from_pre_domain(string pattern);
    excluded_patterns.push_back(pattern);
  endfunction

  function bit is_excluded(uvm_component c);
    for (uvm_component p = c; p != null && p != pre_top; p = p.get_parent())
      foreach (excluded_patterns[i])
        if (uvm_is_match(excluded_patterns[i], p.get_full_name()))
          return 1;
    return 0;
  endfunction

  virtual function void make_inert(uvm_component c);
    if (m_inert.exists(c))
      return;
    m_inert[c] = 1;

    // pre-domain nodes
    c.set_phase_imp(pd_build_phase::get(),               noop_f, 1);
    c.set_phase_imp(pd_connect_phase::get(),             noop_f, 1);
    c.set_phase_imp(pd_end_of_elaboration_phase::get(),  noop_f, 1);
    c.set_phase_imp(pd_start_of_simulation_phase::get(), noop_f, 1);
    c.set_phase_imp(pd_run_phase::get(),                 noop_t, 1);
    c.set_phase_imp(pd_extract_phase::get(),             noop_f, 1);
    c.set_phase_imp(pd_check_phase::get(),               noop_f, 1);
    c.set_phase_imp(pd_report_phase::get(),              noop_f, 1);
    c.set_phase_imp(pd_final_phase::get(),               noop_f, 1);

    // standard common nodes
    c.set_phase_imp(uvm_build_phase::get(),               noop_f, 1);
    c.set_phase_imp(uvm_connect_phase::get(),             noop_f, 1);
    c.set_phase_imp(uvm_end_of_elaboration_phase::get(),  noop_f, 1);
    c.set_phase_imp(uvm_start_of_simulation_phase::get(), noop_f, 1);
    c.set_phase_imp(uvm_run_phase::get(),                 noop_t, 1);
    c.set_phase_imp(uvm_extract_phase::get(),             noop_f, 1);
    c.set_phase_imp(uvm_check_phase::get(),               noop_f, 1);
    c.set_phase_imp(uvm_report_phase::get(),              noop_f, 1);
    c.set_phase_imp(uvm_final_phase::get(),               noop_f, 1);

    // runtime nodes, in whatever domain the component is in
    c.set_phase_imp(uvm_pre_reset_phase::get(),      noop_t, 1);
    c.set_phase_imp(uvm_reset_phase::get(),          noop_t, 1);
    c.set_phase_imp(uvm_post_reset_phase::get(),     noop_t, 1);
    c.set_phase_imp(uvm_pre_configure_phase::get(),  noop_t, 1);
    c.set_phase_imp(uvm_configure_phase::get(),      noop_t, 1);
    c.set_phase_imp(uvm_post_configure_phase::get(), noop_t, 1);
    c.set_phase_imp(uvm_pre_main_phase::get(),       noop_t, 1);
    c.set_phase_imp(uvm_main_phase::get(),           noop_t, 1);
    c.set_phase_imp(uvm_post_main_phase::get(),      noop_t, 1);
    c.set_phase_imp(uvm_pre_shutdown_phase::get(),   noop_t, 1);
    c.set_phase_imp(uvm_shutdown_phase::get(),       noop_t, 1);
    c.set_phase_imp(uvm_post_shutdown_phase::get(),  noop_t, 1);

    `uvm_info("PREDOM/EXCLUDED", $sformatf({
      "%s (domain '%s') is excluded from the pre-domain checks and made ",
      "inert: its phase methods are no-ops in the pre domain, the main ",
      "pass and its own domain."},
      c.get_full_name(),
      (c.get_domain() == null ? "<null>" : c.get_domain().get_name())),
      UVM_LOW)
  endfunction

  // --------------------------------------------------------------------------
  // Starts the main test. Static: callable from anywhere in the TB without
  // a controller handle (pre_domain_controller::release_main(), or the
  // package function pd_release_main()); ctl.release_main() also works.
  // Later calls are ignored. A call before install_pre_domain() is kept
  // and applied when the controller is installed.
  // --------------------------------------------------------------------------
  static pre_domain_controller m_inst;
  local static bit             m_pending;
  local static string          m_pending_reason;
  local static time            m_pending_at;

  static function pre_domain_controller get_inst();
    return m_inst;
  endfunction

  static function void release_main(string reason = "");
    if (m_inst == null) begin
      if (!m_pending) begin
        m_pending        = 1;
        m_pending_reason = reason;
        m_pending_at     = $time;
      end
      return;
    end
    m_inst.m_release(reason, $time);
  endfunction

  // Applies a release_main() call made before install_pre_domain().
  function void m_apply_pending_release();
    if (!m_pending)
      return;
    m_pending = 0;
    m_release({m_pending_reason, " (called before install_pre_domain())"},
              m_pending_at);
  endfunction

  virtual function void m_release(string reason, time at);
    if (main_go.is_on())
      return;
    released_at = at;
    `uvm_info("PREDOM/GATE",
      {"Main test released", (reason == "" ? "" : {": ", reason})}, UVM_LOW)
    main_go.trigger();
  endfunction

  virtual task wait_for_release();
    if (gate_timeout_ns == 0) begin
      main_go.wait_on();
      return;
    end
    fork
      begin
        fork
          main_go.wait_on();
          begin
            #(gate_timeout_ns * 1ns);
            `uvm_fatal("PREDOM/GATE", $sformatf(
              "Pre test did not call release_main() within %0d ns", gate_timeout_ns))
          end
        join_any
        disable fork;
      end
    join
  endtask

  // --------------------------------------------------------------------------
  // Phase callback.
  // --------------------------------------------------------------------------
  virtual function void phase_state_change(uvm_phase phase,
                                           uvm_phase_state_change change);
    uvm_phase_state s = change.get_state();

    m_filter_foreign_cbs(phase);

    // ---------------- pre domain ----------------
    if (phase == pd_build && s == UVM_PHASE_STARTED) begin
      nv_socv_cmdline_processor::refresh_cmdline_for_late_build("the pre-domain build");
      nv_socv_cmdline_processor::apply_build_settings_for_early_build("the pre-domain build");
      m_pre_build_refreshed = ($time != 0);
    end
    else if (phase == pd_connect && s == UVM_PHASE_STARTED) begin
      check_pre_domains("start of pd_connect");
      defer_returning_runtime();
      if (m_pre_build_refreshed)
        nv_socv_cmdline_processor::reapply_report_settings_for_late_build("the pre tree");
    end
    else if (phase == pd_run && s == UVM_PHASE_STARTED) begin
      check_pre_default_sequences("start of pd_run");
    end
    else if (phase == pd_eoe && s == UVM_PHASE_STARTED) begin
      // UVM resolves bindings when the root starts end_of_elaboration;
      // the root is not in pre_dom, so do it here for the pre tree.
      if (!m_bindings_resolved) begin
        m_bindings_resolved = 1;
        uvm_root::get().do_resolve_bindings();
      end
    end

    // ---------------- standard pass ----------------
    else if (phase == std_build && s == UVM_PHASE_STARTED) begin
      uvm_root          top = uvm_root::get();
      uvm_report_server srv = uvm_report_server::get_server();

      check_pre_domains("start of the main build");
      catcher.error_baseline = srv.get_severity_count(UVM_ERROR);
      silence_pre_tree();
      return_adopted();

      nv_socv_cmdline_processor::refresh_cmdline_for_late_build("the main-test build");
      m_main_build_refreshed = ($time != 0);

      if (top.has_child("uvm_test_top")) begin
        // Created by run_test() / +UVM_TESTNAME at time 0. The domain
        // filter kept it out of pre_dom; nothing else to do.
        main_top = top.get_child("uvm_test_top");
      end
      else begin
        resolve_main_test();
        if (main_test == "")
          `uvm_fatal("PREDOM/NOTEST",
            "No main test: give +UVM_TESTNAME (or run_test(<name>)), or install_pre_domain(pre_test, main_test)")
      end

      prepare_main_test();

      if (main_top == null)
        create_main_test();
    end
    else if (phase == std_connect && s == UVM_PHASE_STARTED) begin
      if (m_main_build_refreshed)
        nv_socv_cmdline_processor::reapply_report_settings_for_late_build("the main test");
    end
    else if (phase == std_eoe) begin
      if (s == UVM_PHASE_STARTED)   catcher.guard_builderr = 1;
      else if (s == UVM_PHASE_DONE) catcher.guard_builderr = 0;
    end
    else if (phase == std_run && s == UVM_PHASE_STARTED) begin
      // Last chance: the main run is about to start "run_phase" default
      // sequences on every sequencer, including the pre tree's.
      check_pre_default_sequences("start of the main run");
    end
  endfunction

  // --------------------------------------------------------------------------
  // Protection 1: every pre-tree component must stay in pre_dom. One that
  // moves (typically a domain-aware VIP calling set_domain()) stops
  // getting the pd_* phases, and children it creates after set_domain()
  // are never built. Fatal, so the run stops at the cause.
  // --------------------------------------------------------------------------
  virtual function void check_pre_domains(string when);
    uvm_component all[$];
    int           n_bad;

    m_collect(pre_top, all);
    foreach (all[i]) begin
      uvm_domain d = all[i].get_domain();
      if (is_excluded(all[i])) begin
        make_inert(all[i]);
        continue;
      end
      if (d != pre_dom) begin
        n_bad++;
        `uvm_error("PREDOM/PRE_DOMAIN", $sformatf({
          "%s is in domain '%s', not '%s' (found at %s). ",
          "Components under %s must stay in '%s', otherwise they do not ",
          "get the pd_* phases (pd_build, pd_run, ...): if the domain was ",
          "changed in the constructor, its build_phase was skipped; ",
          "children created after the change are never built. This is ",
          "usually a domain-aware VIP calling set_domain(). To keep it ",
          "working in the pre test, adopt it back into the pre domain: ",
          "ctl.adopt_into_pre_domain(\"%s\") or +PREDOM_ADOPT=%s. If the ",
          "pre test does not use it, make it inert instead: ",
          "ctl.exclude_from_pre_domain(\"%s\") or +PREDOM_EXCLUDE=%s."},
          all[i].get_full_name(), (d == null ? "<null>" : d.get_name()),
          pre_dom.get_name(), when, pre_inst_name, pre_dom.get_name(),
          all[i].get_full_name(), all[i].get_full_name(),
          all[i].get_full_name(), all[i].get_full_name()))
      end
    end
    if (n_bad > 0)
      `uvm_fatal("PREDOM/PRE_DOMAIN", $sformatf(
        "%0d pre-tree component(s) left the '%s' domain; see the PREDOM/PRE_DOMAIN errors above",
        n_bad, pre_dom.get_name()))
  endfunction

  // --------------------------------------------------------------------------
  // Protection 2: a "run_phase" default sequence on a pre-tree sequencer
  // does not start in pd_run (wrong phase name) but does start when the
  // main run begins. Reported once per sequencer.
  // --------------------------------------------------------------------------
  virtual function void check_pre_default_sequences(string when);
    uvm_component all[$];

    m_collect(pre_top, all);
    foreach (all[i]) begin
      uvm_sequencer_base seqr;
      uvm_object_wrapper wrapper;
      uvm_sequence_base  seq;
      bit                found = 0;

      if (!$cast(seqr, all[i]) || m_defseq_reported.exists(all[i])
          || is_excluded(all[i]))
        continue;
      if (uvm_config_db#(uvm_object_wrapper)::get(seqr, "run_phase",
            "default_sequence", wrapper) && wrapper != null)
        found = 1;
      if (uvm_config_db#(uvm_sequence_base)::get(seqr, "run_phase",
            "default_sequence", seq) && seq != null)
        found = 1;

      if (found) begin
        m_defseq_reported[all[i]] = 1;
        `uvm_error("PREDOM/PRE_DEFSEQ", $sformatf({
          "%s has a 'run_phase' default_sequence (found at %s). In the ",
          "pre domain the run phase is named 'pd_run', so this sequence ",
          "does NOT start with the pre test; it starts when the MAIN ",
          "test's run phase begins instead. Set it on 'pd_run_phase', or ",
          "on a runtime phase such as 'main_phase'."},
          seqr.get_full_name(), when))
      end
    end
  endfunction

  function void m_collect(uvm_component c, ref uvm_component q[$]);
    uvm_component kids[$];
    q.push_back(c);
    c.get_children(kids);
    foreach (kids[i])
      m_collect(kids[i], q);
  endfunction

  // --------------------------------------------------------------------------
  // The standard common phases visit every component, so the pre tree is
  // silenced for them. Done at the standard build, when the pre tree is
  // fully built (set_phase_imp() only reaches existing children). The pre
  // nodes use their own imps, so they are not affected.
  // --------------------------------------------------------------------------
  virtual function void silence_pre_tree();
    pre_top.set_phase_imp(uvm_build_phase::get(),               noop_f, 1);
    pre_top.set_phase_imp(uvm_connect_phase::get(),             noop_f, 1);
    pre_top.set_phase_imp(uvm_end_of_elaboration_phase::get(),  noop_f, 1);
    pre_top.set_phase_imp(uvm_start_of_simulation_phase::get(), noop_f, 1);
    pre_top.set_phase_imp(uvm_extract_phase::get(),             noop_f, 1);
    pre_top.set_phase_imp(uvm_check_phase::get(),               noop_f, 1);
    pre_top.set_phase_imp(uvm_report_phase::get(),              noop_f, 1);
    pre_top.set_phase_imp(uvm_final_phase::get(),               noop_f, 1);
    pre_top.set_phase_imp(uvm_run_phase::get(),                 noop_t, 1);
  endfunction

  // +UVM_TESTNAME from the (reprocessed) UVM command line, else
  // install_pre_domain()'s main_test.
  virtual function void resolve_main_test();
    uvm_cmdline_processor clp = uvm_cmdline_processor::get_inst();
    string                names[$];

    main_test = main_default;
    if (clp.get_arg_values("+UVM_TESTNAME=", names) > 0) begin
      main_test = names[0];
      if (names.size() > 1)
        `uvm_warning("PREDOM/MULTTST", $sformatf(
          "Multiple +UVM_TESTNAME values; using the first: %s", main_test))
    end
  endfunction

  // Hook for extra work before the main test is created (e.g. factory reset).
  virtual function void prepare_main_test();
  endfunction

  virtual function void create_main_test();
    uvm_coreservice_t cs      = uvm_coreservice_t::get();
    uvm_factory       factory = cs.get_factory();

    if (!$cast(main_top, factory.create_component_by_name(
                           main_test, "", "uvm_test_top", null))
        || main_top == null)
      `uvm_fatal("PREDOM/INVTST", {"Requested test '", main_test,
                                   "' not found or is not a uvm_component"})

    `uvm_info("PREDOM", {"Running test ", main_test}, UVM_LOW)
  endfunction
endclass


// ----------------------------------------------------------------------------
// 6. INSTALLER. Call from the top module before run_test().
//
//   pre_test    : type name of the pre test (registered with the factory)
//   main_test   : main test type name, used only when run_test() creates no
//                 test and the command line has no +UVM_TESTNAME
//   domain_name : name of the pre domain
// ----------------------------------------------------------------------------
function automatic pre_domain_controller install_pre_domain(
    string pre_test,
    string main_test   = "",
    string domain_name = "pre_dom");

  uvm_coreservice_t     cs        = uvm_coreservice_t::get();
  uvm_factory           factory   = cs.get_factory();
  uvm_root              top       = uvm_root::get();
  uvm_domain            common    = uvm_domain::get_common_domain();
  pre_domain_controller ctl       = new();
  uvm_domain            pre_dom   = new(domain_name);
  uvm_phase             pre_sched = new("uvm_sched", UVM_PHASE_SCHEDULE);
  pre_domain_gate_phase gate      = new();
  uvm_phase             sos_node, ext_node, chk_node, rpt_node;
  uvm_phase             b, r;

  if (pre_domain_controller::m_inst != null)
    `uvm_fatal("PREDOM", "install_pre_domain() called twice; only one pre domain is supported")

  // ---- Capture the STANDARD nodes before inserting anything.
  ctl.std_build   = common.find(uvm_build_phase::get());
  ctl.std_connect = common.find(uvm_connect_phase::get());
  ctl.std_eoe     = common.find(uvm_end_of_elaboration_phase::get());
  ctl.std_run   = common.find(uvm_run_phase::get());
  ctl.std_final = common.find(uvm_final_phase::get());

  if (ctl.std_build == null || ctl.std_connect == null || ctl.std_eoe == null ||
      ctl.std_run   == null || ctl.std_final == null)
    `uvm_fatal("PREDOM", "Standard phase nodes not found in the common domain")

  gate.ctl = ctl;

  // ---- 1. Head, in front of the main build: setup phases + gate.
  pre_dom.add(pd_build_phase::get());
  pre_dom.add(pd_connect_phase::get());
  pre_dom.add(pd_end_of_elaboration_phase::get());
  pre_dom.add(pd_start_of_simulation_phase::get());
  pre_dom.add(gate);
  common.add(pre_dom, .before_phase(ctl.std_build));

  sos_node = pre_dom.find(pd_start_of_simulation_phase::get(), 0);

  // ---- 2. Tail, after the main final (nodes still belong to pre_dom).
  pre_dom.add(pd_extract_phase::get(), .after_phase(ctl.std_final));
  ext_node = pre_dom.find(pd_extract_phase::get(), 0);
  pre_dom.add(pd_check_phase::get(),   .after_phase(ext_node));
  chk_node = pre_dom.find(pd_check_phase::get(), 0);
  pre_dom.add(pd_report_phase::get(),  .after_phase(chk_node));
  rpt_node = pre_dom.find(pd_report_phase::get(), 0);
  pre_dom.add(pd_final_phase::get(),   .after_phase(rpt_node));

  // ---- 3. Long-lived run branch: pd_sos -> pd_extract. It cannot end
  //         before the main final starts (UVM sibling rule: both are
  //         predecessors of pd_extract).
  pre_dom.add(pd_run_phase::get(), .after_phase(sos_node),
                                    .before_phase(ext_node));
  ctl.pd_run = pre_dom.find(pd_run_phase::get(), 0);

  // ---- 4. Pre runtime phases, in parallel with pd_run. Named
  //         "uvm_sched" so set_domain() -> define_domain() does not append
  //         a second schedule.
  uvm_domain::add_uvm_phases(pre_sched);
  pre_dom.add(pre_sched, .with_phase(ctl.pd_run));

  // ---- Global lookups must still land on the standard nodes.
  b = common.find(uvm_build_phase::get());
  r = common.find(uvm_run_phase::get());
  if (b != ctl.std_build || r != ctl.std_run)
    `uvm_error("PREDOM/LOOKUP",
      {"common.find(build) -> ", (b == null ? "<null>" : b.get_full_name()),
       ", common.find(run) -> ", (r == null ? "<null>" : r.get_full_name()),
       ": expected the standard nodes"})
  else
    `uvm_info("PREDOM/LOOKUP",
      "common.find(build/run) resolve to the standard nodes", UVM_LOW)

  // ---- Controller state.
  ctl.pre_dom      = pre_dom;
  ctl.pd_build     = pre_dom.find(pd_build_phase::get(), 0);
  ctl.pd_connect   = pre_dom.find(pd_connect_phase::get(), 0);
  ctl.pd_eoe       = pre_dom.find(pd_end_of_elaboration_phase::get(), 0);
  ctl.pd_gate      = pre_dom.find(gate, 0);
  ctl.pre_test     = pre_test;
  ctl.main_default = main_test;
  ctl.catcher      = new();
  ctl.noop_f       = new();
  ctl.noop_t       = new();
  pd_build_phase::get().ctl = ctl;

  // ---- +PREDOM_ADOPT=<glob>[,<glob>...]  +PREDOM_ADOPT_RETURN=<glob>[,...]
  //      +PREDOM_EXCLUDE=<glob>[,<glob>...]
  begin
    string arg;
    string pats[$];
    if ($value$plusargs("PREDOM_ADOPT=%s", arg)) begin
      uvm_split_string(arg, ",", pats);
      foreach (pats[i]) ctl.adopt_into_pre_domain(pats[i]);
    end
    pats.delete();
    if ($value$plusargs("PREDOM_ADOPT_RETURN=%s", arg)) begin
      uvm_split_string(arg, ",", pats);
      foreach (pats[i]) ctl.adopt_into_pre_domain(pats[i], 1);
    end
    pats.delete();
    if ($value$plusargs("PREDOM_EXCLUDE=%s", arg)) begin
      uvm_split_string(arg, ",", pats);
      foreach (pats[i]) ctl.exclude_from_pre_domain(pats[i]);
    end
  end

  // ---- Root: its standard run_phase would start at non-zero time.
  top.set_phase_imp(uvm_run_phase::get(), ctl.noop_t, 0);

  // ---- Pre test: created now, assigned to pre_dom (children inherit).
  if (!$cast(ctl.pre_top, factory.create_component_by_name(
                            pre_test, "", ctl.pre_inst_name, null))
      || ctl.pre_top == null)
    `uvm_fatal("PREDOM/INVTST", {"Requested pre test '", pre_test,
                                 "' not found or is not a uvm_component"})
  ctl.pre_top.set_domain(pre_dom);

  // ---- Hooks.
  uvm_report_cb::add(null, ctl.catcher);
  if ($test$plusargs("PREDOM_NO_FOREIGN_CB_FILTER"))
    ctl.foreign_cb_patterns.delete();
  uvm_callbacks#(uvm_phase, uvm_phase_cb)::add(null, ctl, UVM_PREPEND);
  uvm_config_db#(pre_domain_controller)::set(null, "*", "pre_domain_ctl",
                                             ctl);
  pre_domain_controller::m_inst = ctl;
  ctl.m_apply_pending_release();
  return ctl;
endfunction

// ----------------------------------------------------------------------------
// Release the main test from anywhere (module, interface, class) without a
// controller handle. Same as pre_domain_controller::release_main().
// ----------------------------------------------------------------------------
function automatic void pd_release_main(string reason = "");
  pre_domain_controller::release_main(reason);
endfunction


// ============================================================================
// Usage
// ============================================================================
//
// Top module:
//
//   import nv_socv_sim_restore_pkg::*;
//   initial begin
//     pre_domain_controller ctl;
//     ctl = install_pre_domain("my_pre_test", "my_main_test");
//     ctl.gate_timeout_ns = 1_000_000;     // optional safety net (1 ms)
//     run_test();
//   end
//
// Release, from anywhere in the TB (pre test, sequence, module, interface):
//
//   ...boot...
//   pre_domain_controller::release_main("boot done");   // or pd_release_main()
//   forever monitor();                 // keeps running alongside the main test
//
// No controller handle is needed (ctl.release_main() also works). A call
// made before install_pre_domain() is kept and applied at install.
//
// Main test selection (at the main build, after the command line is
// reprocessed): uvm_test_top if run_test() created it at time 0, else
// +UVM_TESTNAME, else install_pre_domain()'s main_test.
//
// Rules:
//   - Always-active run_phase loops must not hold objections. A pre run_phase
//     objection keeps the simulation going past the main test's final.
//   - Do not open the gate by waiting for the pre post_shutdown phase to end:
//     it waits for the main test's final (same sibling rule as pd_run).
//   - Do not wait for release_main() in the pre tree's build/connect/eoe/sos:
//     they run before the gate and would block it.
//
// Checked automatically:
//   - PREDOM/PRE_DOMAIN (error + fatal): a pre-tree component left pre_dom,
//     e.g. a domain-aware VIP calling set_domain(). Checked at the start of
//     pd_connect and of the main build. Fix with adopt_into_pre_domain()
//     (+PREDOM_ADOPT) to keep it working in the pre test, or
//     exclude_from_pre_domain() (+PREDOM_EXCLUDE) to make it inert.
//   - PREDOM/PRE_DEFSEQ (error): a pre-tree sequencer has a "run_phase"
//     default_sequence. Use "pd_run_phase" or a runtime phase instead.
//     Checked at the start of pd_run and of the main run.
// ============================================================================

`endif

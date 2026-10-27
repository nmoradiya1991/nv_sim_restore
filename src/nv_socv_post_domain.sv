// SPDX-FileCopyrightText: Copyright (c) 2024-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
//
`ifndef NV_SOCV_POST_DOMAIN_SV
`define NV_SOCV_POST_DOMAIN_SV

`include "uvm_macros.svh"
`include "nv_socv_report_macros.sv"
import uvm_pkg::*;

// ============================================================================
// nv_socv_post_domain.sv
//
// A post test in its own UVM domain that starts DURING the main test.
//
//   main : build .. sos ── run ────────────────────────────────────── extract .. final
//          reset .. configure .. [main ......] post_main .. post_shutdown
//                                     │ release_post()
//   post :              ps_gate ──────┴─ ps_build .. ps_sos ─┬─ ps_run ───────────┬─ ps_extract .. ps_final
//                                                            └─ pre_reset .. post_shutdown
//                                                               (synced with main)  ┘
//
//   - The main test is a normal UVM test: run_test() / +UVM_TESTNAME, time 0.
//   - ps_gate starts with the main run and holds the post domain until
//     release_post() is called (static, callable from anywhere).
//   - Then the post test (uvm_post_top) is created and built: ps_build ..
//     ps_start_of_simulation, at the release time.
//   - Just before ps_run starts, the 12 post runtime phases are synced
//     (uvm_phase::sync) with the same-named phases of the main "uvm" domain.
//     Post phases the main test has already finished run back to back
//     (catch-up); from the main test's current phase on, both sides start
//     and end each runtime phase together.
//   - After the sync, a runtime phase jump on either side is mirrored on
//     the other side to the same target (see m_on_jump). Off with
//     +PSDOM_NO_JUMP_MIRROR.
//   - The post domain ends before the main extract: ps_extract .. ps_final
//     run first, then the main extract .. final.
//   - If the main runtime phases end without a release, the post domain is
//     skipped (no post test is created) and the run finishes normally.
//
// "ps_" = post domain. UVM's own pre_/post_ runtime phases keep their names.
//
// Install (once; later calls return the same controller), from tb_top before
// run_test() or from any main-tree component up to start_of_simulation, e.g.
// the main env's build_phase:
//
//   void'(install_post_domain("my_post_test"));   // +POST_TEST=<name> wins
//
// Command line: at the start of ps_build (release time, non-zero), the
// command line is reprocessed with
// nv_socv_cmdline_processor::refresh_cmdline_for_late_build() (no-op if it
// was already refreshed in this invocation) and +POST_TEST is read again
// from it before the post test is created.
// ============================================================================

typedef class post_domain_controller;


// --------------------------------------------------------------------------
// 1. Post-domain phase classes. Each one calls the standard phase method.
//    Separate classes keep common.find(uvm_build_phase/...) on the standard
//    nodes.
//    The outermost traverse() always starts at uvm_root: the UVM-ML phase
//    hopper starts function-phase traversals at its own phase service
//    component (it phases the real tops itself, for common/uvm only), so
//    the post tree would never be reached.
//    ps_build skips components whose build_phase already ran (a parent
//    called child.build_phase() itself), as UVM does for "build" only.
// --------------------------------------------------------------------------
`define PSDOM_FUNC_PHASE(CLS, BASE, NAME, METHOD)                             \
class CLS extends BASE;                                                     \
  local static CLS m_inst;                                                  \
  local static bit m_in_traverse;                                           \
  function new(string name = NAME);                                         \
    super.new(name);                                                        \
  endfunction                                                               \
  static function CLS get();                                                \
    if (m_inst == null) m_inst = new();                                     \
    return m_inst;                                                          \
  endfunction                                                               \
  virtual function void traverse(uvm_component comp, uvm_phase phase,       \
                                 uvm_phase_state state);                    \
    if (m_in_traverse) begin                                                \
      super.traverse(comp, phase, state);                                   \
      return;                                                               \
    end                                                                     \
    m_in_traverse = 1;                                                      \
    super.traverse(uvm_root::get(), phase, state);                          \
    m_in_traverse = 0;                                                      \
  endfunction                                                               \
  virtual function void exec_func(uvm_component comp, uvm_phase phase);     \
    if (get_name() == "ps_build" && comp.m_build_done)                      \
      return;                                                               \
    comp.METHOD(phase);                                                     \
  endfunction                                                               \
endclass

`PSDOM_FUNC_PHASE(ps_build_phase,               uvm_topdown_phase,  "ps_build",               build_phase)
`PSDOM_FUNC_PHASE(ps_connect_phase,             uvm_bottomup_phase, "ps_connect",             connect_phase)
`PSDOM_FUNC_PHASE(ps_end_of_elaboration_phase,  uvm_bottomup_phase, "ps_end_of_elaboration",  end_of_elaboration_phase)
`PSDOM_FUNC_PHASE(ps_start_of_simulation_phase, uvm_bottomup_phase, "ps_start_of_simulation", start_of_simulation_phase)
`PSDOM_FUNC_PHASE(ps_extract_phase,             uvm_bottomup_phase, "ps_extract",             extract_phase)
`PSDOM_FUNC_PHASE(ps_check_phase,               uvm_bottomup_phase, "ps_check",               check_phase)
`PSDOM_FUNC_PHASE(ps_report_phase,              uvm_bottomup_phase, "ps_report",              report_phase)
`PSDOM_FUNC_PHASE(ps_final_phase,               uvm_topdown_phase,  "ps_final",               final_phase)

`undef PSDOM_FUNC_PHASE

class ps_run_phase extends uvm_task_phase;
  local static ps_run_phase m_inst;
  function new(string name = "ps_run");
    super.new(name);
  endfunction
  static function ps_run_phase get();
    if (m_inst == null) m_inst = new();
    return m_inst;
  endfunction
  virtual task exec_task(uvm_component comp, uvm_phase phase);
    comp.run_phase(phase);
  endtask
endclass

// Gate: no component runs it (the post tree does not exist yet). The
// controller holds it with an objection until release_post().
class ps_gate_phase extends uvm_task_phase;
  local static ps_gate_phase m_inst;
  function new(string name = "ps_gate");
    super.new(name);
  endfunction
  static function ps_gate_phase get();
    if (m_inst == null) m_inst = new();
    return m_inst;
  endfunction
  virtual task exec_task(uvm_component comp, uvm_phase phase);
  endtask
endclass


// --------------------------------------------------------------------------
// 2. No-op imps: the main extract .. final (common domain) would also run
//    on the post tree; it gets ps_extract .. ps_final instead.
// --------------------------------------------------------------------------
class post_domain_noop_func_phase extends uvm_bottomup_phase;
  function new(string name = "post_domain_noop_func");
    super.new(name);
  endfunction
  virtual function void exec_func(uvm_component comp, uvm_phase phase);
  endfunction
endclass

class post_domain_noop_task_phase extends uvm_task_phase;
  function new(string name = "post_domain_noop_task");
    super.new(name);
  endfunction
  virtual task exec_task(uvm_component comp, uvm_phase phase);
  endtask
endclass


// --------------------------------------------------------------------------
// 3. Catcher. UVM 1.2 reports ILLCRT (fatal) for any component created
//    after the common build phase is done, then constructs it anyway.
//    Suppressed only while ps_build runs and only for the post tree.
// --------------------------------------------------------------------------
class post_domain_catcher extends uvm_report_catcher;
  bit    in_post_build;
  string post_inst_name;
  int    n_caught;

  function new(string name = "post_domain_catcher");
    super.new(name);
  endfunction

  virtual function action_e catch();
    if (in_post_build && get_id() == "ILLCRT" &&
        uvm_is_match({"*'", post_inst_name, "*"}, get_message())) begin
      n_caught++;
      return CAUGHT;
    end
    return THROW;
  endfunction
endclass


// --------------------------------------------------------------------------
// 4. Controller.
// --------------------------------------------------------------------------
class post_domain_controller extends uvm_phase_cb;
  // ---- Post test
  string                       post_test;
  uvm_object_wrapper           post_type;       // set: create by type, not name
  string                       post_inst_name = "uvm_post_top";
  uvm_component                post_top;

  // ---- Domains and nodes
  uvm_domain                   post_dom;
  uvm_domain                   uvm_dom;
  uvm_phase                    ps_gate, ps_build, ps_connect, ps_eoe, ps_sos,
                               ps_run;
  uvm_phase                    main_post_shutdown;
  uvm_phase                    rt_imps[$];      // 12 runtime imps, in order
  uvm_phase                    post_rt[$];      // post_dom runtime nodes
  uvm_phase                    main_rt[$];      // uvm domain runtime nodes

  // ---- Jump mirroring (after the sync). +PSDOM_NO_JUMP_MIRROR clears it.
  bit                          mirror_jumps = 1;
  int unsigned                 n_mirrored;
  local int                    m_rt_idx[uvm_phase];
  local bit                    m_rt_post[uvm_phase];
  local uvm_phase              m_expect[2];     // [is_post]: mirrored target
  local int unsigned           m_jump_gen;

  // ---- Gate
  uvm_event                    post_go   = new("post_domain_go");
  uvm_event                    main_done = new("post_domain_main_done");
  int unsigned                 gate_timeout_ns; // 0 = wait until main ends
  time                         released_at;
  bit                          skipped;
  bit                          synced;

  // ---- Helpers
  post_domain_catcher          catcher;
  post_domain_noop_func_phase  noop_f;
  post_domain_noop_task_phase  noop_t;
  local bit                    m_defseq_reported[uvm_component];

  // ---- Foreign phase callbacks (see m_filter_foreign_cbs()).
  string                       foreign_cb_patterns[$] = '{"uvm_ml_phase_cb*"};
  local uvm_phase_cb           m_foreign_cbs[$];

  function new(string name = "post_domain_controller");
    super.new(name);
  endfunction

  // ------------------------------------------------------------------------
  // UVM-ML 2.x handles function phases of the "common" and "uvm" domains
  // only: for any other domain it looks the phase up by name in "uvm" and
  // dereferences the null result (NOA in export_transmit_phase). Phase
  // callbacks whose name matches foreign_cb_patterns are switched off
  // while a ps_* node of post_dom changes state and back on for every
  // other node (including post_dom's runtime phases, which UVM-ML accepts
  // in any domain). This callback is prepended, so it runs before them.
  // ------------------------------------------------------------------------
  // Registers this phase callback ahead of the others. Once phasing has
  // started, the install usually runs inside a phase callback loop
  // (e.g. UVM-ML's, which traverses build); prepending there shifts the
  // loop and re-runs the current callback. So: append now, move to the
  // front from a separate process once the loop is over.
  function void m_add_phase_cb();
    uvm_phase bld = uvm_domain::get_common_domain().find(
                      uvm_build_phase::get());
    if (bld == null || bld.get_state() == UVM_PHASE_DORMANT) begin
      uvm_callbacks#(uvm_phase, uvm_phase_cb)::add(null, this, UVM_PREPEND);
      return;
    end
    uvm_callbacks#(uvm_phase, uvm_phase_cb)::add(null, this);
    fork
      begin
        #0;
        uvm_callbacks#(uvm_phase, uvm_phase_cb)::delete(null, this);
        uvm_callbacks#(uvm_phase, uvm_phase_cb)::add(null, this, UVM_PREPEND);
      end
    join_none
  endfunction

  function void m_filter_foreign_cbs(uvm_phase phase);
    bit       hide;
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
      `uvm_info("PSDOM/FOREIGN_CB", $sformatf(
        "%0d phase callback(s) hidden from the ps_* phases (e.g. '%s')",
        m_foreign_cbs.size(), m_foreign_cbs[0].get_name()), UVM_LOW)
    end

    imp  = phase.get_imp();
    hide = (post_dom != null && phase.get_domain() == post_dom) &&
           imp != null && uvm_is_match("ps_*", imp.get_name());
    foreach (m_foreign_cbs[i])
      void'(m_foreign_cbs[i].callback_mode(!hide));
  endfunction

  // ------------------------------------------------------------------------
  // Release. Static: callable from anywhere without a handle
  // (post_domain_controller::release_post() or pd_release_post());
  // ctl.release_post() also works. First call wins. A call before
  // install_post_domain() is kept and applied at install.
  // ------------------------------------------------------------------------
  static post_domain_controller m_inst;
  local static bit              m_pending;
  local static string           m_pending_reason;
  local static time             m_pending_at;

  static function post_domain_controller get_inst();
    return m_inst;
  endfunction

  static function void release_post(string reason = "");
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

  // ------------------------------------------------------------------------
  // Wait for the post domain to start: blocks until the gate is open and
  // the post test is created (start of ps_build, uvm_post_top exists);
  // returns at once if that already happened. Also returns if the post
  // domain is skipped (no release before the main runtime phases ended);
  // is_post_started() tells the two apart. Static: callable from any
  // module, interface or class, also before install_post_domain().
  // ------------------------------------------------------------------------
  local static uvm_event        m_start_ev;
  local static bit              m_started;

  static function uvm_event m_get_start_ev();
    if (m_start_ev == null)
      m_start_ev = new("post_domain_started");
    return m_start_ev;
  endfunction

  static task wait_post_started();
    uvm_event ev = m_get_start_ev();
    ev.wait_on();
  endtask

  static function bit is_post_started();
    return m_started;
  endfunction

  function void m_apply_pending_release();
    if (!m_pending)
      return;
    m_pending = 0;
    m_release({m_pending_reason, " (called before install_post_domain())"},
              m_pending_at);
  endfunction

  virtual function void m_release(string reason, time at);
    if (post_go.is_on())
      return;
    if (main_done.is_on()) begin
      `uvm_warning("PSDOM/GATE",
        "release_post() after the main runtime phases ended: ignored, the post domain was skipped")
      return;
    end
    released_at = at;
    `uvm_info("PSDOM/GATE",
      {"Post domain released", (reason == "" ? "" : {": ", reason})}, UVM_LOW)
    post_go.trigger();
  endfunction

  // Main runtime done = main post_shutdown executing with all its
  // objections dropped. It cannot wait for post_shutdown to END: that end
  // waits for ps_final (both precede the main extract), which waits for
  // this gate.
  virtual task m_wait_main_runtime_done();
    uvm_objection obj;
    main_post_shutdown.wait_for_state(UVM_PHASE_EXECUTING, UVM_GTE);
    obj = main_post_shutdown.get_objection();
    forever begin
      if (obj != null && obj.get_objection_total() != 0)
        obj.wait_for(UVM_ALL_DROPPED, uvm_root::get());
      uvm_wait_for_nba_region();
      if (obj == null || obj.get_objection_total() == 0)
        break;
    end
    main_done.trigger();
  endtask

  // Holds ps_gate until the release, the end of the main runtime phases
  // (skip), or gate_timeout (fatal).
  virtual task m_gate_watch(uvm_phase phase);
    fork
      begin
        fork
          post_go.wait_on();
          m_wait_main_runtime_done();
          if (gate_timeout_ns > 0) begin
            #(gate_timeout_ns * 1ns);
            `uvm_fatal("PSDOM/GATE", $sformatf(
              "release_post() not called within %0d ns", gate_timeout_ns))
          end
          else
            wait (0);
        join_any
        disable fork;
      end
    join
    if (!post_go.is_on()) begin
      skipped = 1;
      `uvm_info("PSDOM/SKIP",
        "Main runtime phases ended without release_post(): post domain skipped",
        UVM_LOW)
      m_get_start_ev().trigger();
    end
    phase.drop_objection(null, "post gate");
  endtask

  // ------------------------------------------------------------------------
  // Phase callback.
  // ------------------------------------------------------------------------
  virtual function void phase_state_change(uvm_phase phase,
                                           uvm_phase_state_change change);
    uvm_phase_state s = change.get_state();

    m_filter_foreign_cbs(phase);

    if (s == UVM_PHASE_ENDED && m_rt_idx.exists(phase) &&
        change.jump_to() != null)
      m_on_jump(phase, change.jump_to());

    if (phase == ps_gate && s == UVM_PHASE_STARTED) begin
      phase.raise_objection(null, "waiting for release_post()");
      fork
        m_gate_watch(phase);
      join_none
    end
    else if (phase == ps_build) begin
      if (s == UVM_PHASE_STARTED) begin
        catcher.in_post_build = 1;
        if (!skipped) begin
          nv_socv_cmdline_processor::refresh_cmdline_for_late_build("the post-domain build");
          resolve_post_test();
          m_open_connect_window();
          create_post_test();
          m_started = 1;
          m_get_start_ev().trigger();
        end
      end
      else if (s == UVM_PHASE_ENDED) begin
        catcher.in_post_build = 0;
        if (catcher.n_caught > 0)
          `uvm_info("PSDOM/ILLCRT", $sformatf(
            "%0d post-tree component(s) created after the main build; ILLCRT suppressed for them",
            catcher.n_caught), UVM_LOW)
      end
    end
    else if (post_top != null && phase == ps_connect &&
             s == UVM_PHASE_STARTED) begin
      check_post_domains("start of ps_connect");
      silence_std_for_post_tree();
      nv_socv_cmdline_processor::reapply_report_settings_for_late_build("the post tree");
    end
    else if (phase == ps_connect && s == UVM_PHASE_ENDED) begin
      m_close_connect_window();
    end
    else if (post_top != null && phase == ps_eoe && s == UVM_PHASE_STARTED) begin
      post_top.do_resolve_bindings();
    end
    else if (post_top != null && phase == ps_sos && s == UVM_PHASE_STARTED) begin
      sync_runtime();
    end
    else if (post_top != null && phase == ps_run && s == UVM_PHASE_STARTED) begin
      check_post_domains("start of ps_run");
      check_post_default_sequences("start of ps_run");
    end
  endfunction

  // ------------------------------------------------------------------------
  // Connect window (ps_build STARTED .. ps_connect ENDED).
  // uvm_port_base::connect() ignores any connect made once the global
  // end_of_elaboration_ph is EXECUTING/DONE ("Late Connection"), which is
  // always the case for the post tree. For this window the global points at
  // a never-executed guard node so post-tree connects are accepted; the
  // bindings are then resolved at ps_end_of_elaboration.
  // ------------------------------------------------------------------------
  local uvm_phase m_saved_eoe_ph;
  local uvm_phase m_eoe_guard;

  function void m_open_connect_window();
    if (m_saved_eoe_ph != null || $test$plusargs("PSDOM_NO_CONNECT_WINDOW"))
      return;
    if (m_eoe_guard == null)
      m_eoe_guard = new("ps_connect_window", UVM_PHASE_NODE);
    m_saved_eoe_ph = uvm_pkg::end_of_elaboration_ph;
    uvm_pkg::end_of_elaboration_ph = m_eoe_guard;
    `uvm_info("PSDOM/CONNECT", "connect window opened for the post tree", UVM_MEDIUM)
  endfunction

  function void m_close_connect_window();
    if (m_saved_eoe_ph == null) return;
    uvm_pkg::end_of_elaboration_ph = m_saved_eoe_ph;
    m_saved_eoe_ph = null;
    `uvm_info("PSDOM/CONNECT", "connect window closed", UVM_MEDIUM)
  endfunction

  // ------------------------------------------------------------------------
  // Post test creation (start of ps_build).
  // ------------------------------------------------------------------------
  // +POST_TEST from the (reprocessed) UVM command line overrides the name
  // chosen at install.
  virtual function void resolve_post_test();
    uvm_cmdline_processor clp = uvm_cmdline_processor::get_inst();
    string                v;
    if (clp.get_arg_value("+POST_TEST=", v) && v != "" &&
        (post_type != null || v != post_test)) begin
      `uvm_info("PSDOM", {"+POST_TEST=", v, " replaces post test ",
                          post_test_desc()}, UVM_LOW)
      post_test = v;
      post_type = null;
    end
  endfunction

  // Post test for messages: the type name, or the type handle's name.
  function string post_test_desc();
    string n;
    if (post_type == null)
      return post_test;
    n = post_type.get_type_name();
    if (n == "" || n == "<unknown>")
      return "<type handle, no factory name>";
    return {"<type handle> ", n};
  endfunction

  virtual function void create_post_test();
    uvm_coreservice_t cs      = uvm_coreservice_t::get();
    uvm_factory       factory = cs.get_factory();
    uvm_component     c;

    if (post_type != null)
      c = factory.create_component_by_type(post_type, "", post_inst_name, null);
    else
      c = factory.create_component_by_name(post_test, "", post_inst_name, null);
    post_top = c;
    if (post_top == null)
      `uvm_fatal("PSDOM/INVTST", {"Requested post test '", post_test_desc(),
                                  "' not found or is not a uvm_component"})
    post_top.set_domain(post_dom);
    `uvm_info("PSDOM", {"Running post test ", post_test_desc()}, UVM_LOW)
  endfunction

  // The main extract .. final are common-domain nodes and would run on the
  // post tree too; build .. run are already over, silenced for safety.
  virtual function void silence_std_for_post_tree();
    post_top.set_phase_imp(uvm_build_phase::get(),               noop_f, 1);
    post_top.set_phase_imp(uvm_connect_phase::get(),             noop_f, 1);
    post_top.set_phase_imp(uvm_end_of_elaboration_phase::get(),  noop_f, 1);
    post_top.set_phase_imp(uvm_start_of_simulation_phase::get(), noop_f, 1);
    post_top.set_phase_imp(uvm_run_phase::get(),                 noop_t, 1);
    post_top.set_phase_imp(uvm_extract_phase::get(),             noop_f, 1);
    post_top.set_phase_imp(uvm_check_phase::get(),               noop_f, 1);
    post_top.set_phase_imp(uvm_report_phase::get(),              noop_f, 1);
    post_top.set_phase_imp(uvm_final_phase::get(),               noop_f, 1);
  endfunction

  // ------------------------------------------------------------------------
  // Runtime sync (start of ps_start_of_simulation, i.e. just before ps_run
  // and the post runtime phases start).
  // ------------------------------------------------------------------------
  virtual function void sync_runtime();
    foreach (rt_imps[i]) begin
      uvm_phase p = post_dom.find(rt_imps[i]);
      uvm_phase m = uvm_dom.find(rt_imps[i]);
      if (p != post_rt[i] || m == null || m.get_domain() != uvm_dom)
        `uvm_fatal("PSDOM/SYNC", $sformatf(
          "Runtime phase '%s': lookup in '%s' / 'uvm' did not return the expected node; cannot sync",
          rt_imps[i].get_name(), post_dom.get_name()))
      post_dom.sync(uvm_dom, rt_imps[i]);
    end
    synced = 1;
    `uvm_info("PSDOM/SYNC", $sformatf({
      "Post runtime phases synced with the uvm domain (main is in '%s'). ",
      "Phases the main test has finished run back to back; from there on ",
      "both sides start and end each runtime phase together."},
      main_current_phase()), UVM_LOW)
  endfunction

  // ------------------------------------------------------------------------
  // Jump mirroring. A jump only moves the domain whose node jumped; sync
  // does not pass it on. After the sync, a runtime jump on one side is
  // repeated on the other side to the same target phase:
  //   backward: if the other side is past the target, it jumps back too;
  //             if it is at or before the target (still catching up), it
  //             is left alone and meets the jumping side at the target.
  //   forward : if the other side is before the target, it jumps forward
  //             too (skips the same phases).
  // The other side's phase must have started (jump() is only legal from
  // STARTED to ENDED), so this waits a few deltas for it; a side that is
  // parked at the start of a phase (SYNCING) longer than that is not
  // jumped (PSDOM/JUMP warning) and joins the jumping side when it
  // reaches that phase again.
  // ------------------------------------------------------------------------
  function void m_index_rt();
    foreach (post_rt[i]) begin
      m_rt_idx[post_rt[i]]  = i;
      m_rt_post[post_rt[i]] = 1;
    end
    foreach (main_rt[i]) begin
      m_rt_idx[main_rt[i]]  = i;
      m_rt_post[main_rt[i]] = 0;
    end
  endfunction

  virtual function void m_on_jump(uvm_phase src, uvm_phase tgt);
    bit       src_post = m_rt_post[src];
    uvm_phase imp      = tgt.get_imp();
    int       t_idx    = -1;

    if (m_expect[src_post] != null && m_expect[src_post] == imp) begin
      m_expect[src_post] = null;      // the jump this controller mirrored
      return;
    end
    if (!mirror_jumps || !synced)
      return;

    foreach (rt_imps[i])
      if (rt_imps[i] == imp)
        t_idx = i;
    if (t_idx < 0) begin
      `uvm_warning("PSDOM/JUMP", $sformatf(
        "%s jumped %s -> %s: not a runtime phase, not mirrored on the %s side",
        (src_post ? "post" : "main"), src.get_name(), imp.get_name(),
        (src_post ? "main" : "post")))
      return;
    end

    m_jump_gen++;
    fork
      m_mirror_jump(!src_post, m_rt_idx[src], t_idx, m_jump_gen,
                    src.get_name());
    join_none
  endfunction

  virtual task m_mirror_jump(bit dst_post, int s_idx, int t_idx,
                             int unsigned gen, string from);
    string    src = dst_post ? "main" : "post";
    string    dst = dst_post ? "post" : "main";
    bit       fwd = (t_idx > s_idx);
    uvm_phase q[$];

    q = dst_post ? post_rt : main_rt;
    repeat (50) begin
      uvm_phase p     = null;
      int       p_idx = -1;

      if (gen != m_jump_gen)
        return;                       // superseded by a newer jump
      foreach (q[i])
        if (p == null && q[i].get_state() inside
              {[UVM_PHASE_SCHEDULED:UVM_PHASE_CLEANUP]}) begin
          p     = q[i];
          p_idx = i;
        end

      if (p != null) begin
        if (fwd ? (p_idx >= t_idx) : (p_idx <= t_idx)) begin
          `uvm_info("PSDOM/JUMP", $sformatf(
            "%s jumped %s -> %s; %s is in %s, no jump needed (meets %s at %s)",
            src, from, rt_imps[t_idx].get_name(), dst, p.get_name(), src,
            rt_imps[t_idx].get_name()), UVM_LOW)
          return;
        end
        if (p.get_state() inside
              {[UVM_PHASE_STARTED:UVM_PHASE_READY_TO_END]}) begin
          m_expect[dst_post] = rt_imps[t_idx];
          n_mirrored++;
          `uvm_info("PSDOM/JUMP", $sformatf(
            "%s jumped %s -> %s @%0t; mirrored: %s jumps %s -> %s",
            src, from, rt_imps[t_idx].get_name(), $time, dst, p.get_name(),
            rt_imps[t_idx].get_name()), UVM_LOW)
          p.jump(rt_imps[t_idx]);
          return;
        end
      end
      #0;
    end
    `uvm_warning("PSDOM/JUMP", $sformatf({
      "%s jumped %s -> %s; %s was not in a running runtime phase, not ",
      "mirrored (it joins %s when it reaches the same phase)"},
      src, from, rt_imps[t_idx].get_name(), dst, src))
  endtask

  function string main_current_phase();
    foreach (rt_imps[i]) begin
      uvm_phase       m  = uvm_dom.find(rt_imps[i]);
      uvm_phase_state st = m.get_state();
      if (st inside {UVM_PHASE_SYNCING, UVM_PHASE_STARTED,
                     UVM_PHASE_EXECUTING, UVM_PHASE_READY_TO_END,
                     UVM_PHASE_ENDED, UVM_PHASE_CLEANUP})
        return m.get_name();
    end
    return "<none: runtime not active>";
  endfunction

  // ------------------------------------------------------------------------
  // Checks.
  // ------------------------------------------------------------------------
  virtual function void check_post_domains(string when);
    uvm_component all[$];
    int           n_bad;

    m_collect(post_top, all);
    foreach (all[i]) begin
      uvm_domain d = all[i].get_domain();
      if (d != post_dom) begin
        n_bad++;
        `uvm_error("PSDOM/POST_DOMAIN", $sformatf({
          "%s is in domain '%s', not '%s' (found at %s). Components under ",
          "%s must stay in '%s', otherwise they do not get the ps_* phases ",
          "and their runtime phases are not synced with the main test. ",
          "Usually a domain-aware VIP calling set_domain(); move it back ",
          "right after it is created, or disable that feature."},
          all[i].get_full_name(), (d == null ? "<null>" : d.get_name()),
          post_dom.get_name(), when, post_inst_name, post_dom.get_name()))
      end
    end
    if (n_bad > 0)
      `uvm_fatal("PSDOM/POST_DOMAIN", $sformatf(
        "%0d post-tree component(s) left the '%s' domain; see the PSDOM/POST_DOMAIN errors above",
        n_bad, post_dom.get_name()))
  endfunction

  // A "run_phase" default sequence never starts in the post tree (the main
  // run started before the post tree existed; the post run is "ps_run").
  virtual function void check_post_default_sequences(string when);
    uvm_component all[$];

    m_collect(post_top, all);
    foreach (all[i]) begin
      uvm_sequencer_base seqr;
      uvm_object_wrapper wrapper;
      uvm_sequence_base  seq;
      bit                found = 0;

      if (!$cast(seqr, all[i]) || m_defseq_reported.exists(all[i]))
        continue;
      if (uvm_config_db#(uvm_object_wrapper)::get(seqr, "run_phase",
            "default_sequence", wrapper) && wrapper != null)
        found = 1;
      if (uvm_config_db#(uvm_sequence_base)::get(seqr, "run_phase",
            "default_sequence", seq) && seq != null)
        found = 1;

      if (found) begin
        m_defseq_reported[all[i]] = 1;
        `uvm_error("PSDOM/POST_DEFSEQ", $sformatf({
          "%s has a 'run_phase' default_sequence (found at %s). It never ",
          "starts in the post tree. Use \"ps_run_phase\" or a runtime ",
          "phase (\"main_phase\", ...) instead."},
          all[i].get_full_name(), when))
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
endclass


// --------------------------------------------------------------------------
// 5. Installer. Once per simulation; later calls return the controller.
//
//   install_post_domain(post_test, domain_name)
//     post_test   : post test type name; +POST_TEST=<name> overrides it.
//                   Empty and no plusarg: nothing is installed, returns null.
//   install_post_domain_by_type(post_type, domain_name)
//     post_type   : factory type handle, e.g. my_env#(P1, P2)::get_type().
//                   For classes without a factory name (parameterized
//                   classes with `uvm_component_param_utils). Factory type
//                   overrides apply. +POST_TEST=<name> still overrides it.
//   domain_name : name of the post domain
//
// Call from tb_top before run_test(), or from any main-tree component up
// to (and including) start_of_simulation, e.g. the main env's build_phase.
// Plusargs: +POST_GATE_TIMEOUT=<ns> (default 0: wait until the main
// runtime phases end, then skip); +PSDOM_NO_JUMP_MIRROR.
// --------------------------------------------------------------------------
function automatic post_domain_controller install_post_domain(
    string post_test   = "",
    string domain_name = "post_dom");
  return m_install_post_domain(post_test, null, domain_name);
endfunction

function automatic post_domain_controller install_post_domain_by_type(
    uvm_object_wrapper post_type,
    string             domain_name = "post_dom");
  if (post_type == null) begin
    `uvm_error("PSDOM", "install_post_domain_by_type(): null type handle; post domain not installed")
    return null;
  end
  return m_install_post_domain("", post_type, domain_name);
endfunction

function automatic post_domain_controller m_install_post_domain(
    string             post_test,
    uvm_object_wrapper post_type,
    string             domain_name);

  uvm_coreservice_t      cs     = uvm_coreservice_t::get();
  uvm_root               top    = cs.get_root();
  uvm_domain             common = uvm_domain::get_common_domain();
  post_domain_controller ctl;
  uvm_domain             post_dom;
  uvm_phase              post_sched;
  uvm_phase              std_sos, std_ext, sos_node, ext_node;
  string                 pt = post_test;
  int unsigned           gate_ns;

  if (post_domain_controller::m_inst != null) begin
    post_domain_controller c = post_domain_controller::m_inst;
    if ((post_type != null && post_type != c.post_type) ||
        (post_type == null && post_test != "" && post_test != c.post_test))
      `uvm_warning("PSDOM/REINSTALL", {
        "Post domain already installed with post test ", c.post_test_desc(),
        "; this request is ignored. The post domain has a single top ",
        "(uvm_post_top): to run several components in it, install one ",
        "wrapper component that creates them in its build_phase."})
    return c;
  end

  if ($value$plusargs("POST_TEST=%s", pt) && pt != "")
    post_type = null;
  if (pt == "" && post_type == null) begin
    `uvm_info("PSDOM", "No post test (argument or +POST_TEST): post domain not installed", UVM_LOW)
    return null;
  end

  std_sos = common.find(uvm_start_of_simulation_phase::get());
  std_ext = common.find(uvm_extract_phase::get());
  if (std_sos == null || std_ext == null)
    `uvm_fatal("PSDOM", "Standard phase nodes not found in the common domain")
  if (std_sos.get_state() >= UVM_PHASE_ENDED)
    `uvm_fatal("PSDOM/LATE", {
      "install_post_domain() called after the main start_of_simulation ",
      "ended: the post domain could never start. Call it from tb_top ",
      "before run_test() or from a main-tree component's build_phase .. ",
      "start_of_simulation_phase."})

  ctl          = new();
  ctl.post_test = pt;
  ctl.post_type = post_type;
  ctl.catcher  = new();
  ctl.catcher.post_inst_name = ctl.post_inst_name;
  ctl.noop_f   = new();
  ctl.noop_t   = new();
  ctl.uvm_dom  = uvm_domain::get_uvm_domain();
  ctl.main_post_shutdown = ctl.uvm_dom.find(uvm_post_shutdown_phase::get());
  if (ctl.main_post_shutdown == null)
    `uvm_fatal("PSDOM", "post_shutdown node not found in the uvm domain")
  if ($value$plusargs("POST_GATE_TIMEOUT=%d", gate_ns))
    ctl.gate_timeout_ns = gate_ns;

  ctl.rt_imps.push_back(uvm_pre_reset_phase::get());
  ctl.rt_imps.push_back(uvm_reset_phase::get());
  ctl.rt_imps.push_back(uvm_post_reset_phase::get());
  ctl.rt_imps.push_back(uvm_pre_configure_phase::get());
  ctl.rt_imps.push_back(uvm_configure_phase::get());
  ctl.rt_imps.push_back(uvm_post_configure_phase::get());
  ctl.rt_imps.push_back(uvm_pre_main_phase::get());
  ctl.rt_imps.push_back(uvm_main_phase::get());
  ctl.rt_imps.push_back(uvm_post_main_phase::get());
  ctl.rt_imps.push_back(uvm_pre_shutdown_phase::get());
  ctl.rt_imps.push_back(uvm_shutdown_phase::get());
  ctl.rt_imps.push_back(uvm_post_shutdown_phase::get());

  // ---- Post domain graph, built before it is attached to common.
  //      ps_gate -> ps_build -> ps_connect -> ps_eoe -> ps_sos
  //        -> (ps_run || runtime schedule) -> ps_extract .. ps_final
  post_dom   = new(domain_name);
  post_sched = new("uvm_sched", UVM_PHASE_SCHEDULE);   // set_domain() reuses it

  post_dom.add(ps_gate_phase::get());
  post_dom.add(ps_build_phase::get());
  post_dom.add(ps_connect_phase::get());
  post_dom.add(ps_end_of_elaboration_phase::get());
  post_dom.add(ps_start_of_simulation_phase::get());
  post_dom.add(ps_extract_phase::get());
  post_dom.add(ps_check_phase::get());
  post_dom.add(ps_report_phase::get());
  post_dom.add(ps_final_phase::get());

  sos_node = post_dom.find(ps_start_of_simulation_phase::get(), 0);
  ext_node = post_dom.find(ps_extract_phase::get(), 0);
  post_dom.add(ps_run_phase::get(), .after_phase(sos_node),
               .before_phase(ext_node));

  ctl.ps_gate    = post_dom.find(ps_gate_phase::get(), 0);
  ctl.ps_build   = post_dom.find(ps_build_phase::get(), 0);
  ctl.ps_connect = post_dom.find(ps_connect_phase::get(), 0);
  ctl.ps_eoe     = post_dom.find(ps_end_of_elaboration_phase::get(), 0);
  ctl.ps_sos     = sos_node;
  ctl.ps_run     = post_dom.find(ps_run_phase::get(), 0);

  uvm_domain::add_uvm_phases(post_sched);
  post_dom.add(post_sched, .with_phase(ctl.ps_run));
  foreach (ctl.rt_imps[i]) begin
    uvm_phase n = post_dom.find(ctl.rt_imps[i], 0);
    if (n == null || n.get_domain() != post_dom)
      `uvm_fatal("PSDOM", {"Post runtime node '", ctl.rt_imps[i].get_name(),
                           "' not found in the post domain"})
    ctl.post_rt.push_back(n);
    n = ctl.uvm_dom.find(ctl.rt_imps[i]);
    if (n == null)
      `uvm_fatal("PSDOM", {"Runtime node '", ctl.rt_imps[i].get_name(),
                           "' not found in the uvm domain"})
    ctl.main_rt.push_back(n);
  end
  ctl.m_index_rt();
  if ($test$plusargs("PSDOM_NO_JUMP_MIRROR"))
    ctl.mirror_jumps = 0;

  // ---- Attach: parallel branch from the main sos to the main extract.
  common.add(post_dom, .after_phase(std_sos), .before_phase(std_ext));
  ctl.post_dom = post_dom;

  // ---- Hooks.
  uvm_report_cb::add(null, ctl.catcher);
  if ($test$plusargs("PSDOM_NO_FOREIGN_CB_FILTER"))
    ctl.foreign_cb_patterns.delete();
  ctl.m_add_phase_cb();
  uvm_config_db#(post_domain_controller)::set(null, "*", "post_domain_ctl",
                                              ctl);
  post_domain_controller::m_inst = ctl;
  `uvm_info("PSDOM", $sformatf(
    "Post domain '%s' installed (post test %s); waits for release_post()",
    domain_name, ctl.post_test_desc()), UVM_LOW)
  ctl.m_apply_pending_release();
  return ctl;
endfunction

// Release the post domain from anywhere (module, interface, class).
function automatic void pd_release_post(string reason = "");
  post_domain_controller::release_post(reason);
endfunction

// Block until the post domain has started (see
// post_domain_controller::wait_post_started). Returns 1 if it started,
// 0 if it was skipped.
task automatic pd_wait_post_started(output bit started);
  post_domain_controller::wait_post_started();
  started = post_domain_controller::is_post_started();
endtask

// Runtime phase imp by name ("reset", "main", "post_shutdown", ...).
function automatic uvm_phase ps_runtime_imp(string name);
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
    if (imps[i].get_name() == name)
      return imps[i];
  `uvm_fatal("PSDOM", {"'", name, "' is not a runtime phase name"})
  return null;
endfunction


// ============================================================================
// Usage
// ============================================================================
//
// Install (pick one place):
//   tb_top before run_test():     void'(install_post_domain("my_post_test"));
//   main env build_phase:         void'(install_post_domain("my_post_test"));
//   parameterized class (no factory name):
//     void'(install_post_domain_by_type(my_env#(P1, P2)::get_type()));
//
// Release, from anywhere (typically the main test's main_phase):
//   post_domain_controller::release_post("traffic ready");   // or pd_release_post()
//
// Wait for the post domain to start, from anywhere:
//   post_domain_controller::wait_post_started();      // class / task
//   pd_wait_post_started(started);                    // started=0: skipped
//
// Rules:
//   - Post run_phase loops: no objections needed (ps_run ends with the post
//     runtime phases, like the main run does).
//   - Post default sequences: "ps_run_phase" or runtime phases
//     ("main_phase", ...). "run_phase" never starts (PSDOM/POST_DEFSEQ).
//   - A post objection in a synced runtime phase also holds the main test's
//     phase of the same name, and the other way round.
//   - Connections from main-tree ports to post-tree imps made after the
//     main end_of_elaboration may not take effect (bindings already
//     resolved); pass handles or use callbacks / events instead.
//   - Runtime phase jumps after the sync are mirrored both ways (PSDOM/JUMP
//     messages). Jumps to a non-runtime phase (e.g. extract) are not.
//     +PSDOM_NO_JUMP_MIRROR turns mirroring off.
// ============================================================================

`endif

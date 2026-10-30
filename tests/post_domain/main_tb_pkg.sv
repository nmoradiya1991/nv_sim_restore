// ============================================================================
// main_tb_pkg.sv -- domain-based proposal, post domain: the main test, built at time 0.
// STATIC in the DTL flow (part of the saved image); the post test is in
// post_tb_pkg.
//
//   soc_main_test (uvm_test_top, built at time 0)
//     env.cpu_agt : reset 10 ns, main <MAIN_MAIN> (100) ns
//     env.hb      : run_phase heartbeat
//     env         : installs the post domain (pcie_post_test) in build_phase
//     release     : <RELEASE_DELAY> (30) ns into <RELEASE_PHASE> (main):
//                   feature checkpoint B (+SAVE_BEFORE_RELEASE), then release_post()
//
// Command-line reprocessing targets, main tree (already built at time 0),
// after the post domain started: env re-reads post_window (config_int) and
// creates a soc_txn (type override soc_txn -> soc_txn_ext); cl_expect keys
// POST_WINDOW, TXN_TYPE.
//
// Plusargs read here:
//   +MAIN_MAIN=<ns>        cpu_agt main_phase length (100)
//   +RELEASE_PHASE=<name>  main runtime phase that triggers the release (main)
//   +RELEASE_DELAY=<ns>    delay after that phase starts (30)
//   +NO_RELEASE            never release: post domain skipped
//   +SAVE_BEFORE_RELEASE   feature checkpoint B before release_post()
//   +MAIN_JUMP_TO / +MAIN_JUMP_AT=<ns> (50)   main test jump out of main_phase
// ============================================================================

`timescale 1ns/1ps

package main_tb_pkg;

  import uvm_pkg::*;
  import nv_socv_sim_restore_pkg::*;
  import tests_common_pkg::*;
  `include "uvm_macros.svh"

  // --------------------------------------------------------------------------
  // Main test.
  // --------------------------------------------------------------------------
  class soc_txn extends uvm_object;
    `uvm_object_utils(soc_txn)
    function new(string name = "soc_txn");
      super.new(name);
    endfunction
  endclass

  class soc_txn_ext extends soc_txn;
    `uvm_object_utils(soc_txn_ext)
    function new(string name = "soc_txn_ext");
      super.new(name);
    endfunction
  endclass

  class soc_main_env extends uvm_env;
    `uvm_component_utils(soc_main_env)

    phase_logger cpu_agt;
    heartbeat    hb;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      int unsigned main_ns = 100;
      cpu_agt = phase_logger::type_id::create("cpu_agt", this);
      hb      = heartbeat::type_id::create("hb", this);
      void'($value$plusargs("MAIN_MAIN=%d", main_ns));
      cpu_agt.main_delay = main_ns;
      void'(install_post_domain("pcie_post_test"));
    endfunction

    virtual task run_phase(uvm_phase phase);
      uvm_bitstream_t post_window = 0;
      soc_txn         txn;
      post_domain_controller::wait_post_started();
      `uvm_info("ENV", $sformatf("post domain %s @%0t",
                (post_domain_controller::is_post_started() ? "started" : "skipped"),
                $time), UVM_LOW)
      if (!post_domain_controller::is_post_started())
        return;
      void'(uvm_config_int::get(this, "", "post_window", post_window));
      txn = soc_txn::type_id::create("txn");
      cl_expect::check_int("POST_WINDOW", post_window, "main tree, config re-read after the release");
      cl_expect::check("TXN_TYPE", txn.get_type_name(), "main tree, object created after the release");
    endtask
  endclass

  class soc_main_test extends uvm_test;
    `uvm_component_utils(soc_main_test)

    soc_main_env env;
    jump_once    jmp;
    string       release_phase = "main";
    int unsigned release_delay = 30;
    bit          no_release;
    bit          save_before_release;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      string       jump_to;
      int unsigned jump_at = 50;
      void'($value$plusargs("MAIN_JUMP_TO=%s", jump_to));
      void'($value$plusargs("MAIN_JUMP_AT=%d", jump_at));
      jmp = new("main", jump_to, jump_at);

      env = soc_main_env::type_id::create("env", this);
      void'($value$plusargs("RELEASE_PHASE=%s", release_phase));
      void'($value$plusargs("RELEASE_DELAY=%d", release_delay));
      no_release          = $test$plusargs("NO_RELEASE");
      save_before_release = $test$plusargs("SAVE_BEFORE_RELEASE");
    endfunction

    virtual task main_phase(uvm_phase phase);
      jmp.run(this, phase);
    endtask

    virtual function void phase_started(uvm_phase phase);
      if (no_release || phase.get_name() != release_phase ||
          phase.get_domain() != uvm_domain::get_uvm_domain())
        return;
      fork
        begin
          #(release_delay);
          if (save_before_release)
            save_point::take("B (feature: post domain not built)");
          post_domain_controller::release_post($sformatf("main %s_phase + %0d ns%s",
            release_phase, release_delay,
            (save_point::restored() ? ", restored run" : "")));
        end
      join_none
    endfunction

    virtual function void report_phase(uvm_phase phase);
      post_domain_controller ctl = post_domain_controller::get_inst();
      if (ctl == null)
        return;
      `uvm_info("MAIN", $sformatf(
        "post domain: released at %0t, skipped=%0d, synced=%0d, jumps mirrored=%0d",
        ctl.released_at, ctl.skipped, ctl.synced, ctl.n_mirrored), UVM_LOW)
      cl_expect::summary();
    endfunction
  endclass

endpackage

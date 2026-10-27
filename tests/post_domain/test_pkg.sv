// ============================================================================
// test_pkg.sv -- Approach B, post domain: a post test in its own domain,
// built at release_post() during the main test, runtime phases synced.
//
//   soc_main_test (uvm_test_top, built at time 0)
//     env.cpu_agt : reset 10 ns, main <MAIN_MAIN> (100) ns
//     env.hb      : run_phase heartbeat
//     env         : installs the post domain (pcie_post_test) in build_phase
//     release     : <RELEASE_DELAY> (30) ns into <RELEASE_PHASE> (main):
//                   save point B (+SAVE_BEFORE_RELEASE), then release_post()
//
//   pcie_post_test (uvm_post_top, post_dom, built at the release)
//     env.pcie_agt : reset 10 ns, main <POST_MAIN> (20) ns
//     env.pcie_bus : sequencer + driver, connected in ps_connect
//     env.pcie_sb  : counts the bus responses, checks them
//     env.hb       : ps_run heartbeat
//   pcie_post_test_b: pcie_post_test + env.pcie_cov (covergroup on the items)
//
// Plusargs read here:
//   +MAIN_MAIN=<ns>        cpu_agt main_phase length (100)
//   +RELEASE_PHASE=<name>  main runtime phase that triggers the release (main)
//   +RELEASE_DELAY=<ns>    delay after that phase starts (30)
//   +NO_RELEASE            never release: post domain skipped
//   +SAVE_BEFORE_RELEASE   save point B before release_post()
//   +POST_MAIN=<ns>        pcie_agt main_phase length (20)
//   +MAIN_JUMP_TO / +MAIN_JUMP_AT=<ns> (50)   main test jump out of main_phase
//   +POST_JUMP_TO / +POST_JUMP_AT=<ns> (10)   post test jump out of main_phase
// ============================================================================

`timescale 1ns/1ps

package test_pkg;

  import uvm_pkg::*;
  import nv_socv_sim_restore_pkg::*;
  import tests_common_pkg::*;
  `include "uvm_macros.svh"

  // --------------------------------------------------------------------------
  // Main test.
  // --------------------------------------------------------------------------
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
      post_domain_controller::wait_post_started();
      `uvm_info("ENV", $sformatf("post domain %s @%0t",
                (post_domain_controller::is_post_started() ? "started" : "skipped"),
                $time), UVM_LOW)
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
            save_point::take("B (post domain not built)");
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
    endfunction
  endclass


  // --------------------------------------------------------------------------
  // Post test.
  // --------------------------------------------------------------------------
  class pcie_item extends uvm_sequence_item;
    `uvm_object_utils(pcie_item)
    rand bit [7:0] data;
    function new(string name = "pcie_item");
      super.new(name);
    endfunction
  endclass

  class pcie_seq extends uvm_sequence #(pcie_item);
    `uvm_object_utils(pcie_seq)
    int unsigned n_items = 3;
    function new(string name = "pcie_seq");
      super.new(name);
    endfunction
    virtual task body();
      repeat (n_items) begin
        pcie_item it = pcie_item::type_id::create("it");
        start_item(it);
        void'(it.randomize());
        finish_item(it);
        get_response(rsp);
      end
    endtask
  endclass

  class pcie_driver extends uvm_driver #(pcie_item);
    `uvm_component_utils(pcie_driver)
    uvm_analysis_port #(pcie_item) ap;
    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap = new("ap", this);
    endfunction
    virtual task run_phase(uvm_phase phase);
      forever begin
        pcie_item it, r;
        seq_item_port.get_next_item(it);
        #2;
        $cast(r, it.clone());
        r.set_id_info(it);
        seq_item_port.item_done();
        rsp_port.write(r);
        ap.write(r);
      end
    endtask
  endclass

  class pcie_bus_agent extends uvm_agent;
    `uvm_component_utils(pcie_bus_agent)
    uvm_sequencer #(pcie_item) sqr;
    pcie_driver                drv;
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    virtual function void build_phase(uvm_phase phase);
      sqr = uvm_sequencer #(pcie_item)::type_id::create("sqr", this);
      drv = pcie_driver::type_id::create("drv", this);
    endfunction
    virtual function void connect_phase(uvm_phase phase);
      drv.seq_item_port.connect(sqr.seq_item_export);
      drv.rsp_port.connect(sqr.rsp_export);
    endfunction
  endclass

  class pcie_scoreboard extends uvm_subscriber #(pcie_item);
    `uvm_component_utils(pcie_scoreboard)
    int unsigned n_expected = 3;
    int unsigned n_seen;
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    virtual function void write(pcie_item t);
      n_seen++;
    endfunction
    virtual function void check_phase(uvm_phase phase);
      if (n_seen != n_expected)
        `uvm_error("PCIE_SB", $sformatf("%0d responses, %0d expected", n_seen, n_expected))
      else
        `uvm_info("PCIE_SB", $sformatf("%0d responses, as expected", n_seen), UVM_LOW)
    endfunction
  endclass

  class pcie_coverage extends uvm_subscriber #(pcie_item);
    `uvm_component_utils(pcie_coverage)
    covergroup data_cg with function sample(bit [7:0] d);
      cp_data: coverpoint d {
        bins low  = {[8'h00:8'h7F]};
        bins high = {[8'h80:8'hFF]};
      }
    endgroup
    function new(string name, uvm_component parent);
      super.new(name, parent);
      data_cg = new();
    endfunction
    virtual function void write(pcie_item t);
      data_cg.sample(t.data);
    endfunction
    virtual function void report_phase(uvm_phase phase);
      `uvm_info("PCIE_COV", $sformatf("data_cg %0.1f%%", data_cg.get_coverage()), UVM_LOW)
    endfunction
  endclass

  class pcie_env extends uvm_env;
    `uvm_component_utils(pcie_env)

    bit             has_cov;
    phase_logger    pcie_agt;
    pcie_bus_agent  pcie_bus;
    pcie_scoreboard pcie_sb;
    pcie_coverage   pcie_cov;
    heartbeat       hb;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      int unsigned main_ns = 20;
      pcie_agt = phase_logger::type_id::create("pcie_agt", this);
      pcie_bus = pcie_bus_agent::type_id::create("pcie_bus", this);
      pcie_sb  = pcie_scoreboard::type_id::create("pcie_sb", this);
      hb       = heartbeat::type_id::create("hb", this);
      if (has_cov)
        pcie_cov = pcie_coverage::type_id::create("pcie_cov", this);
      void'($value$plusargs("POST_MAIN=%d", main_ns));
      pcie_agt.main_delay = main_ns;
    endfunction

    virtual function void connect_phase(uvm_phase phase);
      pcie_bus.drv.ap.connect(pcie_sb.analysis_export);
      if (pcie_cov != null)
        pcie_bus.drv.ap.connect(pcie_cov.analysis_export);
    endfunction
  endclass

  class pcie_post_test extends uvm_test;
    `uvm_component_utils(pcie_post_test)

    pcie_env  env;
    pcie_seq  seq;
    jump_once jmp;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    virtual function void configure_env();
    endfunction

    virtual function void build_phase(uvm_phase phase);
      string       jump_to;
      int unsigned jump_at = 10;
      void'($value$plusargs("POST_JUMP_TO=%s", jump_to));
      void'($value$plusargs("POST_JUMP_AT=%d", jump_at));
      jmp = new("post", jump_to, jump_at);

      env = pcie_env::type_id::create("env", this);
      configure_env();
      `uvm_info("POST", $sformatf("%s built @%0t (%s)", get_type_name(), $time,
                (save_point::restored() ? "restored run" : "fresh run")), UVM_NONE)
    endfunction

    virtual function void end_of_elaboration_phase(uvm_phase phase);
      this.print();
    endfunction

    virtual task main_phase(uvm_phase phase);
      if (seq == null) begin
        phase.raise_objection(this);
        seq = pcie_seq::type_id::create("seq");
        seq.start(env.pcie_bus.sqr);
        phase.drop_objection(this);
      end
      jmp.run(this, phase);
    endtask
  endclass

  class pcie_post_test_b extends pcie_post_test;
    `uvm_component_utils(pcie_post_test_b)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    virtual function void configure_env();
      env.has_cov = 1;
    endfunction
  endclass

endpackage

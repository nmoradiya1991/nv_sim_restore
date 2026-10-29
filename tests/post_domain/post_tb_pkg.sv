// ============================================================================
// post_tb_pkg.sv -- Approach B, post domain: the post test, built at
// release_post() during the main test, runtime phases synced. DYNAMIC in the
// DTL flow: not in the saved image, loaded after the restore with
// +dtl_add_pkg=<dir>:post_tb_pkg.
//
//   pcie_post_test (uvm_post_top, post_dom, built at the release)
//     env.pcie_agt : reset 10 ns, main <POST_MAIN> (20) ns
//     env.pcie_bus : sequencer + driver, connected in ps_connect
//     env.pcie_sb  : counts the bus responses, checks them
//     env.hb       : ps_run heartbeat
//     env.pcie_cov : covergroup on the items, only with +define+TOPO_V2
//                    (make ... TOPO=v2)
//
// TOPO_V2 changes the topology of the same test. With FLOW=dtl, rebuild just
// this package (make compile_pkg FLOW=dtl TOPO=v2) and restore the same
// checkpoint: the post test is built with the new topology.
//
// Command-line reprocessing targets: settings applied when the post tree is
// built (release, non-zero time; after a restore: merged with the save
// command line and reapplied): pcie_driver -> pcie_driver_fast / _slow
// (type), uvm_post_top.env.pcie_sb -> pcie_scoreboard_strict (instance),
// uvm_post_top.env.pcie_agt main_delay over the pcie env's own set
// (config_int), uvm_post_top.env profile (config_string); cl_expect keys
// DRV_TYPE, SB_TYPE, PCIE_MAIN, PROFILE (checked at ps_end_of_elaboration).
//
// Plusargs read here:
//   +POST_MAIN=<ns>        pcie_agt main_phase length (20)
//   +POST_JUMP_TO / +POST_JUMP_AT=<ns> (10)   post test jump out of main_phase
// ============================================================================

`timescale 1ns/1ps

package post_tb_pkg;

  import uvm_pkg::*;
  import nv_socv_sim_restore_pkg::*;
  import tests_common_pkg::*;
  `include "uvm_macros.svh"

`ifdef TOPO_V2
  localparam string TOPO = "v2";
`else
  localparam string TOPO = "v1";
`endif

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
    int unsigned                   latency = 2;
    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap = new("ap", this);
    endfunction
    virtual task run_phase(uvm_phase phase);
      forever begin
        pcie_item it, r;
        seq_item_port.get_next_item(it);
        #(latency);
        $cast(r, it.clone());
        r.set_id_info(it);
        seq_item_port.item_done();
        rsp_port.write(r);
        ap.write(r);
      end
    endtask
  endclass

  class pcie_driver_fast extends pcie_driver;
    `uvm_component_utils(pcie_driver_fast)
    function new(string name, uvm_component parent);
      super.new(name, parent);
      latency = 1;
    endfunction
  endclass

  class pcie_driver_slow extends pcie_driver;
    `uvm_component_utils(pcie_driver_slow)
    function new(string name, uvm_component parent);
      super.new(name, parent);
      latency = 8;
    endfunction
  endclass

  class pcie_agent extends cfg_agent;
    `uvm_component_utils(pcie_agent)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
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
        `uvm_info("PCIE_SB", $sformatf("%s: %0d responses, as expected",
                  get_type_name(), n_seen), UVM_LOW)
    endfunction
  endclass

  class pcie_scoreboard_strict extends pcie_scoreboard;
    `uvm_component_utils(pcie_scoreboard_strict)
    time last_at;
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    virtual function void write(pcie_item t);
      if (n_seen > 0 && $time == last_at)
        `uvm_error("PCIE_SB", $sformatf("two responses at %0t", $time))
      last_at = $time;
      super.write(t);
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

    string          profile = "default";
    pcie_agent      pcie_agt;
    pcie_bus_agent  pcie_bus;
    pcie_scoreboard pcie_sb;
    pcie_coverage   pcie_cov;
    heartbeat       hb;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      int unsigned main_ns = 20;
      void'($value$plusargs("POST_MAIN=%d", main_ns));
      void'(uvm_config_string::get(this, "", "profile", profile));
      uvm_config_int::set(this, "pcie_agt", "main_delay", main_ns);
      pcie_agt = pcie_agent::type_id::create("pcie_agt", this);
      pcie_bus = pcie_bus_agent::type_id::create("pcie_bus", this);
      pcie_sb  = pcie_scoreboard::type_id::create("pcie_sb", this);
      hb       = heartbeat::type_id::create("hb", this);
`ifdef TOPO_V2
      pcie_cov = pcie_coverage::type_id::create("pcie_cov", this);
`endif
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

    virtual function void build_phase(uvm_phase phase);
      string       jump_to;
      int unsigned jump_at = 10;
      void'($value$plusargs("POST_JUMP_TO=%s", jump_to));
      void'($value$plusargs("POST_JUMP_AT=%d", jump_at));
      jmp = new("post", jump_to, jump_at);

      env = pcie_env::type_id::create("env", this);
      `uvm_info("POST", $sformatf("%s built @%0t (%s), topology %s", get_type_name(), $time,
                (save_point::restored() ? "restored run" : "fresh run"), TOPO), UVM_NONE)
    endfunction

    virtual function void end_of_elaboration_phase(uvm_phase phase);
      this.print();
      cl_expect::check("DRV_TYPE", env.pcie_bus.drv.get_type_name(), "post tree, type override");
      cl_expect::check("SB_TYPE", env.pcie_sb.get_type_name(), "post tree, instance override");
      cl_expect::check_int("PCIE_MAIN", env.pcie_agt.main_delay, "post tree, config_int vs env default");
      cl_expect::check("PROFILE", env.profile, "post tree, config_string");
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

endpackage

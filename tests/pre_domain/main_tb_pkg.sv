// ============================================================================
// main_tb_pkg.sv -- Approach B, pre domain: the main test, built when the
// boot calls release_main(). DYNAMIC in the DTL flow: not in the saved
// image, loaded after the restore with +dtl_add_pkg=<dir>:main_tb_pkg.
//
//   soc_test_a (uvm_test_top, uvm domain, built at release_main())
//     env.cpu_agt : cpu_agent, main_delay <MAIN_MAIN> (100) set by the env
//     env.ddr_agt : ddr_agent, main_delay half of that
//     env.hb
//     env.soc_sb  : only with +define+TOPO_V2 (make ... TOPO=v2)
//
// TOPO_V2 changes the topology of the same test. With FLOW=dtl, rebuild just
// this package (make compile_pkg FLOW=dtl TOPO=v2) and restore the same
// checkpoint: the main test is built with the new topology.
//
// Pre runtime phases not finished at the release are synced with the main
// test's (PREDOM/SYNC); phase_logger "... ENDED" lines show the sync.
//
// Command-line reprocessing targets: cpu_agent -> cpu_agent_fast /
// cpu_agent_slow (type), uvm_test_top.env.ddr_agt -> ddr_agent_lp
// (instance), uvm_test_top.env.cpu_agt main_delay over the env's own set
// (config_int), uvm_test_top.env profile (config_string); cl_expect keys
// CPU_TYPE, DDR_TYPE, CPU_MAIN, PROFILE (checked at the main
// end_of_elaboration).
//
// Plusargs read here:
//   +MAIN_MAIN=<ns>        cpu_agt main_phase length (100)
//   +MAIN_SEED=<n>         printed by the main test (restore demo)
//   +MAIN_JUMP_TO=<phase>  main test jumps out of main_phase once, at
//   +MAIN_JUMP_AT=<ns>     <ns> into it (50)
// ============================================================================

`timescale 1ns/1ps

package main_tb_pkg;

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
  // Agents (factory override targets).
  // --------------------------------------------------------------------------
  class cpu_agent extends cfg_agent;
    `uvm_component_utils(cpu_agent)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
  endclass

  class cpu_agent_fast extends cpu_agent;
    `uvm_component_utils(cpu_agent_fast)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
  endclass

  class cpu_agent_slow extends cpu_agent;
    `uvm_component_utils(cpu_agent_slow)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
  endclass

  class ddr_agent extends cfg_agent;
    `uvm_component_utils(ddr_agent)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
  endclass

  class ddr_agent_lp extends ddr_agent;
    `uvm_component_utils(ddr_agent_lp)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
  endclass


  // --------------------------------------------------------------------------
  // Main tests.
  // --------------------------------------------------------------------------
  class soc_scoreboard extends uvm_component;
    `uvm_component_utils(soc_scoreboard)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    virtual task run_phase(uvm_phase phase);
      `uvm_info("SB", $sformatf("soc_sb run_phase @%0t", $time), UVM_LOW)
    endtask
  endclass

  class soc_env extends uvm_env;
    `uvm_component_utils(soc_env)

    int unsigned   main_ns = 100;
    string         profile = "default";
    cpu_agent      cpu_agt[2];
    ddr_agent      ddr_agt;
    heartbeat      hb;
    soc_scoreboard soc_sb;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      void'(uvm_config_string::get(this, "", "profile", profile));
      uvm_config_int::set(this, "cpu_agt*", "main_delay", main_ns);
      uvm_config_int::set(this, "ddr_agt", "main_delay", main_ns / 2);
      cpu_agt[0] = cpu_agent::type_id::create("cpu_agt[0]", this);
      cpu_agt[1] = cpu_agent::type_id::create("cpu_agt[1]", this);
      ddr_agt = ddr_agent::type_id::create("ddr_agt", this);
      hb      = heartbeat::type_id::create("hb", this);
`ifdef TOPO_V2
      soc_sb  = soc_scoreboard::type_id::create("soc_sb", this);
`endif
    endfunction
  endclass

  class soc_test_a extends uvm_test;
    `uvm_component_utils(soc_test_a)

    soc_env      env;
    jump_once    jmp;
    int unsigned seed;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      string       jump_to;
      int unsigned jump_at = 50;
      void'($value$plusargs("MAIN_JUMP_TO=%s", jump_to));
      void'($value$plusargs("MAIN_JUMP_AT=%d", jump_at));
      void'($value$plusargs("MAIN_SEED=%d", seed));
      jmp = new("main", jump_to, jump_at);

      env = soc_env::type_id::create("env", this);
      void'($value$plusargs("MAIN_MAIN=%d", env.main_ns));
      `uvm_info("MAIN", $sformatf("%s built @%0t (%s), seed=%0d, topology %s", get_type_name(),
                $time, (save_point::restored() ? "restored run" : "fresh run"), seed, TOPO),
                UVM_NONE)
    endfunction

    virtual function void end_of_elaboration_phase(uvm_phase phase);
      uvm_root::get().print_topology();
      cl_expect::check("CPU_TYPE", env.cpu_agt[0].get_type_name(), "main tree, type override");
      cl_expect::check("DDR_TYPE", env.ddr_agt.get_type_name(), "main tree, instance override");
      cl_expect::check_int("CPU_MAIN", env.cpu_agt[0].main_delay, "main tree, config_int vs env default");
      cl_expect::check("PROFILE", env.profile, "main tree, config_string");
    endfunction

    virtual task main_phase(uvm_phase phase);
      jmp.run(this, phase);
    endtask

    virtual function void report_phase(uvm_phase phase);
      cl_expect::summary();
    endfunction
  endclass

endpackage

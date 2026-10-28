// ============================================================================
// test_pkg.sv -- Approach B, pre domain: common boot in its own domain, the
// main test built when the boot releases it.
//
//   boot_pre_test (uvm_pre_top, pre_dom, built at time 0)
//     env.clk_rst_agt : reset 10 ns
//     env.fw_load_agt : fw_load_agent, main_phase <PRE_MAIN> (60) ns, set by
//                       the env through uvm_config_db (main_delay)
//     env.hb          : pd_run heartbeat, alive until after the main final
//     main_phase      : boot <PRE_BOOT> (40) ns, save point A, release_main()
//
//   soc_test_a (uvm_test_top, uvm domain, built at release_main())
//     env.cpu_agt : cpu_agent, main_delay <MAIN_MAIN> (100) set by the env
//     env.ddr_agt : ddr_agent, main_delay half of that
//     env.hb
//   soc_test_b: soc_test_a + env.soc_sb, cpu main <MAIN_MAIN> x 2
//
// Pre runtime phases not finished at the release are synced with the main
// test's (PREDOM/SYNC); phase_logger "... ENDED" lines show the sync.
//
// Command-line reprocessing targets: factory / config overrides for
//   pre tree  : fw_load_agent -> fw_load_agent_fast (type),
//               uvm_pre_top.env.fw_load_agt main_delay (config_int)
//               cl_expect keys FW_TYPE, FW_MAIN   (checked at pd_eoe)
//   main tree : cpu_agent -> cpu_agent_fast / cpu_agent_slow (type),
//               uvm_test_top.env.ddr_agt -> ddr_agent_lp (instance),
//               uvm_test_top.env.cpu_agt main_delay over the env's own set
//               (config_int), uvm_test_top.env profile (config_string)
//               cl_expect keys CPU_TYPE, DDR_TYPE, CPU_MAIN, PROFILE
//               (checked at the main end_of_elaboration)
//
// Plusargs read here:
//   +PRE_MAIN=<ns>         fw_load_agt main_phase length (60)
//   +PRE_BOOT=<ns>         boot length before release_main() (40)
//   +PRE_NO_RELEASE        never release (gate timeout test)
//   +MAIN_MAIN=<ns>        cpu_agt main_phase length (100)
//   +MAIN_SEED=<n>         printed by the main test (restore demo)
//   +MAIN_JUMP_TO=<phase>  main test jumps out of main_phase once, at
//   +MAIN_JUMP_AT=<ns>     <ns> into it (50)
// ============================================================================

`timescale 1ns/1ps

package test_pkg;

  import uvm_pkg::*;
  import nv_socv_sim_restore_pkg::*;
  import tests_common_pkg::*;
  `include "uvm_macros.svh"

  // --------------------------------------------------------------------------
  // Agents (factory override targets).
  // --------------------------------------------------------------------------
  class fw_load_agent extends cfg_agent;
    `uvm_component_utils(fw_load_agent)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
  endclass

  class fw_load_agent_fast extends fw_load_agent;
    `uvm_component_utils(fw_load_agent_fast)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
  endclass

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
  // Pre test: common boot.
  // --------------------------------------------------------------------------
  class boot_env extends uvm_env;
    `uvm_component_utils(boot_env)

    phase_logger  clk_rst_agt;
    fw_load_agent fw_load_agt;
    heartbeat     hb;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      int unsigned main_ns = 60;
      void'($value$plusargs("PRE_MAIN=%d", main_ns));
      uvm_config_int::set(this, "fw_load_agt", "main_delay", main_ns);
      clk_rst_agt = phase_logger::type_id::create("clk_rst_agt", this);
      fw_load_agt = fw_load_agent::type_id::create("fw_load_agt", this);
      hb          = heartbeat::type_id::create("hb", this);
      clk_rst_agt.main_delay = 0;
    endfunction
  endclass

  class boot_pre_test extends uvm_test;
    `uvm_component_utils(boot_pre_test)

    boot_env     env;
    int unsigned boot_ns = 40;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      env = boot_env::type_id::create("env", this);
      void'($value$plusargs("PRE_BOOT=%d", boot_ns));
      `uvm_info("PRE", $sformatf("pre test built @%0t", $time), UVM_LOW)
    endfunction

    virtual function void end_of_elaboration_phase(uvm_phase phase);
      cl_expect::check("FW_TYPE", env.fw_load_agt.get_type_name(), "pre tree, type override");
      cl_expect::check_int("FW_MAIN", env.fw_load_agt.main_delay, "pre tree, config_int vs env default");
    endfunction

    virtual task main_phase(uvm_phase phase);
      phase.raise_objection(this);
      #(boot_ns);
      if (!$test$plusargs("PRE_NO_RELEASE")) begin
        save_point::take("A (boot done, main test not built)");
        pre_domain_controller::release_main($sformatf("boot done after %0d ns%s",
          boot_ns, (save_point::restored() ? ", restored run" : "")));
      end
      phase.drop_objection(this);
    endtask

    virtual function void report_phase(uvm_phase phase);
      pre_domain_controller ctl = pre_domain_controller::get_inst();
      `uvm_info("PRE", $sformatf("pre report @%0t: main test %s released at %0t",
                $time, ctl.main_test, ctl.released_at), UVM_LOW)
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

    bit            has_sb;
    int unsigned   main_ns = 100;
    string         profile = "default";
    cpu_agent      cpu_agt;
    ddr_agent      ddr_agt;
    heartbeat      hb;
    soc_scoreboard soc_sb;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      void'(uvm_config_string::get(this, "", "profile", profile));
      uvm_config_int::set(this, "cpu_agt", "main_delay", main_ns);
      uvm_config_int::set(this, "ddr_agt", "main_delay", main_ns / 2);
      cpu_agt = cpu_agent::type_id::create("cpu_agt", this);
      ddr_agt = ddr_agent::type_id::create("ddr_agt", this);
      hb      = heartbeat::type_id::create("hb", this);
      if (has_sb)
        soc_sb = soc_scoreboard::type_id::create("soc_sb", this);
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

    virtual function void configure_env();
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
      configure_env();
      `uvm_info("MAIN", $sformatf("%s built @%0t (%s), seed=%0d", get_type_name(),
                $time, (save_point::restored() ? "restored run" : "fresh run"), seed),
                UVM_NONE)
    endfunction

    virtual function void end_of_elaboration_phase(uvm_phase phase);
      uvm_root::get().print_topology();
      cl_expect::check("CPU_TYPE", env.cpu_agt.get_type_name(), "main tree, type override");
      cl_expect::check("DDR_TYPE", env.ddr_agt.get_type_name(), "main tree, instance override");
      cl_expect::check_int("CPU_MAIN", env.cpu_agt.main_delay, "main tree, config_int vs env default");
      cl_expect::check("PROFILE", env.profile, "main tree, config_string");
    endfunction

    virtual task main_phase(uvm_phase phase);
      jmp.run(this, phase);
    endtask

    virtual function void report_phase(uvm_phase phase);
      cl_expect::summary();
    endfunction
  endclass

  class soc_test_b extends soc_test_a;
    `uvm_component_utils(soc_test_b)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    virtual function void configure_env();
      env.has_sb  = 1;
      env.main_ns = env.main_ns * 2;
    endfunction
  endclass

endpackage

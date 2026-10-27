// ============================================================================
// test_pkg.sv -- Approach B, pre domain: common boot in its own domain, the
// main test built when the boot releases it.
//
//   boot_pre_test (uvm_pre_top, pre_dom, built at time 0)
//     env.clk_rst_agt : reset 10 ns
//     env.fw_load_agt : main_phase <PRE_MAIN> (60) ns
//     env.hb          : pd_run heartbeat, alive until after the main final
//     main_phase      : boot <PRE_BOOT> (40) ns, save point A, release_main()
//
//   soc_test_a (uvm_test_top, uvm domain, built at release_main())
//     env.cpu_agt, env.ddr_agt, env.hb
//   soc_test_b: soc_test_a + env.soc_sb, cpu main <MAIN_MAIN> x 2
//
// Pre runtime phases not finished at the release are synced with the main
// test's (PREDOM/SYNC); phase_logger "... ENDED" lines show the sync.
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
  // Pre test: common boot.
  // --------------------------------------------------------------------------
  class boot_env extends uvm_env;
    `uvm_component_utils(boot_env)

    phase_logger clk_rst_agt;
    phase_logger fw_load_agt;
    heartbeat    hb;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      int unsigned main_ns = 60;
      clk_rst_agt = phase_logger::type_id::create("clk_rst_agt", this);
      fw_load_agt = phase_logger::type_id::create("fw_load_agt", this);
      hb          = heartbeat::type_id::create("hb", this);
      void'($value$plusargs("PRE_MAIN=%d", main_ns));
      clk_rst_agt.main_delay = 0;
      fw_load_agt.main_delay = main_ns;
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
    phase_logger   cpu_agt;
    phase_logger   ddr_agt;
    heartbeat      hb;
    soc_scoreboard soc_sb;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      cpu_agt = phase_logger::type_id::create("cpu_agt", this);
      ddr_agt = phase_logger::type_id::create("ddr_agt", this);
      hb      = heartbeat::type_id::create("hb", this);
      if (has_sb)
        soc_sb = soc_scoreboard::type_id::create("soc_sb", this);
      cpu_agt.main_delay = main_ns;
      ddr_agt.main_delay = main_ns / 2;
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
    endfunction

    virtual task main_phase(uvm_phase phase);
      jmp.run(this, phase);
    endtask
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

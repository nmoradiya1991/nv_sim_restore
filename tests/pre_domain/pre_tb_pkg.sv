// ============================================================================
// pre_tb_pkg.sv -- Approach B, pre domain: the common boot (pre test), built
// at time 0 in its own domain. STATIC in the DTL flow (part of the saved
// image); the main tests are in main_tb_pkg.
//
//   boot_pre_test (uvm_pre_top, pre_dom, built at time 0)
//     env.clk_rst_agt : reset 10 ns
//     env.fw_load_agt : fw_load_agent, main_phase <PRE_MAIN> (60) ns, set by
//                       the env through uvm_config_db (main_delay)
//     env.hb          : pd_run heartbeat, alive until after the main final
//     main_phase      : boot <PRE_BOOT> (40) ns, save point A, release_main()
//
// Command-line reprocessing targets: fw_load_agent -> fw_load_agent_fast
// (type), uvm_pre_top.env.fw_load_agt main_delay (config_int); cl_expect
// keys FW_TYPE, FW_MAIN (checked at pd_eoe).
//
// Plusargs read here:
//   +PRE_MAIN=<ns>         fw_load_agt main_phase length (60)
//   +PRE_BOOT=<ns>         boot length before release_main() (40)
//   +PRE_NO_RELEASE        never release (gate timeout test)
// ============================================================================

`timescale 1ns/1ps

package pre_tb_pkg;

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

endpackage

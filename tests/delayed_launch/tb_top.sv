// ============================================================================
// tb_top.sv -- Approach A: delay run_test() until after the boot.
//
//   boot       : pure SV (no UVM component): reset, then FW_WORDS firmware
//                words; pins held at legal idle values. Then save point A
//                (+sim_image_save_enable) and trigger_test_launch().
//   launch     : wait_for_test_launch_trigger() blocks until the trigger
//                when +NV_SOCV_DELAYED_TEST_LAUNCH is given (no-op without
//                it: classic run_test() at time 0), refreshes the command
//                line, then run_test() builds the test at the current time.
//   cfg_reader : module code that reads "dl_mode" published by the test's
//                build_phase, through nv_socv_config_db (waits for the gate).
//
// Plusargs:
//   +NV_SOCV_DELAYED_TEST_LAUNCH  gate run_test() until the boot is done
//   +BOOT_NS=<ns>                 reset length (default 100)
//   +FW_WORDS=<n>                 firmware words loaded after reset (16)
//   +UVM_TESTNAME=<name>          test (default dl_test_a)
//   +sim_image_*                  save/restore (common/sim_save_restore.sv)
// ============================================================================

`timescale 1ns/1ps

module tb_top;

  import uvm_pkg::*;
  import nv_socv_sim_restore_pkg::*;
  import tests_common_pkg::*;
`ifndef NV_DYN_TB
  // DTL / DTR: test_pkg is the dynamic package, loaded after the restore.
  import test_pkg::*;
`endif

  sim_save_restore u_sim_save_restore();

  bit clk;
  always #1 clk = ~clk;

  dl_if dif (clk);

  int unsigned boot_ns  = 100;
  int unsigned fw_words = 16;
  int unsigned fw_loaded;

  initial begin : boot
    dif.rst_n = 1'b0;
    dif.vld   = 1'b0;
    dif.data  = '0;
    void'($value$plusargs("BOOT_NS=%d", boot_ns));
    void'($value$plusargs("FW_WORDS=%d", fw_words));
    #(boot_ns);
    dif.rst_n = 1'b1;
    repeat (fw_words) @(posedge clk) fw_loaded++;
    $display("[tb_top] @%0t boot done: %0d firmware words loaded", $time, fw_loaded);

    save_point::take("A (boot done, no UVM topology)");
    nv_socv_delayed_test_launch::trigger_test_launch();
  end

  initial begin : launch
    uvm_config_db#(virtual dl_if)::set(null, "*", "dl_vif", dif);
    nv_socv_delayed_test_launch::wait_for_test_launch_trigger();
    $display("[tb_top] @%0t run_test() (delayed launch %0s)", $time,
             (nv_socv_delayed_test_launch::is_delayed_launch_active() ? "on" : "off"));
    run_test("dl_test_a");
  end

  initial begin : cfg_reader
    int mode;
    bit found;
    nv_socv_config_db#(int)::get(null, "", "dl_mode", mode, found);
    $display("[tb_top] @%0t nv_socv_config_db dl_mode: %s", $time,
             (found ? $sformatf("%0d", mode) : "not found"));
  end

endmodule

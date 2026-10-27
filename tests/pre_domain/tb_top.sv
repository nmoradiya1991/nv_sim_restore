// ============================================================================
// tb_top.sv -- Approach B, pre domain.
//
// install_pre_domain() before run_test(): boot_pre_test (uvm_pre_top) runs
// from time 0 in pre_dom; run_test() without a name creates no test at
// time 0, so the main test is chosen at the release, after the command
// line is reprocessed: +UVM_TESTNAME, else soc_test_a.
//
// Plusargs:
//   +PRE_GATE_TIMEOUT=<ns>  fatal if the boot does not release the main
//                           test within <ns> (default 0: no limit)
//   +UVM_TESTNAME=<name>    main test (default soc_test_a)
//   +PREDOM_ADOPT / +PREDOM_ADOPT_RETURN / +PREDOM_EXCLUDE=<glob,...>
//   +sim_image_*            save/restore (common/sim_save_restore.sv)
// ============================================================================

`timescale 1ns/1ps

module tb_top;

  import uvm_pkg::*;
  import nv_socv_sim_restore_pkg::*;
  import tests_common_pkg::*;
  import test_pkg::*;

  sim_save_restore u_sim_save_restore();

  initial begin
    pre_domain_controller ctl;
    ctl = install_pre_domain("boot_pre_test", "soc_test_a");
    void'($value$plusargs("PRE_GATE_TIMEOUT=%d", ctl.gate_timeout_ns));
    run_test();
  end

endmodule

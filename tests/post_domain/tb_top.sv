// ============================================================================
// tb_top.sv -- domain-based proposal, post domain.
//
// Plain run_test(): soc_main_test is built at time 0 and its env installs
// the post domain. The post test is created at release_post(), after the
// command line is reprocessed: +POST_TEST, else pcie_post_test.
//
// Plusargs:
//   +UVM_TESTNAME=<name>     main test (default soc_main_test)
//   +POST_TEST=<name>        post test (default pcie_post_test)
//   +POST_GATE_TIMEOUT=<ns>  fatal if not released within <ns> (default 0:
//                            wait until the main runtime phases end, skip)
//   +PSDOM_NO_JUMP_MIRROR    do not mirror runtime phase jumps
//   +RELEASE_FROM_TB=<ns>    release from this module at <ns> (with
//                            +NO_RELEASE to disable the test's release)
//   +sim_image_*             save/restore (common/sim_save_restore.sv)
// ============================================================================

`timescale 1ns/1ps

module tb_top;

  import uvm_pkg::*;
  import nv_socv_sim_restore_pkg::*;
  import tests_common_pkg::*;
  import main_tb_pkg::*;
`ifndef NV_DYN_TB
  // DTL / DTR: post_tb_pkg is the dynamic package, loaded after the restore.
  import post_tb_pkg::*;
`endif

  sim_save_restore u_sim_save_restore();

  initial run_test("soc_main_test");

  initial begin
    bit started;
    pd_wait_post_started(started);
    $display("[tb_top] @%0t post domain %s", $time, (started ? "started" : "skipped"));
  end

  initial begin
    int unsigned release_ns;
    if ($value$plusargs("RELEASE_FROM_TB=%d", release_ns)) begin
      #(release_ns);
      pd_release_post($sformatf("tb_top after %0d ns", release_ns));
    end
  end

endmodule

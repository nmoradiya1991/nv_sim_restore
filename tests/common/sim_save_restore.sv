// ============================================================================
// sim_save_restore.sv -- simulation image save/restore for the tests,
// modelled on nitro_lib nitro_utils (same plusargs and events).
//
//   VCS     : $save(<dir>/<file>); restore with simv -r <dir>/<file> ...
//   Xcelium : $save(<file>), elaborated and run with -process_save;
//             restore with xrun -r <file> ...   (+define+NV_SR_XCELIUM)
//             DTR: base snapshot built with -mkdbssnap; restore with
//             xrun <pkg>.sv -dbsname <base> -dbssnap <file> ...
//
// Plusargs (save run):
//   +sim_image_save_enable            enable saving
//   +sim_image_save_dir_path=<dir>    VCS checkpoint directory (default .)
//   +sim_image_save_file=<name>       checkpoint file / name (default sim.<t>ps.chk)
//   +sim_image_save_time=<ps>         also save at <ps> (0 / unset: no timed save)
//   +sim_finish_after_save            $finish right after the save
// Plusargs (restored run):
//   +sim_image_restore_enable         fire "sim_image_restored" after restore
//   +dtl_add_pkg=<dir>:<pkg>          VCS Dynamic Test Load: $dtl_load the
//                                     package right after the restore, before
//                                     "sim_image_restored" / "sim_image_saved"
//                                     (static image compiled with
//                                     -enable_dynamic_tb +define+NV_DTL)
//   +dtr_pkg=<pkg>                    Xcelium Dynamic Test Reload: only logged.
//                                     xrun links <pkg> with the saved snapshot
//                                     (-dbsname / -dbssnap) before the restart,
//                                     so its classes are already registered
//
// Global uvm_events (uvm_event_pool::get_global), usable from module and
// class code:
//   "sim_image_save"     : request a save
//   "sim_image_saved"    : save point passed (save run and restored run)
//   "sim_image_restored" : the simulation was restored
// Only one instance per testbench.
// ============================================================================

`ifndef SIM_SAVE_RESTORE_SV
`define SIM_SAVE_RESTORE_SV

module sim_save_restore;

  timeunit      1ns;
  timeprecision 1ps;

  import uvm_pkg::*;

  longint unsigned save_time_ps;
  string           save_dir = ".";
  bit              restored;

  uvm_event        save_req_ev;
  uvm_event        saved_ev;
  uvm_event        restored_ev;

  // The dynamic package's classes register with the factory when it is
  // loaded, so it must be loaded before anything waiting on the save point
  // creates a test from it.
  task automatic dtl_load();
    string pkg;
    if ($value$plusargs("dtr_pkg=%s", pkg))
      $display("<%0t> SIM_IMAGE: DTR package %s linked with the restored snapshot",
               $realtime, pkg);
    if (!$value$plusargs("dtl_add_pkg=%s", pkg))
      return;
`ifdef NV_DTL
    $display("<%0t> SIM_IMAGE: $dtl_load (+dtl_add_pkg=%s)", $realtime, pkg);
    $dtl_load;
`else
    $display("<%0t> SIM_IMAGE: +dtl_add_pkg=%s ignored: static image not compiled with +define+NV_DTL",
             $realtime, pkg);
`endif
  endtask

  task automatic save_image();
    string save_file;

    if (!$value$plusargs("sim_image_save_file=%s", save_file))
      save_file = $sformatf("sim.%0dps.chk", longint'($realtime / 1ps));
`ifndef NV_SR_XCELIUM
    // Xcelium takes the bare checkpoint name, the same name given to xrun -r.
    save_file = {save_dir, "/", save_file};
`endif

    $display("<%0t> SIM_IMAGE: saving checkpoint %s", $realtime, save_file);
    $save(save_file);

    // A restored simulation resumes here, with the restore command line.
    #1ps;
    if ($test$plusargs("sim_image_restore_enable") && !restored) begin
      restored = 1'b1;
      $display("<%0t> SIM_IMAGE: simulation restored", $realtime);
      dtl_load();
      restored_ev.trigger();
    end
    saved_ev.trigger();

    if ($test$plusargs("sim_finish_after_save") && !restored) begin
      $display("<%0t> SIM_IMAGE: +sim_finish_after_save, ending the save run",
               $realtime);
      $finish;
    end
  endtask

  initial begin
    save_req_ev = uvm_event_pool::get_global("sim_image_save");
    saved_ev    = uvm_event_pool::get_global("sim_image_saved");
    restored_ev = uvm_event_pool::get_global("sim_image_restored");

    if ($test$plusargs("sim_image_save_enable")) begin
      void'($value$plusargs("sim_image_save_dir_path=%s", save_dir));
      if (!$value$plusargs("sim_image_save_time=%d", save_time_ps))
        save_time_ps = 0;
      $display("%m: sim image save enabled (dir %s, timed save at %0d ps)",
               save_dir, save_time_ps);
      fork
        if (save_time_ps != 0) begin
          #(1ps * save_time_ps);
          save_image();
        end
        forever begin
          save_req_ev.wait_ptrigger();
          save_req_ev.reset();
          save_image();
        end
      join_none
    end
  end

endmodule

`endif // SIM_SAVE_RESTORE_SV

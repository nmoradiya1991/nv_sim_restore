# Xcelium save run: sim_save_restore.sv issues $stop at the save point; save
# the simulation snapshot $env(XRUN_SNAP) there, then continue (the run ends
# right after the save with +sim_finish_after_save).
# Restore with: xrun -r $env(XRUN_SNAP) +sim_image_restore_enable <new args>
set snap ckpt
if {[info exists env(XRUN_SNAP)]} {
  set snap $env(XRUN_SNAP)
}
run
puts "xrun_save.tcl: saving simulation snapshot '$snap' at [time]"
save -simulation -overwrite $snap
run
exit

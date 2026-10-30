# Save / restore

| | Save run | Restore run |
|:--|:--|:--|
| **VCS** | `./simv <args> +sim_image_save_enable +sim_image_save_dir_path=<dir> +sim_image_save_file=<f> [+sim_finish_after_save]` → `$save` | `./simv -r <dir>/<f> +sim_image_restore_enable <new args>` |
| **Xcelium** | elaborate and run with `-64bit -process_save`: `xrun -64bit -R -process_save <args> +sim_image_save_enable +sim_image_save_file=<name> [+sim_finish_after_save]` → `$save("<name>")` | `xrun -64bit -r <name> +sim_image_restore_enable <new args>` |
| Approach A | `+NV_SOCV_DELAYED_TEST_LAUNCH` | `+UVM_TESTNAME=<test>` + test plusargs / `+uvm_set_*` |
| Pre domain (point A) | *no* `+UVM_TESTNAME` | `+UVM_TESTNAME=<main test>` + main plusargs |
| Post domain (point B) | `+UVM_TESTNAME=<main>` | `+POST_TEST=<post test>` + post plusargs |

- **`$time` is preserved.** The restored run continues at the save time; the
  pre/post builds happen at that time (`RUNPHSTIME` is suppressed for
  Approach A). Timeouts are absolute.
- **Choose the save point before any `+UVM_TESTNAME`-dependent object exists.**
  A test created before the save cannot be replaced by the restore.
- Module code and classes request a save with the global `uvm_event`
  `"sim_image_save"` and resume on `"sim_image_saved"` (see
  [`tests/common/sim_save_restore.sv`](../tests/common/sim_save_restore.sv)).


## Xcelium: process-based save/restart

| Step | How |
|:--|:--|
| Enable | `-process_save` on the elaboration **and** the simulation command line; `-64bit` is recommended with it |
| Save | `xrun -64bit ... -process_save`; the testbench calls `$save("<name>")` at the save point (here: `+sim_image_save_file=<name>`) |
| Restore & proceed | `xrun -r <name>` with the same name as the saved checkpoint |

The flow relies on the restored run seeing its *new* plusargs
(`$test$plusargs` and `uvm_dpi_get_next_arg()`). Check
`NV_SOCV_CMDLINE_PROCESSOR/*` and `PSDOM/GATE` / `PREDOM/GATE` in
`logs/restore_*_xrun.log` the first time you use a new Xcelium version.

## VCS Dynamic Test Load (DTL)

The saved image contains only the **static** part. The **dynamic** package
(the tests built after the save point) is compiled separately against it.
After the restore, `sim_save_restore.sv` loads it with `$dtl_load`, before
anything continues from the save point. This lets you change and recompile the
dynamic package without regenerating the checkpoint. DTL is supported with VCS
only.

DTL is a **flow**, not a separate set of targets. `FLOW=dtl` switches
`compile`, `save` and `restore` (and the scenario targets built on them) to
the DTL commands. `compile_pkg` is the only DTL-only target.

| Step | `FLOW=dtl` command (from `common.mk`) |
|:--|:--|
| `compile` | `vlogan +define+NV_DTL uvm_pkg.sv <library> <tests common> -f static.f` · `vcs -top tb_top -partcomp -dir=DTL_STATIC -enable_dynamic_tb uvm_dpi.cc -o simv_dtl`, then `compile_pkg` |
| `compile_pkg` | `vlogan <pkg>.sv` · `vcs -partcomp <pkg> -dir=DTL_<pkg> -sharedlib=DTL_STATIC -dynamic_tb` |
| `save` | `./simv_dtl ... +sim_image_save_enable` → `ckpt_vcs_dtl/<ckpt>.chk` |
| `restore` | `./simv_dtl -r ckpt_vcs_dtl/<ckpt>.chk +sim_image_restore_enable +dtl_add_pkg=DTL_<pkg>:<pkg> <new args>` |

```bash
cd tests/post_domain                           # same in delayed_launch and pre_domain
export VCS_HOME=/home/tools/vcs/2025.06-SP2-3
make compile FLOW=dtl                          # static simv_dtl + dynamic post_tb_pkg
make save    FLOW=dtl                          # static image only; ◆ B, then $finish
make restore FLOW=dtl                          # loads post_tb_pkg, builds the post test from it
make restore_cl FLOW=dtl                       # new overrides of classes of the loaded package
make compile_pkg FLOW=dtl TOPO=v2              # new topology of the same post test (or any edit
make restore FLOW=dtl                          # of post_tb_pkg.sv); same checkpoint, no new save
```

Both flows can coexist in one folder: they use separate executables
(`simv` / `simv_dtl`), checkpoint directories (`ckpt_vcs` / `ckpt_vcs_dtl`)
and log names (`*_vcs.log` / `*_vcs_dtl.log`). Elaboration options must be
the same in both DTL steps (`DTL_ELAB_OPTS`), otherwise VCS reports
`DTL-SHLIB-ERR`.

| Folder | Save point | Dynamic package | Not available with `FLOW=dtl` |
|:--|:--|:--|:--|
| `delayed_launch` | ◆ A, boot done | `test_pkg` | `run_*` |
| `pre_domain` | ◆ A, gate closed | `main_tb_pkg` | `run_*`, `save_cl`, `restore_cl_drop` (`restore_cl` restores the `save` checkpoint) |
| `post_domain` | ◆ B, before `release_post()` | `post_tb_pkg` | `run_*`, `save_cl`, `restore_cl_keep` (`restore_cl` restores the `save` checkpoint) |

> `run_*` targets have no restore, so nothing loads the dynamic package.
> Command-line overrides that name dynamic classes must be given at the
> **restore**: the save run doesn't have those classes, so UVM rejects them.
> In `pre_domain` and `post_domain`, that rules out `save_cl` with its stale
> overrides. In `delayed_launch` it doesn't apply, because the stale
> settings are only used after the restore.

## Xcelium Dynamic Test Reload (DTR)

`SIM=xrun FLOW=dtr`. The same static / dynamic split as DTL (`static.f` and
the folder's dynamic package), built with the Xcelium dynamic test flow:

| Step | Target | Command |
|:--|:--|:--|
| Dynamic base snapshot (DBS): time-0 model with the DUT, `tb_top` and the static packages | `compile` | `xrun -64bit -sv -uvm -uvmhome $UVM_HOME -elaborate -process_save -mkdbssnap -name dbs_base +define+NV_DYN_TB <library> -f static.f -xmlibdirname xcelium_dtr.d` |
| Run the DBS to the save point; `$save("<ckpt>")` | `save` | `xrun -64bit -r dbs_base -name dbs_base -process_save -cds_implicit_tmpdir ckpt_xrun_dtr +sim_image_save_enable +sim_image_save_file=<ckpt> ...` |
| Dynamic test snapshot (DTS): compile the package, link it with the saved snapshot, restart from it | `restore` | `xrun -64bit -sv -uvm -uvmhome $UVM_HOME -uvmnoautocompile -process_save <pkg>.sv -dbsname dbs_base -dbssnap <ckpt> -cds_alternate_tmpdir ckpt_xrun_dtr +sim_image_restore_enable +dtr_pkg=<pkg> <new args>` |

```bash
cd tests/post_domain                           # same in delayed_launch and pre_domain
export XCELIUM_HOME=/path/to/XCELIUM<version>
export UVM_HOME=CDNS-1.2
make compile SIM=xrun FLOW=dtr                 # DBS from static.f; post_tb_pkg is not in it
make save    SIM=xrun FLOW=dtr                 # ◆ B, $save("post_ckpt_b"), then $finish
make restore SIM=xrun FLOW=dtr                 # DTS: compiles post_tb_pkg, restarts from post_ckpt_b
make restore SIM=xrun FLOW=dtr TOPO=v2         # edited package (here: new topology), same checkpoint
```

Differences from DTL:

- The package is compiled and linked as part of every restore, so there is no
  `compile_pkg` step (`compile_pkg` only prints a note with `FLOW=dtr`).
- No load call after the restore: the package's classes register with the
  factory when xrun loads the test snapshot, before the restart.
  `sim_save_restore.sv` only logs `+dtr_pkg` at the restore point.
- The DBS, the saved snapshots and the DTS live in `xcelium_dtr.d`
  (`-xmlibdirname`); the process images in `ckpt_xrun_dtr`
  (`-cds_implicit_tmpdir` on the save, `-cds_alternate_tmpdir` on the
  restore). The `FLOW=std` Xcelium library `xcelium.d` is not touched.
- For restores in parallel, give each one its own library (`XLIB=<dir>`,
  a copy of `xcelium_dtr.d` after the save), since each restore writes a DTS
  into it.

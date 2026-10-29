# nv_sim_restore

A UVM library for building the testbench at non-zero time: after a boot, after
a checkpoint restore, or during the main test. Each late build reprocesses the
command line first. Supported on VCS and Xcelium, with UVM 1.2 or IEEE 1800.2.

## Repository layout

```
nv_sim_restore/
├── src/                      library: nv_socv_sim_restore_pkg.sv (includes the rest)
├── doc/                      design and usage documentation
└── tests/
    ├── common/               common.mk, sim_save_restore.sv, tests_common_pkg.sv
    ├── delayed_launch/       Approach A: run_test() after the boot
    ├── pre_domain/           Approach B: boot in the pre domain, main test at release
    └── post_domain/          Approach B: post test built during the main test
```

Each test folder has a `Makefile`, `files.f` (all files), `static.f` (DTL
static image) and `tb_top.sv`. `make help` lists the folder's targets.

## Documentation

| Doc | Contents |
|:--|:--|
| [doc/overview.md](doc/overview.md) | the problem, approaches, package files, topology over time |
| [doc/delayed_launch.md](doc/delayed_launch.md) | Approach A: delayed `run_test()` |
| [doc/pre_domain.md](doc/pre_domain.md) | Approach B: pre domain |
| [doc/post_domain.md](doc/post_domain.md) | Approach B: post domain |
| [doc/cmdline_reprocessing.md](doc/cmdline_reprocessing.md) | command-line refresh / merge rules, worked override cases |
| [doc/save_restore.md](doc/save_restore.md) | save / restore, Xcelium `-process_save`, VCS Dynamic Test Load |
| [doc/tests.md](doc/tests.md) | test folders and targets |

## Setup

| Variable | Needed for | Example |
|:--|:--|:--|
| `VCS_HOME` | VCS if `vcs` is not on `PATH`; always set for `FLOW=dtl` | `/home/tools/vcs/2025.06-SP2-3` |
| `XCELIUM_HOME` (or `XRUN`) | `SIM=xrun` | `/path/to/XCELIUM<version>` |
| `UVM_HOME` | `SIM=xrun` (`-uvmhome`) | `CDNS-1.2` |

Optional make variables:

| Variable | Default | Meaning |
|:--|:--|:--|
| `SIM` | `vcs` | `vcs` or `xrun` |
| `FLOW` | `std` | `std`, or `dtl` (VCS Dynamic Test Load, VCS only) |
| `UVM_VER` | `uvm-1.2` | VCS UVM library |
| `VERBOSITY` | `UVM_MEDIUM` | `+UVM_VERBOSITY` |
| `ARGS` | — | extra plusargs on every run |
| `SAVE_FINISH` | `1` | `$finish` right after the save |
| `VCS_EXTRA` / `XRUN_EXTRA` | — | extra compile options |
| `DTL_ELAB_OPTS` | `-full64 -sverilog +vcs+lic+wait` | `FLOW=dtl`: options of both elaborations (must match) |

Logs go to `tests/<folder>/logs/<target>_<sim>[_dtl].log`.

## Compile and run

The commands are the same in every test folder; only the test-selection variables differ.

```bash
cd tests/post_domain            # or delayed_launch, pre_domain

make compile                    # build
make run_default                # plain run, no save
make save                       # run to the save point, save, $finish
make restore                    # restore and continue with a new command line
make clean
```

| Folder | Save point | Select the test on restore |
|:--|:--|:--|
| `delayed_launch` | A: boot done, no UVM tree | `make restore TEST=dl_test_b DL_MODE=7 N_ITEMS=8` |
| `pre_domain` | A: boot done, main test not built | `make restore MAIN_TEST=soc_test_b MAIN_SEED=42` |
| `post_domain` | B: main test running, post test not built | `make restore POST_TEST=pcie_post_test_b POST_MAIN=50` |

In `delayed_launch`, use `run_delayed` instead of `run_default`.

### Xcelium

```bash
export XCELIUM_HOME=/path/to/XCELIUM<version>
export UVM_HOME=CDNS-1.2
make compile save restore SIM=xrun
```

### VCS Dynamic Test Load

The saved image holds only the static part. The dynamic package is compiled
separately and loaded after the restore.

```bash
export VCS_HOME=/home/tools/vcs/2025.06-SP2-3
make compile FLOW=dtl           # static simv_dtl + dynamic package
make save    FLOW=dtl
make restore FLOW=dtl
make compile_pkg FLOW=dtl       # after editing only the dynamic package; then restore again
```

`run_*` targets are not available with `FLOW=dtl`. See
[doc/save_restore.md](doc/save_restore.md#vcs-dynamic-test-load-dtl) for details.

## What to expect after a restore

In every folder, `make save` stops at the save point, before the part of the
testbench that varies per test exists. `make restore` then builds that part
from the **new** command line, with no recompile. The excerpts below are from
VCS runs with the default restore variables (paths trimmed; times are in fs,
so `@50000000` = 50 ns).

**`FLOW=std` and `FLOW=dtl` produce the same restore log.** The only extra
line in DTL is the dynamic package load, right after the restore:

```
<50001000> SIM_IMAGE: simulation restored
<50001000> SIM_IMAGE: $dtl_load (+dtl_add_pkg=DTL_main_tb_pkg:main_tb_pkg)
```

Every restore ends with `UVM_ERROR : 0` and `UVM_FATAL : 0`.

### delayed_launch: the whole UVM test is chosen after the restore

Save (131 ns): the boot is done in plain SystemVerilog, and no UVM topology exists yet.

```
[tb_top] @131000000 boot done: 16 firmware words loaded
[SAVEPT] save point A (boot done, no UVM topology): requesting a sim image save @131000000
```

Restore (`TEST=dl_test_b DL_MODE=7 N_ITEMS=8`): the command line is
repopulated and `run_test()` launches only now, picking up the test name,
config and `nv_socv_config_db` values from the restore command line:

```
[NV_SOCV_CMDLINE_PROCESSOR/REPOPULATE] Command line repopulated
[NV_SOCV_DELAYED_TEST_LUNCH] Test launch event triggered
[RNTST] Running test dl_test_b...
[UVM_CMDLINE_PROC] Applying config setting from the command line: +uvm_set_config_int=uvm_test_top.env.drv,n_items,8
[TEST] dl_test_b built @131000000 (restored run), dl_mode=7
[DRV] dl_driver built @131000000, n_items=8 gap=1
[CHK] dl_checker: 8 words on the pins, as driven
```

### pre_domain: the boot tree is saved, the main test is chosen after the restore

Save (50 ns): `uvm_pre_top` (the boot test in the `pre_dom` domain) is built
at time 0 and is in the middle of its `main` phase. `uvm_test_top` does not
exist yet.

```
[NV_SOCV_CMDLINE_PROCESSOR/EARLY_BUILD] Applying command-line factory/config settings before the pre-domain build
[PRE] pre test built @0
[SAVEPT] save point A (boot done, main test not built): requesting a sim image save @50000000
```

Restore (`MAIN_TEST=soc_test_b MAIN_SEED=42`): the gate releases the main
test, the command line is reprocessed, and `soc_test_b` is built at 50 ns:

```
[PREDOM/GATE] Main test released: boot done after 40 ns, restored run
[NV_SOCV_CMDLINE_PROCESSOR/LATE_BUILD] Reprocessing command line before the main-test build
[NV_SOCV_CMDLINE_PROCESSOR/REPOPULATE] Command line repopulated
[NV_SOCV_CMDLINE_PROCESSOR/REAPPLY] UVM command-line settings reapplied
[PREDOM] Running test soc_test_b
[MAIN] soc_test_b built @50000000 (restored run), seed=42
```

The topology now shows both trees: the restored boot tree and the new main
tree. The boot tree continues from where it was saved: its `main` phase ends
at 70 ns, while the main test runs its own phases from 50 ns. Both report at
the end (160 ns).

```
uvm_pre_top      boot_pre_test      <- from the checkpoint
  env            boot_env
uvm_test_top     soc_test_b         <- built after the restore
  env            soc_env
    cpu_agt[0..1], ddr_agt, hb, soc_sb
```

### post_domain: the main test is saved, the post test is chosen after the restore

Save (40 ns): `uvm_test_top` (the main test) is running its `main` phase. The
post domain is installed, but its tree is not built.

```
[PSDOM] Post domain 'post_dom' installed (post test pcie_post_test); waits for release_post()
[SAVEPT] save point B (post domain not built): requesting a sim image save @40000000
```

Restore (`POST_TEST=pcie_post_test_b POST_MAIN=50`): the new arguments are
**merged** into the existing command line (the main tree is already built),
the post test is replaced, and `uvm_post_top` is built during the main
`main_phase`:

```
[PSDOM/GATE] Post domain released: main main_phase + 30 ns, restored run
[NV_SOCV_CMDLINE_PROCESSOR/APPEND] Command-line args merged
[NV_SOCV_CMDLINE_PROCESSOR/REAPPLY] UVM command-line settings reapplied
[PSDOM] +POST_TEST=pcie_post_test_b replaces post test pcie_post_test
[POST] pcie_post_test_b built @40000000 (restored run)
[CFG] uvm_post_top.env.pcie_agt (pcie_agent) built @40000000: main_delay=50 profile=default
[PSDOM/ILLCRT] 27 post-tree component(s) created after the main build; ILLCRT suppressed for them
[PSDOM/SYNC] Post runtime phases synced with the uvm domain (main is in 'main'). ...
```

The post tree runs the runtime phases that the main test has already finished
back to back, then moves in step with it. Both `main` phases end together at
110 ns, and the post checks run in the same simulation:

```
[PCIE_SB] pcie_scoreboard: 3 responses, as expected
[MAIN] post domain: released at ..., skipped=0, synced=1, jumps mirrored=0
```

The report catcher shows `caught UVM_FATAL reports : 27`. These are the
ILLCRT (component created after build) fatals for the 27 post-tree
components, caught on purpose; the final summary has `UVM_FATAL : 0`.

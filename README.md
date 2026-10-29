# nv_socv_sim_restore

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

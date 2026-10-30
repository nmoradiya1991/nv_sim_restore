# nv_sim_restore

A UVM library for building the testbench at non-zero time, so that one
checkpoint serves many tests: **delayed UVM invocation** (`run_test()` after
the boot or after a restore of the boot checkpoint), **command-line
reprocessing** (the restore's UVM args select the test or the scenario, also
after a feature checkpoint), and the **domain-based proposal** (pre / post
domain) where the boot cannot leave UVM. Supported on VCS and Xcelium, with
UVM 1.2 or IEEE 1800.2.

## Repository layout

```
nv_sim_restore/
├── src/                      library: nv_socv_sim_restore_pkg.sv (includes the rest)
├── doc/                      design and usage documentation
└── tests/
    ├── common/               common.mk, sim_save_restore.sv, tests_common_pkg.sv
    ├── delayed_launch/       delayed UVM invocation: run_test() after the boot; feature checkpoint C
    ├── pre_domain/           domain-based proposal: boot in the pre domain, main test at release
    └── post_domain/          domain-based proposal: post test built during the main test
```

Each test folder has a `Makefile`, `files.f` (all files), `static.f` (DTL /
DTR static image) and `tb_top.sv`. `make help` lists the folder's targets.

## Documentation

| Doc | Contents |
|:--|:--|
| [doc/overview.md](doc/overview.md) | the problem, checkpoints, solution space, checkpoint life, UVM time-zero assumptions, package files |
| [doc/delayed_launch.md](doc/delayed_launch.md) | delayed UVM invocation: delayed `run_test()`, feature checkpoint C |
| [doc/pre_domain.md](doc/pre_domain.md) | domain-based proposal: pre domain |
| [doc/post_domain.md](doc/post_domain.md) | domain-based proposal: post domain |
| [doc/cmdline_strategy.md](doc/cmdline_strategy.md) | why and how the UVM command line is reprocessed: repopulate vs. merge, precedence, diagrams |
| [doc/cmdline_reprocessing.md](doc/cmdline_reprocessing.md) | how the command-line tables are reread, rewritten and reused, API |
| [doc/save_restore.md](doc/save_restore.md) | save / restore, Xcelium `-process_save`, VCS Dynamic Test Load, Xcelium Dynamic Test Reload |
| [doc/tests.md](doc/tests.md) | test folders and targets, command-line targets and expected results |
| [doc/tool_uvm_dependencies.md](doc/tool_uvm_dependencies.md) | simulator and UVM library dependencies found so far, open items, qualifying new releases |

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
| `FLOW` | `std` | `std`; `dtl` (VCS Dynamic Test Load, `SIM=vcs` only); `dtr` (Xcelium Dynamic Test Reload, `SIM=xrun` only) |
| `UVM_VER` | `uvm-1.2` | VCS UVM library |
| `VERBOSITY` | `UVM_MEDIUM` | `+UVM_VERBOSITY` |
| `ARGS` | — | extra plusargs on every run |
| `SAVE_FINISH` | `1` | `$finish` right after the save |
| `VCS_EXTRA` / `XRUN_EXTRA` | — | extra compile options |
| `DTL_ELAB_OPTS` | `-full64 -sverilog +vcs+lic+wait` | `FLOW=dtl`: options of both elaborations (must match) |
| `DTR_BASE` | `dbs_base` | `FLOW=dtr`: name of the dynamic base snapshot |
| `TOPO` | `v1` | `v2`: `pre_domain` / `post_domain` compile the package built after the checkpoint with `+define+TOPO_V2`, a different topology of the same test |
| `CL` | `1` | `pre_domain` / `post_domain`: `make restore` also passes and checks command-line overrides; `0`: off |

Logs go to `tests/<folder>/logs/<target>_<sim>[_dtl|_dtr].log`.

## Compile and run

The commands are the same in every test folder.

```bash
cd tests/post_domain            # or delayed_launch, pre_domain

make compile                    # build
make run_default                # plain run, no save
make save                       # run to the checkpoint, save, $finish
make restore                    # restore and continue with a new command line
make clean
```

| Folder | Checkpoint | Built after the restore | Restore example |
|:--|:--|:--|:--|
| `delayed_launch` | boot checkpoint A: boot done, no UVM tree | the whole UVM test | `make restore TEST=dl_test_b DL_MODE=7 N_ITEMS=8` |
| `delayed_launch` | feature checkpoint C: `dl_test_f` after IP init and pipeline fill | the common scenario sequence | `make restore_c SCENARIO=5` |
| `pre_domain` | boot checkpoint A: boot done, main test not built | main test `soc_test_a` | `make restore MAIN_SEED=42` |
| `post_domain` | feature checkpoint B: main test running, post test not built | post test `pcie_post_test` | `make restore POST_MAIN=50` |

In `delayed_launch`, use `run_delayed` instead of `run_default`. Checkpoint
A and C are each saved from scratch: `make save restore` tests delayed UVM
invocation, `make save_c restore_c restore_c_keep` (`FLOW=std` only) tests
the merge and reapply at a feature checkpoint.

In `pre_domain` and `post_domain` the restore keeps the same test. The new
command line changes how its tree is built, and the dynamic package (`TOPO`)
changes its topology. `make restore` also passes factory overrides and
`config_db` settings for the tree built after the restore, and checks that
they took effect (`CL_EXPECT` lines in the log). `CL=0` turns this off:

| Folder | Command-line settings checked on `make restore` (`CL=1`, default) |
|:--|:--|
| `pre_domain` | `cpu_agent` → `cpu_agent_fast` (type), `env.ddr_agt` → `ddr_agent_lp` (instance), `cpu_agt` `main_delay` 250 over the env's own set, env `profile` `perf` |
| `post_domain` | `pcie_driver` → `pcie_driver_fast` (type), `env.pcie_sb` → `pcie_scoreboard_strict` (instance), `pcie_agt` `main_delay` 77 over the env's `POST_MAIN` set, env `profile` `gen5`; main tree: `post_window` 40 re-read and `soc_txn` → `soc_txn_ext` for an object created after the release |

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
make compile_pkg FLOW=dtl TOPO=v2   # new topology of the same test: rebuild the package only,
make restore FLOW=dtl               # then restore the SAME checkpoint; no new save needed
```

`run_*` targets are not available with `FLOW=dtl`. See
[doc/save_restore.md](doc/save_restore.md#vcs-dynamic-test-load-dtl) for details.

### Xcelium Dynamic Test Reload

Same idea on Xcelium. `compile` builds the dynamic base snapshot (DBS)
from `static.f` with `-mkdbssnap`. `save` runs it to the checkpoint. Each
`restore` compiles the dynamic package and links it with the saved snapshot
(`-dbsname` / `-dbssnap`, the dynamic test snapshot), then restarts from it.
There is no separate package build: every restore picks up the current
package source.

```bash
export XCELIUM_HOME=/path/to/XCELIUM<version>
export UVM_HOME=CDNS-1.2
make compile save restore SIM=xrun FLOW=dtr      # base snapshot, save, restore
make restore SIM=xrun FLOW=dtr TOPO=v2           # same checkpoint, new topology
```

`run_*` targets are not available with `FLOW=dtr`. See
[doc/save_restore.md](doc/save_restore.md#xcelium-dynamic-test-reload-dtr) for details.

## What to expect after a restore

In every folder, `make save` stops at the checkpoint, before the part of the
testbench built after it exists. `make restore` then builds that part from
the **new** command line, with no recompile. The excerpts below are from the
VCS runs of

```bash
make -C delayed_launch compile save_cl restore_cl FLOW=std|dtl
make -C pre_domain     compile save    restore    FLOW=std|dtl
make -C post_domain    compile save    restore    FLOW=std|dtl
```

(paths and `UVM_INFO <file> @ <time>: <component>` prefixes trimmed; times
are in fs, so `@50000000` = 50 ns).

**`SIM=xrun` (`FLOW=std` or `FLOW=dtr`) gives the same outcome.** The same
`REPOPULATE` / `APPEND`, `REAPPLY`, `UVM_CMDLINE_PROC` and `CL_EXPECT` lines
appear, with the same values and topologies, and every check passes. In
`delayed_launch` only the three restore settings are applied, as on VCS.
The differences are cosmetic:

| | VCS | Xcelium |
|---|---|---|
| Time unit in the log | fs: `@50000000` = 50 ns | ps: `@50000` = 50 ns |
| Restore marker | `<50001000> SIM_IMAGE: simulation restored` | `<50001> SIM_IMAGE: simulation restored` |
| Save marker (`delayed_launch`) | `saving checkpoint ckpt_vcs/dl_ckpt_cl.chk` | `saving checkpoint dl_ckpt_cl` |
| `[PHASE]` lines | phase name left-aligned | phase name right-aligned |

Both simulators end every restore with `UVM_WARNING : 0`. A
`[MULTVERB] Multiple (2) +UVM_VERBOSITY arguments` warning on Xcelium means
the library in use predates the global-verbosity fix described in
[doc/cmdline_strategy.md](doc/cmdline_strategy.md#verbosity-on-save-and-restore).

**`FLOW=std` and `FLOW=dtl` produce the same restore log.** In all three
folders the DTL log has exactly one extra line, the dynamic package load
right after the restore:

```
<50001000> SIM_IMAGE: simulation restored
<50001000> SIM_IMAGE: $dtl_load (+dtl_add_pkg=DTL_main_tb_pkg:main_tb_pkg)
```

Every restore, on both simulators, ends with `UVM_ERROR : 0`, `UVM_FATAL : 0`
and `[CL_EXPECT] <n> expectation(s) checked, 0 failed` (4 in `delayed_launch`
and `pre_domain`, 6 in `post_domain`).

With `SIM=xrun FLOW=dtr` the restore log carries one marker line in the same
place instead (`+dtr_pkg`; xrun links the package before the restart):

```
<50001> SIM_IMAGE: simulation restored
<50001> SIM_IMAGE: DTR package main_tb_pkg linked with the restored snapshot
```

> [!IMPORTANT]
> **With DTL (VCS) or DTR (Xcelium), one checkpoint serves any number of testbench versions.**
>
> The checkpoint holds only the static image. The dynamic package
> (`test_pkg`, `main_tb_pkg` or `post_tb_pkg`) is loaded fresh on every
> restore. You can edit it (add or remove agents, scoreboards and
> coverage, change the topology of the same test), recompile **only that
> package**, and restore the **same snapshot** again. No new save, no
> rerun of the boot or the main test up to the checkpoint.
>
> ```bash
> make compile save restore FLOW=dtl        # once: save; restore with topology v1
> make compile_pkg FLOW=dtl TOPO=v2         # seconds: rebuilds just the dynamic package
> make restore FLOW=dtl                     # same checkpoint, same test, topology v2
>
> make compile save restore SIM=xrun FLOW=dtr   # Xcelium: same, restore compiles the package
> make restore SIM=xrun FLOW=dtr TOPO=v2        # same checkpoint, same test, topology v2
> ```
>
> `TOPO=v2` is a ready-made example of such a change: the same test builds
> one more component (`soc_sb` in `pre_domain`, `pcie_cov` in
> `post_domain`). Any edit of the package works the same way.
>
> With `FLOW=std`, the testbench code is frozen inside the checkpoint, so any
> change to it needs a recompile and a new save. The only rule with DTL / DTR
> is that the static part (`static.f`: `tb_top`, the DUT, and the packages
> already alive at the checkpoint) must not change. If it does, rerun
> `make compile save FLOW=dtl` (or `SIM=xrun FLOW=dtr`).

### delayed_launch: the whole UVM test is built after the restore

Save (`save_cl`, 131 ns): the boot is done in plain SystemVerilog and no UVM
topology exists. The save command line carries **stale** settings
(`+uvm_set_type_override=dl_driver,dl_driver_slow`, `n_items` 2, profile
`stale`):

```
[tb_top] @131000000 boot done: 16 firmware words loaded
[SAVEPT] checkpoint A (boot done, no UVM topology): requesting a sim image save @131000000
<131000000> SIM_IMAGE: saving checkpoint ckpt_vcs/dl_ckpt_cl.chk
```

Restore (`restore_cl`): the command line is **repopulated** (there is no
`uvm_test_top` yet), so the stale settings are flushed. `run_test()` launches
only now, and UVM applies the restore command line as if it were time 0:

```
[NV_SOCV_CMDLINE_PROCESSOR/REPOPULATE] Command line repopulated
[NV_SOCV_DELAYED_TEST_LUNCH] Test launch event triggered
[RNTST] Running test dl_test_b...
[INSTOVR] Applying instance override from the command line: +uvm_set_inst_override=dl_checker,dl_checker_strict,uvm_test_top.env.chk
[UVM_CMDLINE_PROC] Applying type override from the command line: +uvm_set_type_override=dl_driver,dl_driver_fast
[UVM_CMDLINE_PROC] Applying config setting from the command line: +uvm_set_config_int=uvm_test_top.env.drv,n_items,12
[UVM_CMDLINE_PROC] Applying config setting from the command line: +uvm_set_config_string=uvm_test_top.env,profile,stress
[TEST] dl_test_b built @131000000 (restored run), dl_mode=1
[DRV] dl_driver_fast built @131000000, n_items=12 gap=0

uvm_test_top  dl_test_b
  env         dl_env
    chk       dl_checker_strict
    drv       dl_driver_fast

[CL_EXPECT] DRV_TYPE = dl_driver_fast as expected (factory type override)
[CL_EXPECT] CHK_TYPE = dl_checker_strict as expected (factory instance override)
[CL_EXPECT] N_ITEMS = 12 as expected (config_int vs env default)
[CL_EXPECT] PROFILE = stress as expected (config_string)
[DRV] 12 words driven, done @157000000
[CHK] dl_checker_strict: 12 words on the pins, as driven
[CL_EXPECT] 4 expectation(s) checked, 0 failed
```

### delayed_launch: feature checkpoint C, merge and reapply

> [!NOTE]
> Expected outcome, from the code; these targets have not been run yet, so
> times are left out (`@<t>`).

```bash
make compile save_c restore_c restore_c_keep      # SIM=vcs or xrun, FLOW=std
```

`save_c` is a run from scratch with delayed UVM invocation: the boot runs in
SV, no checkpoint A is taken (`+DL_FEATURE_SAVE`), and the gate launches the
feature test `dl_test_f` with a **stale** scenario 1. The test runs IP init
and the pipeline fill, then saves C and stops:

```
[NV_SOCV_CMDLINE_PROCESSOR/REPOPULATE] Command line repopulated
[RNTST] Running test dl_test_f...
[FEAT] IP init and pipeline fill done @<t>: <n_items + 4> word(s)
[SAVEPT] checkpoint C (feature: IP init and pipeline fill done): requesting a sim image save @<t>
```

`restore_c` restores C. `uvm_test_top` exists, so the restore arguments are
**merged** and reapplied, and the common sequence created after C picks the
new scenario (3) and the `dl_scenario_seq_long` override:

```
[SAVEPT] checkpoint C (feature: IP init and pipeline fill done) passed @<t> (restored run)
[NV_SOCV_CMDLINE_PROCESSOR/APPEND] Command-line args merged
[NV_SOCV_CMDLINE_PROCESSOR/REAPPLY] Applying type override: +uvm_set_type_override=dl_scenario_seq,dl_scenario_seq_long
[NV_SOCV_CMDLINE_PROCESSOR/REAPPLY] Applying config int: +uvm_set_config_int=uvm_test_top.env,scenario,1
[NV_SOCV_CMDLINE_PROCESSOR/REAPPLY] Applying config int: +uvm_set_config_int=uvm_test_top.env,scenario,3
[NV_SOCV_CMDLINE_PROCESSOR/REAPPLY] UVM command-line settings reapplied
[SCN] dl_scenario_seq_long: scenario 3, 12 word(s) @<t>
[CL_EXPECT] SCENARIO = 3 as expected (config_int read after C)
[CL_EXPECT] SEQ_TYPE = dl_scenario_seq_long as expected (factory override, object created after C)
[CL_EXPECT] 2 expectation(s) checked, 0 failed
```

The merge keeps the stale `scenario,1` from the run that saved C and adds the
new one after it, so the new one wins. `restore_c_keep` passes no settings:
the same checkpoint then runs the scenario of the run that saved it:

```
[SCN] dl_scenario_seq: scenario 1, 2 word(s) @<t>
[CL_EXPECT] SCENARIO = 1 as expected (config_int read after C)
[CL_EXPECT] SEQ_TYPE = dl_scenario_seq as expected (factory override, object created after C)
[CL_EXPECT] 2 expectation(s) checked, 0 failed
```

The merge also reports a `[NV_SOCV_CMDLINE_PROCESSOR/OVERRIDE]` line for
each plusarg given a different value by the restore.

### pre_domain: the boot tree is saved, the main test is built after the restore

Save (50 ns): `uvm_pre_top` (the boot test in the `pre_dom` domain) is built
at time 0 and is in the middle of its `main` phase. `uvm_test_top` does not
exist yet.

```
[NV_SOCV_CMDLINE_PROCESSOR/EARLY_BUILD] Applying command-line factory/config settings before the pre-domain build
[PRE] pre test built @0
[SAVEPT] checkpoint A (boot done, main test not built): requesting a sim image save @50000000
```

Restore: the gate releases the main test. The library repopulates the
command line from the restore invocation and reapplies the UVM settings, then
the same test, `soc_test_a`, is built at 50 ns with them:

```
[PREDOM/GATE] Main test released: boot done after 40 ns, restored run
[NV_SOCV_CMDLINE_PROCESSOR/LATE_BUILD] Reprocessing command line before the main-test build at 50001000
[NV_SOCV_CMDLINE_PROCESSOR/REPOPULATE] Command line repopulated
[NV_SOCV_CMDLINE_PROCESSOR/REAPPLY] Applying instance override: +uvm_set_inst_override=ddr_agent,ddr_agent_lp,uvm_test_top.env.ddr_agt
[NV_SOCV_CMDLINE_PROCESSOR/REAPPLY] Applying type override: +uvm_set_type_override=cpu_agent,cpu_agent_fast
[NV_SOCV_CMDLINE_PROCESSOR/REAPPLY] Applying config int: +uvm_set_config_int=uvm_test_top.env.cpu_agt*,main_delay,250
[NV_SOCV_CMDLINE_PROCESSOR/REAPPLY] Applying config string: +uvm_set_config_string=uvm_test_top.env,profile,perf
[NV_SOCV_CMDLINE_PROCESSOR/REAPPLY] UVM command-line settings reapplied
[PREDOM] Running test soc_test_a
[MAIN] soc_test_a built @50000000 (restored run), seed=42, topology v1
```

The topology shows both trees: the boot tree restored from the checkpoint,
and the main tree built after the restore with the overridden types. The
boot tree continues from where it was saved: its `main` phase ends at 70 ns,
while the main test runs its own phases from 50 ns.

```
uvm_pre_top      boot_pre_test      <- from the checkpoint
  env            boot_env
    clk_rst_agt  phase_logger
    fw_load_agt  fw_load_agent
    hb           heartbeat
uvm_test_top     soc_test_a         <- built after the restore
  env            soc_env
    cpu_agt[0]   cpu_agent_fast
    cpu_agt[1]   cpu_agent_fast
    ddr_agt      ddr_agent_lp
    hb           heartbeat          (TOPO=v2: + soc_sb  soc_scoreboard)

[CL_EXPECT] CPU_TYPE = cpu_agent_fast as expected (main tree, type override)
[CL_EXPECT] DDR_TYPE = ddr_agent_lp as expected (main tree, instance override)
[CL_EXPECT] CPU_MAIN = 250 as expected (main tree, config_int vs env default)
[CL_EXPECT] PROFILE = perf as expected (main tree, config_string)
[CL_EXPECT] 4 expectation(s) checked, 0 failed
```

`CPU_MAIN` checks that the command-line `main_delay` wins over the env's own
`config_db` set (100) for a tree built at non-zero time.

With `make compile_pkg FLOW=dtl TOPO=v2` and the same checkpoint, the same
test is built with the scoreboard added:

```
[MAIN] soc_test_a built @50000000 (restored run), seed=42, topology v2
    soc_sb       soc_scoreboard     <- new in the topology
[SB] soc_sb run_phase @50000000
```

### post_domain: the main test is saved, the post test is built after the restore

Save (40 ns): `uvm_test_top` (the main test) is running its `main` phase. The
post domain is installed, but its tree is not built.

```
[PSDOM] Post domain 'post_dom' installed (post test pcie_post_test); waits for release_post()
[SAVEPT] checkpoint B (feature: post domain not built): requesting a sim image save @40000000
```

Restore: the main tree already exists, so the restore arguments are
**merged** into the command line and reapplied. They reach both trees: the
main tree restored from the checkpoint re-reads `post_window` and creates an
object with the `soc_txn_ext` override, and the same post test,
`pcie_post_test`, is built during the main `main_phase`:

```
[PSDOM/GATE] Post domain released: main main_phase + 30 ns, restored run
[NV_SOCV_CMDLINE_PROCESSOR/LATE_BUILD] Reprocessing command line before the post-domain build at 40001000
[NV_SOCV_CMDLINE_PROCESSOR/APPEND] Command-line args merged
[NV_SOCV_CMDLINE_PROCESSOR/REAPPLY] Applying instance override: +uvm_set_inst_override=pcie_scoreboard,pcie_scoreboard_strict,uvm_post_top.env.pcie_sb
[NV_SOCV_CMDLINE_PROCESSOR/REAPPLY] Applying type override: +uvm_set_type_override=pcie_driver,pcie_driver_fast
[NV_SOCV_CMDLINE_PROCESSOR/REAPPLY] Applying type override: +uvm_set_type_override=soc_txn,soc_txn_ext
[NV_SOCV_CMDLINE_PROCESSOR/REAPPLY] Applying config int: +uvm_set_config_int=uvm_post_top.env.pcie_agt,main_delay,77
[NV_SOCV_CMDLINE_PROCESSOR/REAPPLY] Applying config int: +uvm_set_config_int=uvm_test_top.env,post_window,40
[NV_SOCV_CMDLINE_PROCESSOR/REAPPLY] Applying config string: +uvm_set_config_string=uvm_post_top.env,profile,gen5
[NV_SOCV_CMDLINE_PROCESSOR/REAPPLY] UVM command-line settings reapplied
[PSDOM] Running post test pcie_post_test
[ENV] post domain started @40000000
[CL_EXPECT] POST_WINDOW = 40 as expected (main tree, config re-read after the release)
[CL_EXPECT] TXN_TYPE = soc_txn_ext as expected (main tree, object created after the release)
[POST] pcie_post_test built @40000000 (restored run), topology v1
[CFG] uvm_post_top.env.pcie_agt (pcie_agent) built @40000000: main_delay=77 profile=default
[PSDOM/ILLCRT] 25 post-tree component(s) created after the main build; ILLCRT suppressed for them
```

The post topology has the overridden driver and scoreboard; `main_delay` 77
wins over the env's own `POST_MAIN` set (50):

```
uvm_post_top               pcie_post_test
  env                      pcie_env
    hb                     heartbeat
    pcie_agt               pcie_agent
    pcie_bus               pcie_bus_agent
      drv                  pcie_driver_fast
      sqr                  uvm_sequencer
    pcie_sb                pcie_scoreboard_strict
                           (TOPO=v2: + pcie_cov  pcie_coverage)

[CL_EXPECT] DRV_TYPE = pcie_driver_fast as expected (post tree, type override)
[CL_EXPECT] SB_TYPE = pcie_scoreboard_strict as expected (post tree, instance override)
[CL_EXPECT] PCIE_MAIN = 77 as expected (post tree, config_int vs env default)
[CL_EXPECT] PROFILE = gen5 as expected (post tree, config_string)
```

The post tree runs the runtime phases that the main test has already finished
back to back, then moves in step with it. Both `main` phases end together at
127 ns, and the post checks run in the same simulation:

```
[PSDOM/SYNC] Post runtime phases synced with the uvm domain (main is in 'main'). ...
[PHASE] main ENDED                   @127000000  domain=post_dom
[PHASE] main ENDED                   @127000000  domain=uvm
[PCIE_SB] pcie_scoreboard_strict: 3 responses, as expected
[MAIN] post domain: released at 40001000000000, skipped=0, synced=1, jumps mirrored=0
[CL_EXPECT] 6 expectation(s) checked, 0 failed
```

The report catcher shows `caught UVM_FATAL reports : 25`, the same number as
the `PSDOM/ILLCRT` line. These are the ILLCRT (component created after build)
fatals for the post-tree components, caught on purpose; the final summary has
`UVM_FATAL : 0`.

With `make compile_pkg FLOW=dtl TOPO=v2` and the same checkpoint, the same
post test is built with the coverage collector added:

```
[POST] pcie_post_test built @40000000 (restored run), topology v2
    pcie_cov               pcie_coverage           <- new in the topology
[PCIE_COV] data_cg ...%
```

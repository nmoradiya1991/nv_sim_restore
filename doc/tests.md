# Tests

Each test folder has a `Makefile`, `files.f` (every file, for the normal flow),
`static.f` (the static image, for the DTL and DTR flows), `tb_top.sv` and the test
packages:

| Folder | Static (saved image) | Dynamic (DTL / DTR, loaded after the restore) |
|:--|:--|:--|
| `delayed_launch` | `dl_if.sv`, `tb_top.sv` | `test_pkg.sv` (all tests) |
| `pre_domain` | `pre_tb_pkg.sv` (boot pre test), `tb_top.sv` | `main_tb_pkg.sv` (main test `soc_test_a`; `TOPO=v2` adds `env.soc_sb`) |
| `post_domain` | `main_tb_pkg.sv` (main test), `tb_top.sv` | `post_tb_pkg.sv` (post test `pcie_post_test`; `TOPO=v2` adds `env.pcie_cov`) |


## Targets

`make help` in a folder prints its targets. The command-line reprocessing
targets (`run_cl*`, `save_cl`, `restore_cl*`) are listed in
[Command-line targets](#command-line-targets) below.

<details open>
<summary><b>tests/delayed_launch</b> — Approach A</summary>

| Target | What it shows |
|:--|:--|
| `run_classic` | no gate: `dl_test_a` built at time 0, boot in parallel |
| `run_delayed` | gate: boot in SV, `dl_test_a` built at boot done |
| `run_delayed_b` | same with `+UVM_TESTNAME=dl_test_b` (adds `env.chk`) |
| `save` | ◆ A: boot done, no UVM tree, `$finish` |
| `restore` | `TEST=dl_test_b DL_MODE=7 N_ITEMS=8`: new test, new plusarg, `+uvm_set_config_int` |
| `restore_a` | restore with `dl_test_a` |

</details>

<details open>
<summary><b>tests/pre_domain</b> — Approach B, pre domain</summary>

| Target | What it shows |
|:--|:--|
| `run_default` | boot 40 ns, then `soc_test_a` |
| `run_pre_long` | `fw_load_agt` main 300 ns: the main `main_phase` waits (synced) |
| `run_jump_back` | main jumps main → reset; pre waits at the start of `post_main` |
| `run_jump_fwd` | main jumps main → shutdown; pre runs the skipped phases alone |
| `run_gate_timeout` | no release: `PREDOM/GATE` fatal at 500 ns |
| `save` | ◆ A: boot done, gate closed, `$finish` |
| `restore` | same test, `MAIN_SEED=42`, plus checked command-line overrides (`CL=0`: off) |

</details>

<details open>
<summary><b>tests/post_domain</b> — Approach B, post domain</summary>

| Target | What it shows |
|:--|:--|
| `run_default` | release 30 ns into the main `main_phase` |
| `run_release_reset` | release in reset: less catch-up, then lockstep |
| `run_release_late` | release 90 ns into main: main waits for post reset … main |
| `run_post_long` | post main 300 ns: main `main_phase` waits |
| `run_tb_release` | released from `tb_top` (module code) at 50 ns |
| `run_norelease` | never released: post domain skipped |
| `run_gate_timeout` | never released + `+POST_GATE_TIMEOUT=60`: fatal |
| `run_jump_main_back` / `run_jump_main_fwd` | main jump, mirrored on post |
| `run_jump_post_back` | post jump, mirrored on main |
| `run_jump_nomirror` | `+PSDOM_NO_JUMP_MIRROR` |
| `save` | ◆ B: before `release_post()`, `$finish` |
| `restore` | same post test, `POST_MAIN=50`, plus checked command-line overrides (`CL=0`: off) |

</details>

## Command-line targets

These targets change factory overrides and config on the command line for a
tree built at non-zero time. The **save run** gets *stale* settings and the
**restore** gets *new* ones; `restore_cl_drop` and `restore_cl_keep` give the
restore none. Each target passes the expected results as `+EXP_<KEY>=<value>`,
and the test checks them (`tests_common_pkg::cl_expect`):

```text
UVM_INFO  ... [CL_EXPECT] DRV_TYPE = pcie_driver_fast as expected (post tree, type override) @...
UVM_ERROR ... [CL_EXPECT] PCIE_MAIN = 20, expected 77 (post tree, config_int vs env default) @...
UVM_INFO  ... [CL_EXPECT] 6 expectation(s) checked, 1 failed
```

How the library makes this work is in
[cmdline_reprocessing.md](cmdline_reprocessing.md). Why the VCS and Xcelium
results differ for `restore_cl_drop` is in
[cmdline_strategy.md](cmdline_strategy.md#what-is-seen-at-each-point-vcs-and-xcelium).

| Folder | Target | Command-line settings | Expected |
|:--|:--|:--|:--|
| `delayed_launch` | `run_cl` | `+UVM_TESTNAME=dl_test_b`, type `dl_driver→dl_driver_fast`, inst `uvm_test_top.env.chk→dl_checker_strict`, `env.drv n_items=12` (env default 4), `env profile=stress` | all 4 applied |
| | `save_cl` | saved at the gate; stale: type `dl_driver→dl_driver_slow`, `n_items=2`, `profile=stale` | — |
| | `restore_cl` | the `run_cl` settings | all 4 applied, stale ones gone (repopulate) |
| | `restore_cl_drop` | only `+UVM_TESTNAME=dl_test_b` | VCS: `dl_driver`, `dl_checker`, 4, `default`; Xcelium: `dl_driver_slow`, `dl_checker`, 2, `stale` |
| `pre_domain` | `run_cl_pre` | type `fw_load_agent→fw_load_agent_fast`, `uvm_pre_top.env.fw_load_agt main_delay=90` (no save) | fast, 90 |
| | `run_cl_main` | type `cpu_agent→cpu_agent_fast`, inst `uvm_test_top.env.ddr_agt→ddr_agent_lp`, `cpu_agt main_delay=250` (env sets 100), `profile=perf` | all 4 applied |
| | `save_cl` | saved before the main build; stale: `cpu_agent→cpu_agent_slow`, `main_delay=5`, `profile=stale` | — |
| | `restore_cl` | the `run_cl_main` settings | all 4 applied, stale ones gone (repopulate) |
| | `restore_cl_drop` | none | VCS: `cpu_agent`, `ddr_agent`, 100, `default`; Xcelium: `cpu_agent_slow`, `ddr_agent`, 5, `stale` |
| `post_domain` | `run_cl` | type `pcie_driver→pcie_driver_fast`, inst `uvm_post_top.env.pcie_sb→pcie_scoreboard_strict`, `pcie_agt main_delay=77` (pcie env sets 20), `profile=gen5`; main tree: `uvm_test_top.env post_window=40` and type `soc_txn→soc_txn_ext`, both used by the main env after the release | all 6 applied |
| | `save_cl` | save point B (before the release); stale: `pcie_driver→pcie_driver_slow`, post `profile=stale`, `post_window=1` | — |
| | `restore_cl` | the `run_cl` settings | all 6 applied; each new setting wins over the stale one (merge) |
| | `restore_cl_keep` | none | stale ones persist: `pcie_driver_slow`, `pcie_scoreboard`, 20, `stale`, `post_window=1`, `soc_txn` |

`pre_domain run_cl_pre` checks the early-build fix and `PCIE_MAIN` /
`FW_MAIN` check the config-precedence fix, both described in
[cmdline_reprocessing.md](cmdline_reprocessing.md#two-related-build-fixes).

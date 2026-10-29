# Tests

Each test folder has a `Makefile`, `files.f` (every file, for the normal flow),
`static.f` (the static image, for the DTL flow), `tb_top.sv` and the test
packages:

| Folder | Static (saved image) | Dynamic (DTL, loaded after the restore) |
|:--|:--|:--|
| `delayed_launch` | `dl_if.sv`, `tb_top.sv` | `test_pkg.sv` (all tests) |
| `pre_domain` | `pre_tb_pkg.sv` (boot pre test), `tb_top.sv` | `main_tb_pkg.sv` (main tests) |
| `post_domain` | `main_tb_pkg.sv` (main test), `tb_top.sv` | `post_tb_pkg.sv` (post tests) |


## Targets

`make help` in a folder prints its targets. The command-line reprocessing
targets (`run_cl*`, `save_cl`, `restore_cl*`) are described in
[cmdline_reprocessing.md](cmdline_reprocessing.md#worked-cases--factory-overrides-and-config-at-non-zero-time).

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
| `run_default` | boot 40 ns, then `soc_test_a` (install default) |
| `run_cmdline` | main test from `+UVM_TESTNAME=soc_test_b` |
| `run_pre_long` | `fw_load_agt` main 300 ns: the main `main_phase` waits (synced) |
| `run_jump_back` | main jumps main → reset; pre waits at the start of `post_main` |
| `run_jump_fwd` | main jumps main → shutdown; pre runs the skipped phases alone |
| `run_gate_timeout` | no release: `PREDOM/GATE` fatal at 500 ns |
| `save` | ◆ A: boot done, gate closed, `$finish` |
| `restore` | `MAIN_TEST=soc_test_b MAIN_SEED=42` |
| `restore_a` | restore with `soc_test_a` |

</details>

<details open>
<summary><b>tests/post_domain</b> — Approach B, post domain</summary>

| Target | What it shows |
|:--|:--|
| `run_default` | release 30 ns into the main `main_phase` |
| `run_release_reset` | release in reset: less catch-up, then lockstep |
| `run_release_late` | release 90 ns into main: main waits for post reset … main |
| `run_post_long` | post main 300 ns: main `main_phase` waits |
| `run_post_b` | `+POST_TEST=pcie_post_test_b` (adds `pcie_cov`) |
| `run_tb_release` | released from `tb_top` (module code) at 50 ns |
| `run_norelease` | never released: post domain skipped |
| `run_gate_timeout` | never released + `+POST_GATE_TIMEOUT=60`: fatal |
| `run_jump_main_back` / `run_jump_main_fwd` | main jump, mirrored on post |
| `run_jump_post_back` | post jump, mirrored on main |
| `run_jump_nomirror` | `+PSDOM_NO_JUMP_MIRROR` |
| `save` | ◆ B: before `release_post()`, `$finish` |
| `restore` | `POST_TEST=pcie_post_test_b POST_MAIN=50` |
| `restore_a` | restore with `pcie_post_test` |

</details>

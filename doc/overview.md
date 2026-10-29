# Overview

Standard UVM has **one topology, created at time 0**: one `uvm_test_top`, built
in the common domain at time 0, port bindings resolved once at
`end_of_elaboration`, the command line parsed once. A checkpoint taken after
boot therefore freezes the *test* as well as the design, and every restore
replays the test that was chosen before the save.

This package removes that limit. The UVM tree is created **at non-zero time,
in stages**, and each stage reprocesses the command line first:

| Stage | What is built | When | API |
|:--|:--|:--|:--|
| **Approach A** — delayed launch | the whole test (`uvm_test_top`) | after boot / restore, `run_test()` gated | `nv_socv_delayed_test_launch` |
| **Approach B** — pre domain | common boot tree `uvm_pre_top` | time 0, in its own domain `pre_dom` | `install_pre_domain()` · `pd_release_main()` |
| | main test `uvm_test_top` | at `release_main()` | |
| **Approach B** — post domain | post tree `uvm_post_top` | at `release_post()`, during the main test | `install_post_domain()` · `pd_release_post()` |
| All of the above | — | right before each late build | `nv_socv_cmdline_processor` |

Benefits:

- **One save, many restores** — save once after the long boot, restore into
  any test with a new command line (`+UVM_TESTNAME`, `+POST_TEST`,
  `+uvm_set_*`, test plusargs).
- **Simulation performance** — components that are not built yet have no
  threads, no sampling, no coverage and no memory.
- **Phased adoption** — existing tests keep working; the post domain lets new
  content join a running test without touching the main tree.

## Package contents

| File | Contents |
|:--|:--|
| [`src/nv_socv_sim_restore_pkg.sv`](../src/nv_socv_sim_restore_pkg.sv) | `package nv_socv_sim_restore_pkg` (`timeunit 1fs`), includes everything below |
| [`src/nv_socv_cmdline_processor.sv`](../src/nv_socv_cmdline_processor.sv) | command-line refresh / merge / reapply for late builds and restores |
| [`src/nv_socv_delayed_test_launch.sv`](../src/nv_socv_delayed_test_launch.sv) | launch gate for `run_test()` and `nv_socv_config_db#(T)` |
| [`src/nv_socv_pre_domain.sv`](../src/nv_socv_pre_domain.sv) | `pd_*` phases, `pre_domain_controller`, `install_pre_domain()` |
| [`src/nv_socv_post_domain.sv`](../src/nv_socv_post_domain.sv) | `ps_*` phases, `post_domain_controller`, `install_post_domain()` |
| [`src/nv_socv_report_macros.sv`](../src/nv_socv_report_macros.sv) | `` `nv_uvm_info/warning/fatal`` usable before `run_test()` |
| [`tests/`](../tests/) | self-contained VCS / Xcelium tests for every flow |


## Topology over time

```
 sim time ──────────────────────────────────────────────────────────────────────────────▶
                                   ◆ A                          ◆ B
            0                      │ release_main()             │ release_post()
            │                      │                            │
 pre_dom    │ uvm_pre_top          │                            │
 (boot)     │  └ boot_env          │   pd_run keeps going (monitors, clocks, …) ───────────▶
            │     ├ clk_rst_agt    │                            │
            │     └ fw_load_agt    │                            │
            │                      │                            │
 uvm        │                      │ uvm_test_top               │
 (main)     │                      │  └ soc_env                 │   ─────────────────────▶
            │                      │     ├ cpu_agt  ├ ddr_agt   │
            │                      │     └ soc_sb               │
            │                      │                            │
 post_dom   │                      │                            │ uvm_post_top
 (post)     │                      │                            │  └ pcie_env ──────────▶
            │                      │                            │     ├ pcie_agt ├ pcie_sb
            │                      │                            │     └ pcie_cov
```

- **Save point A** — boot done, main test not built (`pd_gate`, or the
  Approach A launch gate). Restore into *any* main test.
- **Save point B** — main test running, post tree not built (before
  `release_post()`). Restore into *any* post test.
- Simulation time is **not reset** by a restore: `$time` continues from the
  save point, and every late build happens at that non-zero time.


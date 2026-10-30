# UVM command-line reprocessing: strategy

How `nv_socv_cmdline_processor` makes UVM command-line options work when the
UVM test is built late, or after a restore. The API reference and the worked
test cases are in [cmdline_reprocessing.md](cmdline_reprocessing.md).

## The problem: UVM reads the command line once, at time 0

The `uvm_cmdline_processor` singleton reads the simulator command line once,
when UVM is first used at time 0, into its argument tables. This page is
about the UVM options in them: `+UVM_<OPTION>=<value>` (such as
`+UVM_TESTNAME`, `+UVM_VERBOSITY`, `+UVM_TIMEOUT`) and the `+uvm_set_*`
settings. Everything UVM does with them later (`+UVM_TESTNAME` in
`run_test()`, factory overrides and `config_db` settings in
`uvm_root::build_phase()`, report settings for each new component) reads
these tables, never the simulator again.

```mermaid
flowchart LR
    CL["simulator command line"] -- "read once, time 0" --> T["uvm_cmdline_processor tables<br/>+UVM_* · +uvm_set_*"]
    T --> A["run_test(): +UVM_TESTNAME"]
    T --> B["uvm_root::build_phase():<br/>+uvm_set_type/inst_override<br/>+uvm_set_config_int/string<br/>+UVM_TIMEOUT …"]
    T --> C["each new component:<br/>+uvm_set_verbosity/action/severity"]
```

That gives two limitations:

1. **Delayed UVM invocation.** The UVM test is built at a non-zero time, for
   example after a boot done in plain SystemVerilog. The options it needs
   are applied from what the tables held at time 0, and the tables were
   saved with the boot.
2. **Restore with a new command line.** A checkpoint restores the tables as
   they were at the save. The options the user gives to the restore never
   reach them, so the code after the restore runs with the save run's
   options.

```mermaid
sequenceDiagram
    participant Save as save run
    participant Ckpt as checkpoint
    participant Rst as restore run
    participant UVM as UVM tables
    Save->>UVM: time 0: read save command line
    Save->>Ckpt: $save (tables included)
    Ckpt->>Rst: restart with a NEW command line
    Note over Rst,UVM: tables still hold the SAVE command line
    Rst->>UVM: run_test() / build / overrides read the old tables
```

## The solution: reprocess the tables at T != 0

Right before the part of the testbench built after the restore (or after
the delay), the library reads the current command line again through
`uvm_dpi_get_next_arg()`, rewrites the tables, and reapplies the UVM
settings (`reapply_cmdline_settings()`). Components created after that
point also get the report settings
(`reapply_report_settings_for_late_build()`).

| Flow | Reprocessing point |
|:--|:--|
| Approach A, `delayed_launch` | the test launch after the boot (`trigger_test_launch()`) |
| Approach B, `pre_domain` | `release_main()`: right before the main test is built |
| Approach B, `post_domain` | `release_post()`: right before the post test is built |

It happens once per run, never at time 0 (at time 0 the tables are already
current). Between the restore and the reprocessing point, the tables still
hold the save run's values.

The library picks one of two strategies, depending on whether the UVM
topology already exists:

```mermaid
flowchart TD
    S["reprocessing point, T != 0"] --> P["read the current command line (DPI)<br/>collapse repeated settings<br/>(+NV_SOCV_CMDLINE_PRECEDENCE)"]
    P --> Q{"uvm_test_top exists?"}
    Q -- no --> R["Strategy 1: REPOPULATE<br/>flush the tables, refill from the current command line"]
    Q -- yes --> M["Strategy 2: MERGE<br/>keep the tables; +UVM_OPTION replaced in place,<br/>+uvm_set_* appended at the tail"]
    R --> X["reapply_cmdline_settings()"]
    M --> X
    X --> B["late build: tree built with the new options"]
```

## Strategy 1: repopulate (no `uvm_test_top` yet)

Used when nothing of the UVM test exists yet: `delayed_launch` and
`pre_domain`. Nothing has been built from the save run's UVM options, so
they carry no meaning. The tables are flushed and refilled from the current
command line only.

```mermaid
flowchart LR
    subgraph before ["tables before (save run, time 0)"]
        b1["+UVM_VERBOSITY=UVM_MEDIUM"]
        b2["+uvm_set_type_override=dl_driver,dl_driver_slow"]
        b3["+uvm_set_config_int=uvm_test_top.env.drv,n_items,2"]
        b4["+uvm_set_config_string=uvm_test_top.env,profile,stale"]
    end
    subgraph after ["tables after repopulate (restore command line)"]
        a1["+UVM_VERBOSITY=UVM_MEDIUM"]
        a2["+UVM_TESTNAME=dl_test_b"]
        a3["+uvm_set_type_override=dl_driver,dl_driver_fast"]
        a4["+uvm_set_inst_override=dl_checker,dl_checker_strict,uvm_test_top.env.chk"]
        a5["+uvm_set_config_int=uvm_test_top.env.drv,n_items,12"]
        a6["+uvm_set_config_string=uvm_test_top.env,profile,stress"]
    end
    before -- "flush + refill" --> after
```

Example (`tests/delayed_launch`):

```bash
make save_cl      # save run:    +uvm_set_type_override=dl_driver,dl_driver_slow
                  #              +uvm_set_config_int=uvm_test_top.env.drv,n_items,2
                  #              +uvm_set_config_string=uvm_test_top.env,profile,stale
make restore_cl   # restore run: +UVM_TESTNAME=dl_test_b
                  #              +uvm_set_type_override=dl_driver,dl_driver_fast
                  #              +uvm_set_inst_override=dl_checker,dl_checker_strict,uvm_test_top.env.chk
                  #              +uvm_set_config_int=uvm_test_top.env.drv,n_items,12
                  #              +uvm_set_config_string=uvm_test_top.env,profile,stress
```

Result: `dl_test_b` is built after the restore with `dl_driver_fast`,
`dl_checker_strict`, `n_items` 12 and profile `stress`. `make
restore_cl_drop` restores the same checkpoint with no settings: on VCS the
test gets its defaults (`dl_driver`, `n_items` 4, profile `default`).

## Strategy 2: merge (`uvm_test_top` exists)

Used when a checkpoint is taken **after** the UVM topology was created. Its
options were applied to that topology at time 0, and its factory and
`config_db` state is part of the checkpoint, so the tables are kept and the
restore's options are merged into them:

| UVM option from the restore | Action in the tables |
|:--|:--|
| `+UVM_<OPTION>=<value>` (`+UVM_TESTNAME`, `+UVM_VERBOSITY`, `+UVM_TIMEOUT`, `+UVM_MAX_QUIT_COUNT`, …) | the entry with the same option **replaced in place** (reported as `NV_SOCV_CMDLINE_PROCESSOR/OVERRIDE`); appended at the tail if the save run did not have it |
| `+uvm_set_*` (type / inst override, config int / string, verbosity, action, severity, default sequence) | **appended at the tail**: these are independent settings; UVM applies them in table order, so for the same target the restore's, applied last, wins |

Typical flow, a feature checkpoint: boot, then the delayed UVM invocation
builds the topology, the test runs to an interesting point of a feature
(for example, right before a PCIe speed change), the checkpoint is taken
there, and each restore continues the feature with its own options.
`post_domain` is this case: the main test runs, the checkpoint is taken
before `release_post()`, and the post test is built after the restore.

```mermaid
sequenceDiagram
    participant TB as boot (SV)
    participant UVM as UVM topology
    participant CK as checkpoint
    participant R as restore run
    TB->>UVM: boot done: delayed UVM invocation (run_test)
    UVM->>UVM: topology built, test runs<br/>(options applied from the time-0 tables)
    UVM->>CK: feature checkpoint: before the PCIe speed change
    CK->>R: restore with new options
    R->>UVM: MERGE: tables kept, restore options merged
    UVM->>UVM: rest of the feature (speed change, post test)<br/>built / configured with the merged options
```

```mermaid
flowchart LR
    subgraph before ["tables before (save run; +UVM_TIMEOUT added for illustration)"]
        b1["+UVM_TIMEOUT=1000000"]
        b2["+uvm_set_type_override=pcie_driver,pcie_driver_slow"]
        b3["+uvm_set_config_int=uvm_test_top.env,post_window,1"]
    end
    subgraph after ["tables after merge"]
        a1["+UVM_TIMEOUT=2000000 (replaced in place)"]
        a2["+uvm_set_type_override=pcie_driver,pcie_driver_slow"]
        a3["+uvm_set_config_int=uvm_test_top.env,post_window,1"]
        a5["+uvm_set_type_override=pcie_driver,pcie_driver_fast (appended, applied last)"]
        a6["+uvm_set_config_int=uvm_test_top.env,post_window,40 (appended, applied last)"]
    end
    before -- "merge" --> after
```

Example (`tests/post_domain`):

```bash
make save_cl          # save point B, before release_post():
                      #   +uvm_set_type_override=pcie_driver,pcie_driver_slow
                      #   +uvm_set_config_string=uvm_post_top.env,profile,stale
                      #   +uvm_set_config_int=uvm_test_top.env,post_window,1
make restore_cl       # restore: +uvm_set_type_override=pcie_driver,pcie_driver_fast
                      #   +uvm_set_config_string=uvm_post_top.env,profile,gen5
                      #   +uvm_set_config_int=uvm_test_top.env,post_window,40 ...
make restore_cl_keep  # restore with no settings
```

Result: with `restore_cl` the post test gets `pcie_driver_fast` and
profile `gen5`, and the main env, which reads `post_window` again after the
release, gets 40. With `restore_cl_keep` the save run's settings stay in
effect (`pcie_driver_slow`, `stale`, `post_window` 1), since they are part
of the topology's state.

A `+UVM_<OPTION>` replaced in place (illustration with `+UVM_TIMEOUT`):

```text
save run tables : ... +UVM_TIMEOUT=1000000 ...
restore         : +UVM_TIMEOUT=2000000
after merge     : ... +UVM_TIMEOUT=2000000 ...      (same position)
OVERRIDE report : Command-line argument overridden: '+UVM_TIMEOUT=1000000' -> '+UVM_TIMEOUT=2000000'
```

## Repeated arguments: precedence

Before either strategy, the current command line is collapsed so that each
setting appears once. A setting is identified by what it targets, not by
its value:

| Argument | Same setting when equal |
|:--|:--|
| `+uvm_set_type_override=<req>,<ovr>` | `<req>` |
| `+uvm_set_inst_override=<req>,<ovr>,<path>` | `<req>`, `<path>` |
| `+uvm_set_config_int` / `_string=<path>,<field>,<val>` | `<path>`, `<field>` |
| `+uvm_set_default_sequence=<path>,<phase>,<seq>` | `<path>`, `<phase>` |
| `+uvm_set_verbosity=<comp>,<id>,<verb>,<phase>[,<time>]` | all fields but `<verb>` |
| `+uvm_set_action` / `_severity=<comp>,<id>,<sev>,...` | `<comp>`, `<id>`, `<sev>` |
| `+UVM_<OPTION>=<value>` | `+UVM_<OPTION>` |

`+NV_SOCV_CMDLINE_PRECEDENCE` chooses which occurrence is kept:

| Value | Kept | Note |
|:--|:--|:--|
| `first` (default) | the first occurrence | |
| `last` | the last occurrence, at its position | |

```text
command line : +uvm_set_type_override=dl_driver,dl_driver_fast
               +uvm_set_type_override=dl_driver,dl_driver_slow
first        : +uvm_set_type_override=dl_driver,dl_driver_fast
last         : +uvm_set_type_override=dl_driver,dl_driver_slow
```

Different targets are independent and all kept, for example
`+uvm_set_type_override=dl_driver,dl_driver_fast` and
`+uvm_set_type_override=soc_txn,soc_txn_ext`.

### Xcelium: the restored command line

After an Xcelium restart (`-process_save`, `FLOW=std` and `FLOW=dtr`
alike), the command line reported through the DPI is not only the restore's.
It is the restore's command line, then the save run's options that are not
on it, then the save run's whole command line again (followed by its
internal `xmsim` options). VCS reports only the restore's command line.

```mermaid
flowchart LR
    A["restore command line<br/>+uvm_set_type_override=dl_driver,dl_driver_fast<br/>+uvm_set_config_int=…,n_items,12"] --> B["save options not on the restore<br/>+uvm_set_type_override=dl_driver,dl_driver_slow<br/>+uvm_set_config_int=…,n_items,2"]
    B --> C["save run command line again<br/>+UVM_VERBOSITY=… +uvm_set_…slow …<br/>-amsdlibdir … -LOG_FD_NAME logs/save_….log …"]
```

With the default `first`, the restore's value wins for every setting it
gives, the same as on VCS. `last` makes the save run's value win.

Settings given **only** on the save run are still reported by Xcelium after
the restart, so on Xcelium they survive a repopulate (`restore_cl_drop` in
`delayed_launch` and `pre_domain` expects them on Xcelium, and the
defaults on VCS). To get the same result on both simulators, give a
checkpoint meant for many restores a minimal save command line: UVM cannot
unset a `+uvm_set_*` setting, only override its target.

## What is seen at each point, VCS and Xcelium

Values of UVM options (`+UVM_<OPTION>`, `+uvm_set_*`) as UVM sees them, with
the default `+NV_SOCV_CMDLINE_PRECEDENCE=first`:

| Point | VCS | Xcelium |
|:--|:--|:--|
| Save run, from time 0 | save run's values | save run's values |
| Checkpoint (`$save`) | the tables are saved with the save run's values | same |
| Restore, before the reprocessing point | **save run's** values (tables restored; the restore's options not seen yet) | same |
| Reported by the simulator after the restore | the restore's command line only | the restore's command line, then the save run's options (some twice) |
| After reprocessing: the restore gives the same option / target | **restore's** value | **restore's** value |
| After reprocessing: the restore does not give it, **repopulate** | **gone** (UVM default) | **save run's** value (still reported by Xcelium) |
| After reprocessing: the restore does not give it, **merge** | **save run's** value | **save run's** value |
| A value read or applied before the save (variable, `config_db::get()` done, component or object already created) | **old** value; the new one only if read again / created after the reprocessing point | same |

With `+NV_SOCV_CMDLINE_PRECEDENCE=last`, only one row changes: when the
restore gives the same option or target, Xcelium ends up with the **save
run's** value, because its copy is reported after the restore's. VCS still
gets the restore's value, since it reports each option only once.

## Summary

| | Repopulate | Merge |
|:--|:--|:--|
| When | no `uvm_test_top` yet | `uvm_test_top` exists |
| Examples | `delayed_launch`, `pre_domain` | `post_domain`, feature checkpoints |
| Save run's tables | flushed | kept |
| Restore's `+UVM_<OPTION>` | the only entry | replaces the same option in place |
| Restore's `+uvm_set_*` | the only entries | appended at the tail, applied last |
| Save-run setting the restore does not give | gone (VCS); still reported on Xcelium | stays |
| Repeated settings on the current command line | collapsed by `+NV_SOCV_CMDLINE_PRECEDENCE` (default `first`) | same |
| After the rewrite | `reapply_cmdline_settings()`, then report settings for components created later | same |

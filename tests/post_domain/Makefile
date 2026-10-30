# ============================================================================
# post_domain -- domain-based proposal: post test (pcie_post_test) built at
# release_post() during the main test, runtime phases synced with it.
#
#   make compile               [SIM=vcs|xrun] [TOPO=v1|v2]
#   make run_default           release 30 ns into the main main_phase
#   make run_release_reset     release in reset: less catch-up, then lockstep
#   make run_release_late      release 90 ns into main: main main_phase waits
#                              for the post reset .. main
#   make run_post_long         post main 300 ns: main main_phase waits
#   make run_tb_release        released from tb_top (module) at 50 ns
#   make run_norelease         never released: post domain skipped
#   make run_gate_timeout      never released + POST_GATE_TIMEOUT: fatal
#   make run_jump_main_back    main jumps main -> reset; mirrored on post
#   make run_jump_main_fwd     main jumps main -> shutdown; mirrored on post
#   make run_jump_post_back    post jumps main -> reset; mirrored on main
#   make run_jump_nomirror     as run_jump_main_back, +PSDOM_NO_JUMP_MIRROR
#   make save                  feature checkpoint B (before release_post), $finish
#   make restore               restore B: same post test, +POST_MAIN, plus
#                              the command-line overrides below, checked;
#                              pcie_agt main is then 77, the command line
#                              winning over the env's own POST_MAIN set
#                              (CL=0: +POST_MAIN only)
#
# Topology: TOPO=v2 builds env.pcie_cov in the same post test
# (+define+TOPO_V2 on post_tb_pkg). With FLOW=dtl (or dtr, SIM=xrun) the checkpoint is reused:
#   make compile save restore FLOW=dtl             topology v1
#   make compile_pkg restore FLOW=dtl TOPO=v2      same checkpoint, v2
#
# Command-line reprocessing (factory overrides / config, checked with +EXP_*;
# see "CL_EXPECT" in the log):
#   make run_cl                no save: post-tree and main-tree settings on
#                              the command line, post tree built at the
#                              release
#   make save_cl               checkpoint B with STALE settings: pcie_driver
#                              -> pcie_driver_slow, post profile "stale",
#                              main env post_window 1
#   make restore_cl            restore save_cl with NEW settings: the
#                              restore merges them after the stale ones:
#                              pcie_driver ->
#                              pcie_driver_fast (type), env.pcie_sb ->
#                              pcie_scoreboard_strict (instance), pcie_agt
#                              main 77 over the pcie env's own set, profile
#                              "gen5", main env post_window 40 (re-read after
#                              the release), soc_txn -> soc_txn_ext for an
#                              object the main env creates after the release
#   make restore_cl_keep       restore save_cl with no settings: the stale
#                              ones stay (merge: factory / config state of the
#                              save run is kept)
#   make clean
#
# FLOW=dtl (VCS Dynamic Test Load) or FLOW=dtr SIM=xrun (Xcelium Dynamic Test
# Reload): the saved image has the main test only;
# post_tb_pkg is loaded right after the restore and the post test is built
# from it at release_post().
#   static : main_tb_pkg.sv, tb_top.sv (static.f)  dynamic: post_tb_pkg.sv
#   restore_cl restores the `save` checkpoint; save_cl, restore_cl_keep and
#   the run_* targets are FLOW=std only (save_cl's stale overrides name
#   post_tb_pkg classes, which the save run does not have).
#
#   Overrides: POST_MAIN=50 CL=0 TOPO=v2 CKPT_NAME=post_ckpt_b
#              ARGS='+...' VERBOSITY=UVM_LOW
# ============================================================================

CKPT_NAME   ?= post_ckpt_b
SAVE_CKPT   := $(CKPT_NAME)
CL_CKPT     ?= post_ckpt_cl
EXTRA_CKPTS  = $(CL_CKPT)
DYN_PKG      = post_tb_pkg
POST_MAIN   ?= 50
CL          ?= 1

include ../common/common.mk

.DEFAULT_GOAL := help

# Stale settings given to the save run only.
CL_STALE = +uvm_set_type_override=pcie_driver,pcie_driver_slow \
           +uvm_set_config_string=uvm_post_top.env,profile,stale \
           +uvm_set_config_int=uvm_test_top.env,post_window,1
# Settings given to the restored (or plain) run, and what they must give.
CL_OVR   = +uvm_set_type_override=pcie_driver,pcie_driver_fast \
           +uvm_set_inst_override=pcie_scoreboard,pcie_scoreboard_strict,uvm_post_top.env.pcie_sb \
           +uvm_set_config_int=uvm_post_top.env.pcie_agt,main_delay,77 \
           +uvm_set_config_string=uvm_post_top.env,profile,gen5 \
           +uvm_set_config_int=uvm_test_top.env,post_window,40 \
           +uvm_set_type_override=soc_txn,soc_txn_ext
CL_EXP   = +EXP_DRV_TYPE=pcie_driver_fast +EXP_SB_TYPE=pcie_scoreboard_strict \
           +EXP_PCIE_MAIN=77 +EXP_PROFILE=gen5 +EXP_POST_WINDOW=40 \
           +EXP_TXN_TYPE=soc_txn_ext
CL_EXP_KEEP = +EXP_DRV_TYPE=pcie_driver_slow +EXP_SB_TYPE=pcie_scoreboard \
           +EXP_PCIE_MAIN=20 +EXP_PROFILE=stale +EXP_POST_WINDOW=1 \
           +EXP_TXN_TYPE=soc_txn
# CL=1 (default): restore also passes CL_OVR and checks it.
RESTORE_CL = $(if $(filter 1,$(CL)),$(CL_OVR) $(CL_EXP))

save_cl restore_cl_keep: CKPT_NAME = $(CL_CKPT)
restore_cl: CKPT_NAME = $(if $(DYN),$(SAVE_CKPT),$(CL_CKPT))

.PHONY: run_default run_release_reset run_release_late run_post_long \
        run_tb_release run_norelease run_gate_timeout run_jump_main_back \
        run_jump_main_fwd run_jump_post_back run_jump_nomirror \
        save restore run_cl save_cl restore_cl restore_cl_keep

run_default:
	$(call sim_run,run_default,)

run_release_reset:
	$(call sim_run,run_release_reset,+RELEASE_PHASE=reset +RELEASE_DELAY=5)

run_release_late:
	$(call sim_run,run_release_late,+RELEASE_DELAY=90)

run_post_long:
	$(call sim_run,run_post_long,+POST_MAIN=300)

run_tb_release:
	$(call sim_run,run_tb_release,+NO_RELEASE +RELEASE_FROM_TB=50)

run_norelease:
	$(call sim_run,run_norelease,+NO_RELEASE)

run_gate_timeout:
	$(call sim_run,run_gate_timeout,+NO_RELEASE +POST_GATE_TIMEOUT=60)

run_jump_main_back:
	$(call sim_run,run_jump_main_back,+MAIN_JUMP_TO=reset)

run_jump_main_fwd:
	$(call sim_run,run_jump_main_fwd,+MAIN_JUMP_TO=shutdown)

run_jump_post_back:
	$(call sim_run,run_jump_post_back,+POST_JUMP_TO=reset)

run_jump_nomirror:
	$(call sim_run,run_jump_nomirror,+MAIN_JUMP_TO=reset +PSDOM_NO_JUMP_MIRROR)

save:
	$(call sim_save,save,+SAVE_BEFORE_RELEASE)

restore:
	$(call sim_restore,restore,+POST_MAIN=$(POST_MAIN) $(RESTORE_CL))

run_cl:
	$(call sim_run,run_cl,$(CL_OVR) $(CL_EXP))

save_cl:
	$(call std_only,the stale overrides name post_tb_pkg classes)
	$(call sim_save,save_cl,+SAVE_BEFORE_RELEASE $(CL_STALE))

restore_cl:
	$(call sim_restore,restore_cl,$(CL_OVR) $(CL_EXP))

restore_cl_keep:
	$(call std_only,needs the save_cl checkpoint)
	$(call sim_restore,restore_cl_keep,$(CL_EXP_KEEP))

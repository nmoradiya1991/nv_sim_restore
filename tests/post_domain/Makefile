# ============================================================================
# post_domain -- Approach B: post test built at release_post() during the
# main test, runtime phases synced with it.
#
#   make compile               [SIM=vcs|xrun]
#   make run_default           release 30 ns into the main main_phase
#   make run_release_reset     release in reset: less catch-up, then lockstep
#   make run_release_late      release 90 ns into main: main main_phase waits
#                              for the post reset .. main
#   make run_post_long         post main 300 ns: main main_phase waits
#   make run_post_b            +POST_TEST=pcie_post_test_b (adds pcie_cov)
#   make run_tb_release        released from tb_top (module) at 50 ns
#   make run_norelease         never released: post domain skipped
#   make run_gate_timeout      never released + POST_GATE_TIMEOUT: fatal
#   make run_jump_main_back    main jumps main -> reset; mirrored on post
#   make run_jump_main_fwd     main jumps main -> shutdown; mirrored on post
#   make run_jump_post_back    post jumps main -> reset; mirrored on main
#   make run_jump_nomirror     as run_jump_main_back, +PSDOM_NO_JUMP_MIRROR
#   make save                  save point B (before release_post), $finish
#   make restore               restore B: +POST_TEST=$(POST_TEST),
#                              +POST_MAIN=$(POST_MAIN)
#   make restore_a             restore B with pcie_post_test
#
# Command-line reprocessing (factory overrides / config, checked with +EXP_*;
# see "CL_EXPECT" in the log):
#   make run_cl                no save: post-tree and main-tree settings on
#                              the command line, post tree built at the
#                              release
#   make save_cl               save point B with STALE settings: pcie_driver
#                              -> pcie_driver_slow, post profile "stale",
#                              main env post_window 1
#   make restore_cl            restore save_cl with NEW settings: the
#                              restore merges them after the stale ones:
#                              pcie_post_test_b, pcie_driver ->
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
#   Overrides: POST_TEST=pcie_post_test POST_MAIN=50 CKPT_NAME=post_ckpt_b
#              ARGS='+...' VERBOSITY=UVM_LOW
# ============================================================================

CKPT_NAME   ?= post_ckpt_b
CL_CKPT     ?= post_ckpt_cl
EXTRA_CKPTS  = $(CL_CKPT)
POST_TEST   ?= pcie_post_test_b
POST_MAIN   ?= 50

include ../common/common.mk

.DEFAULT_GOAL := help

# Stale settings given to the save run only.
CL_STALE = +uvm_set_type_override=pcie_driver,pcie_driver_slow \
           +uvm_set_config_string=uvm_post_top.env,profile,stale \
           +uvm_set_config_int=uvm_test_top.env,post_window,1
# Settings given to the restored (or plain) run, and what they must give.
CL_NEW   = +POST_TEST=pcie_post_test_b \
           +uvm_set_type_override=pcie_driver,pcie_driver_fast \
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

save_cl restore_cl restore_cl_keep: CKPT_NAME = $(CL_CKPT)

.PHONY: run_default run_release_reset run_release_late run_post_long run_post_b \
        run_tb_release run_norelease run_gate_timeout run_jump_main_back \
        run_jump_main_fwd run_jump_post_back run_jump_nomirror \
        save restore restore_a run_cl save_cl restore_cl restore_cl_keep

run_default:
	$(call sim_run,run_default,)

run_release_reset:
	$(call sim_run,run_release_reset,+RELEASE_PHASE=reset +RELEASE_DELAY=5)

run_release_late:
	$(call sim_run,run_release_late,+RELEASE_DELAY=90)

run_post_long:
	$(call sim_run,run_post_long,+POST_MAIN=300)

run_post_b:
	$(call sim_run,run_post_b,+POST_TEST=pcie_post_test_b)

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
	$(call sim_restore,restore_$(POST_TEST),+POST_TEST=$(POST_TEST) +POST_MAIN=$(POST_MAIN))

restore_a:
	$(call sim_restore,restore_a,+POST_TEST=pcie_post_test)

run_cl:
	$(call sim_run,run_cl,$(CL_NEW) $(CL_EXP))

save_cl:
	$(call sim_save,save_cl,+SAVE_BEFORE_RELEASE $(CL_STALE))

restore_cl:
	$(call sim_restore,restore_cl,$(CL_NEW) $(CL_EXP))

restore_cl_keep:
	$(call sim_restore,restore_cl_keep,$(CL_EXP_KEEP))

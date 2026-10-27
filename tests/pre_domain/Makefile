# ============================================================================
# pre_domain -- Approach B: common boot in the pre domain, main test built at
# release_main().
#
#   make compile               [SIM=vcs|xrun]
#   make run_default           boot 40 ns, then soc_test_a (install default)
#   make run_cmdline           main test from +UVM_TESTNAME=soc_test_b
#   make run_pre_long          fw_load_agt main 300 ns: main main_phase waits
#                              for it (synced phase)
#   make run_jump_back         main jumps main -> reset: pre ends main_phase,
#                              waits at the start of post_main
#   make run_jump_fwd          main jumps main -> shutdown: pre runs the
#                              skipped phases alone, meets main at shutdown
#   make run_gate_timeout      boot never releases: PREDOM/GATE fatal at 500 ns
#   make save                  save point A (boot done, gate closed), $finish
#   make restore               restore A: main test $(MAIN_TEST), +MAIN_SEED
#   make restore_a             restore A with soc_test_a
#   make clean
#
#   Overrides: MAIN_TEST=soc_test_a MAIN_SEED=7 CKPT_NAME=pre_ckpt_a
#              ARGS='+...' VERBOSITY=UVM_LOW
# ============================================================================

CKPT_NAME ?= pre_ckpt_a
MAIN_TEST ?= soc_test_b
MAIN_SEED ?= 42

include ../common/common.mk

.DEFAULT_GOAL := help

.PHONY: run_default run_cmdline run_pre_long run_jump_back run_jump_fwd \
        run_gate_timeout save restore restore_a

run_default:
	$(call sim_run,run_default,)

run_cmdline:
	$(call sim_run,run_cmdline,+UVM_TESTNAME=soc_test_b)

run_pre_long:
	$(call sim_run,run_pre_long,+PRE_MAIN=300)

run_jump_back:
	$(call sim_run,run_jump_back,+MAIN_JUMP_TO=reset)

run_jump_fwd:
	$(call sim_run,run_jump_fwd,+MAIN_JUMP_TO=shutdown)

run_gate_timeout:
	$(call sim_run,run_gate_timeout,+PRE_NO_RELEASE +PRE_GATE_TIMEOUT=500)

save:
	$(call sim_save,save,)

restore:
	$(call sim_restore,restore_$(MAIN_TEST),+UVM_TESTNAME=$(MAIN_TEST) +MAIN_SEED=$(MAIN_SEED))

restore_a:
	$(call sim_restore,restore_a,+UVM_TESTNAME=soc_test_a)

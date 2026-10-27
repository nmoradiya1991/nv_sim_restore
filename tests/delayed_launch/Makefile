# ============================================================================
# delayed_launch -- Approach A: run_test() after the boot / after restore.
#
#   make compile               [SIM=vcs|xrun]
#   make run_classic           no gate: test built at time 0, boot in parallel
#   make run_delayed           gate: boot in SV, dl_test_a built at boot done
#   make run_delayed_b         same, +UVM_TESTNAME=dl_test_b (adds env.chk)
#   make save                  save point A (boot done, no UVM tree), $finish
#   make restore               restore A: $(TEST), +DL_MODE=$(DL_MODE),
#                              n_items=$(N_ITEMS) via +uvm_set_config_int
#   make restore_a             restore A with dl_test_a and the defaults
#   make clean
#
#   Overrides: TEST=dl_test_b DL_MODE=7 N_ITEMS=8 CKPT_NAME=dl_ckpt_a
#              ARGS='+...' VERBOSITY=UVM_LOW
# ============================================================================

CKPT_NAME ?= dl_ckpt_a
TEST      ?= dl_test_b
DL_MODE   ?= 7
N_ITEMS   ?= 8

include ../common/common.mk

.DEFAULT_GOAL := help

GATE        = +NV_SOCV_DELAYED_TEST_LAUNCH
SET_N_ITEMS = +uvm_set_config_int=uvm_test_top.env.drv,n_items,$(N_ITEMS)

.PHONY: run_classic run_delayed run_delayed_b save restore restore_a

run_classic:
	$(call sim_run,run_classic,)

run_delayed:
	$(call sim_run,run_delayed,$(GATE))

run_delayed_b:
	$(call sim_run,run_delayed_b,$(GATE) +UVM_TESTNAME=dl_test_b)

save:
	$(call sim_save,save,$(GATE))

restore:
	$(call sim_restore,restore_$(TEST),$(GATE) +UVM_TESTNAME=$(TEST) \
	  +DL_MODE=$(DL_MODE) $(SET_N_ITEMS))

restore_a:
	$(call sim_restore,restore_a,$(GATE) +UVM_TESTNAME=dl_test_a)

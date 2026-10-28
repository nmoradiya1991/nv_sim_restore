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
#
# Command-line reprocessing (factory overrides / config at non-zero time,
# checked with +EXP_*; see "CL_EXPECT" in the log):
#   make run_cl                no save: overrides on the command line, test
#                              built at boot done after the refresh
#   make save_cl               save point A with STALE settings on the save
#                              command line: driver -> dl_driver_slow,
#                              n_items 2, profile "stale"
#   make restore_cl            restore save_cl with NEW settings: driver ->
#                              dl_driver_fast (type), env.chk ->
#                              dl_checker_strict (instance), n_items 12 over
#                              the env's own set of 4, profile "stress"
#   make restore_cl_drop       restore save_cl with no settings: the stale
#                              ones are gone (the argv tables are rebuilt)
#   make clean
#
#   Overrides: TEST=dl_test_b DL_MODE=7 N_ITEMS=8 CKPT_NAME=dl_ckpt_a
#              ARGS='+...' VERBOSITY=UVM_LOW
# ============================================================================

CKPT_NAME   ?= dl_ckpt_a
CL_CKPT     ?= dl_ckpt_cl
EXTRA_CKPTS  = $(CL_CKPT)
TEST        ?= dl_test_b
DL_MODE     ?= 7
N_ITEMS     ?= 8

include ../common/common.mk

.DEFAULT_GOAL := help

GATE        = +NV_SOCV_DELAYED_TEST_LAUNCH
SET_N_ITEMS = +uvm_set_config_int=uvm_test_top.env.drv,n_items,$(N_ITEMS)

# Stale settings given to the save run only.
CL_STALE = +uvm_set_type_override=dl_driver,dl_driver_slow \
           +uvm_set_config_int=uvm_test_top.env.drv,n_items,2 \
           +uvm_set_config_string=uvm_test_top.env,profile,stale
# Settings given to the restored (or plain) run, and what they must give.
CL_NEW   = +UVM_TESTNAME=dl_test_b \
           +uvm_set_type_override=dl_driver,dl_driver_fast \
           +uvm_set_inst_override=dl_checker,dl_checker_strict,uvm_test_top.env.chk \
           +uvm_set_config_int=uvm_test_top.env.drv,n_items,12 \
           +uvm_set_config_string=uvm_test_top.env,profile,stress
CL_EXP   = +EXP_DRV_TYPE=dl_driver_fast +EXP_CHK_TYPE=dl_checker_strict \
           +EXP_N_ITEMS=12 +EXP_PROFILE=stress
CL_EXP_DROP = +UVM_TESTNAME=dl_test_b +EXP_DRV_TYPE=dl_driver \
           +EXP_CHK_TYPE=dl_checker +EXP_N_ITEMS=4 +EXP_PROFILE=default

save_cl restore_cl restore_cl_drop: CKPT_NAME = $(CL_CKPT)

.PHONY: run_classic run_delayed run_delayed_b save restore restore_a \
        run_cl save_cl restore_cl restore_cl_drop

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

run_cl:
	$(call sim_run,run_cl,$(GATE) $(CL_NEW) $(CL_EXP))

save_cl:
	$(call sim_save,save_cl,$(GATE) $(CL_STALE))

restore_cl:
	$(call sim_restore,restore_cl,$(GATE) $(CL_NEW) $(CL_EXP))

restore_cl_drop:
	$(call sim_restore,restore_cl_drop,$(GATE) $(CL_EXP_DROP))

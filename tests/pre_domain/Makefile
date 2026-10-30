# ============================================================================
# pre_domain -- Approach B: common boot in the pre domain, main test
# (soc_test_a) built at release_main().
#
#   make compile               [SIM=vcs|xrun] [TOPO=v1|v2]
#   make run_default           boot 40 ns, then soc_test_a
#   make run_pre_long          fw_load_agt main 300 ns: main main_phase waits
#                              for it (synced phase)
#   make run_jump_back         main jumps main -> reset: pre ends main_phase,
#                              waits at the start of post_main
#   make run_jump_fwd          main jumps main -> shutdown: pre runs the
#                              skipped phases alone, meets main at shutdown
#   make run_gate_timeout      boot never releases: PREDOM/GATE fatal at 500 ns
#   make save                  save point A (boot done, main test not built)
#   make restore               restore A: same test, +MAIN_SEED, plus the
#                              command-line overrides below, checked
#                              (CL=0: +MAIN_SEED only)
#
# Topology: TOPO=v2 builds env.soc_sb in the same test (+define+TOPO_V2 on
# main_tb_pkg). With FLOW=dtl (or dtr, SIM=xrun) the checkpoint is reused:
#   make compile save restore FLOW=dtl             topology v1
#   make compile_pkg restore FLOW=dtl TOPO=v2      same checkpoint, v2
#
# Command-line reprocessing (factory overrides / config, checked with +EXP_*;
# see "CL_EXPECT" in the log):
#   make run_cl_pre            time 0, pre tree: fw_load_agent ->
#                              fw_load_agent_fast (type), fw_load_agt
#                              main_delay 90 over the boot env's own set
#   make run_cl_main           no save: main-tree overrides on the command
#                              line, main tree built at the release
#   make save_cl               save point A with STALE main-tree settings:
#                              cpu_agent -> cpu_agent_slow, cpu main 5,
#                              profile "stale"
#   make restore_cl            restore save_cl with NEW settings:
#                              cpu_agent -> cpu_agent_fast (type),
#                              env.ddr_agt -> ddr_agent_lp (instance), cpu
#                              main 250 over the env's own set, profile "perf"
#   make restore_cl_drop       restore save_cl with no settings: repopulate
#                              flushes the stale ones (VCS); Xcelium still
#                              reports them after the restart, so they stay
#   make clean
#
# FLOW=dtl (VCS Dynamic Test Load) or FLOW=dtr SIM=xrun (Xcelium Dynamic Test
# Reload): the saved image has the boot (pre test)
# only; main_tb_pkg is loaded right after the restore and the main test is
# built from it at release_main().
#   static : pre_tb_pkg.sv, tb_top.sv (static.f)   dynamic: main_tb_pkg.sv
#   restore_cl restores the `save` checkpoint; save_cl, restore_cl_drop and
#   the run_* targets are FLOW=std only (save_cl's stale overrides name
#   main_tb_pkg classes, which the save run does not have).
#
#   Overrides: MAIN_SEED=7 CL=0 TOPO=v2 CKPT_NAME=pre_ckpt_a
#              ARGS='+...' VERBOSITY=UVM_LOW
# ============================================================================

CKPT_NAME   ?= pre_ckpt_a
SAVE_CKPT   := $(CKPT_NAME)
CL_CKPT     ?= pre_ckpt_cl
EXTRA_CKPTS  = $(CL_CKPT)
DYN_PKG      = main_tb_pkg
MAIN_SEED   ?= 42
CL          ?= 1

include ../common/common.mk

.DEFAULT_GOAL := help

CL_PRE   = +uvm_set_type_override=fw_load_agent,fw_load_agent_fast \
           +uvm_set_config_int=uvm_pre_top.env.fw_load_agt,main_delay,90 \
           +EXP_FW_TYPE=fw_load_agent_fast +EXP_FW_MAIN=90
# Stale settings given to the save run only.
CL_STALE = +uvm_set_type_override=cpu_agent,cpu_agent_slow \
           '+uvm_set_config_int=uvm_test_top.env.cpu_agt*,main_delay,5' \
           +uvm_set_config_string=uvm_test_top.env,profile,stale
# Settings given to the restored (or plain) run, and what they must give.
CL_OVR   = +uvm_set_type_override=cpu_agent,cpu_agent_fast \
           +uvm_set_inst_override=ddr_agent,ddr_agent_lp,uvm_test_top.env.ddr_agt \
           '+uvm_set_config_int=uvm_test_top.env.cpu_agt*,main_delay,250' \
           +uvm_set_config_string=uvm_test_top.env,profile,perf
CL_EXP   = +EXP_CPU_TYPE=cpu_agent_fast +EXP_DDR_TYPE=ddr_agent_lp \
           +EXP_CPU_MAIN=250 +EXP_PROFILE=perf
CL_EXP_DROP = +EXP_DDR_TYPE=ddr_agent \
           $(if $(filter xrun,$(SIM)),+EXP_CPU_TYPE=cpu_agent_slow +EXP_CPU_MAIN=5 +EXP_PROFILE=stale,+EXP_CPU_TYPE=cpu_agent +EXP_CPU_MAIN=100 +EXP_PROFILE=default)
# CL=1 (default): restore also passes CL_OVR and checks it.
RESTORE_CL = $(if $(filter 1,$(CL)),$(CL_OVR) $(CL_EXP))

save_cl restore_cl_drop: CKPT_NAME = $(CL_CKPT)
restore_cl: CKPT_NAME = $(if $(DYN),$(SAVE_CKPT),$(CL_CKPT))

.PHONY: run_default run_pre_long run_jump_back run_jump_fwd \
        run_gate_timeout save restore \
        run_cl_pre run_cl_main save_cl restore_cl restore_cl_drop

run_default:
	$(call sim_run,run_default,)

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
	$(call sim_restore,restore,+MAIN_SEED=$(MAIN_SEED) $(RESTORE_CL))

run_cl_pre:
	$(call sim_run,run_cl_pre,$(CL_PRE))

run_cl_main:
	$(call sim_run,run_cl_main,$(CL_OVR) $(CL_EXP))

save_cl:
	$(call std_only,the stale overrides name main_tb_pkg classes)
	$(call sim_save,save_cl,$(CL_STALE))

restore_cl:
	$(call sim_restore,restore_cl,$(CL_OVR) $(CL_EXP))

restore_cl_drop:
	$(call std_only,needs the save_cl checkpoint)
	$(call sim_restore,restore_cl_drop,$(CL_EXP_DROP))

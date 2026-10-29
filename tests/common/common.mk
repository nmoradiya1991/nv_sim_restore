# ============================================================================
# common.mk -- shared VCS / Xcelium flow for the nv_socv_sim_restore tests.
#
# Included by tests/<test>/Makefile, which sets CKPT_NAME and DTL_PKG (and
# TOP if it is not tb_top) and defines the scenario targets with sim_run /
# sim_save / sim_restore.
#
#   SIM=vcs   (default)  vcs -ntb_opts $(UVM_VER)   save: $save    restore: simv -r
#   SIM=xrun             xrun -uvm -uvmhome $(UVM_HOME) -process_save
#                        save: $save("<name>")     restore: xrun -r <name>
#                        needs XCELIUM_HOME (or XRUN) and UVM_HOME
#
#   FLOW=std  (default)  one image with every file (files.f)
#   FLOW=dtl             VCS Dynamic Test Load, VCS only. Same targets:
#     compile      static image: vlogan +define+NV_DTL uvm_pkg, library,
#                  tests common, static.f; vcs -partcomp -enable_dynamic_tb
#                  -dir=DTL_STATIC -o simv_dtl
#                  then the dynamic package $(DTL_PKG): vlogan $(DTL_PKG).sv;
#                  vcs -partcomp $(DTL_PKG) -dynamic_tb -sharedlib=DTL_STATIC
#                  -dir=DTL_$(DTL_PKG)
#     compile_pkg  the dynamic package only (after editing it, or with
#                  TOPO=v1|v2; the saved checkpoints stay valid)
#     save         ./simv_dtl ... (static image only), into ckpt_vcs_dtl/
#     restore      ./simv_dtl -r ... +dtl_add_pkg=DTL_$(DTL_PKG):$(DTL_PKG);
#                  sim_save_restore.sv calls $dtl_load right after the restore
#     run_*        not available: without a restore nothing loads the package
#
# Variables:
#   UVM_VER      VCS UVM library (-ntb_opts / etc/<ver>)  (default uvm-1.2)
#   VCS_HOME     optional; vcs is taken from PATH when unset
#   XCELIUM_HOME Xcelium install (xrun = $(XCELIUM_HOME)/tools/bin/xrun)
#   UVM_HOME     Xcelium -uvmhome (install path or CDNS-1.2 / CDNS-IEEE)
#   VERBOSITY    +UVM_VERBOSITY                       (default UVM_MEDIUM)
#   ARGS         extra plusargs appended to every run
#   SAVE_FINISH  1: $finish right after the save      (default 1)
#   EXTRA_CKPTS  other checkpoint names used by the test (removed by clean)
#   VCS_EXTRA / XRUN_EXTRA   extra compile options
#   DTL_ELAB_OPTS  FLOW=dtl: vcs options of BOTH elaborations (must match,
#                  else DTL-SHLIB-ERR)  (default -full64 -sverilog +vcs+lic+wait)
#   TOPO         v1 | v2: v2 compiles the testbench with +define+TOPO_V2 (a
#                different topology of the same test, in the package built
#                after the save point). FLOW=dtl: only the dynamic package
#                gets it, so make compile_pkg FLOW=dtl TOPO=v2 is enough and
#                the existing checkpoint is reused       (default v1)
# ============================================================================

COMMON_DIR  := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
LIB_DIR     ?= $(abspath $(COMMON_DIR)/../..)
SIM         ?= vcs
FLOW        ?= std
TOP         ?= tb_top
CKPT_NAME   ?= ckpt
LOG_DIR     ?= logs
VERBOSITY   ?= UVM_MEDIUM
SAVE_FINISH ?= 1
UVM_VER     ?= uvm-1.2
TOPO        ?= v1

ifeq ($(filter v1 v2,$(TOPO)),)
  $(error TOPO must be v1 or v2, got '$(TOPO)')
endif
TOPO_DEFS := $(if $(filter v2,$(TOPO)),+define+TOPO_V2)

ifeq ($(filter std dtl,$(FLOW)),)
  $(error FLOW must be std or dtl, got '$(FLOW)')
endif
DTL := $(filter dtl,$(FLOW))
ifneq ($(DTL),)
  ifneq ($(SIM),vcs)
    $(error FLOW=dtl is VCS only (SIM=vcs))
  endif
endif

LIB_FILES = +incdir+$(LIB_DIR)/src \
            $(LIB_DIR)/src/nv_socv_sim_restore_pkg.sv \
            +incdir+$(COMMON_DIR) \
            $(COMMON_DIR)/tests_common_pkg.sv \
            $(COMMON_DIR)/sim_save_restore.sv
TB_FILES  = -f files.f
SIM_ARGS  = +UVM_VERBOSITY=$(VERBOSITY) $(ARGS)
SR_FINISH = $(if $(filter 1,$(SAVE_FINISH)),+sim_finish_after_save)
LOG_TAG   = $(SIM)$(if $(DTL),_dtl)

ifeq ($(SIM),vcs)
  VCS_HOME_ = $(or $(VCS_HOME),$(abspath $(dir $(shell which vcs 2>/dev/null))/..))
  VCS_BIN  ?= $(if $(VCS_HOME),$(VCS_HOME)/bin/vcs,vcs)
  SIMV      = $(if $(DTL),simv_dtl,simv)
  CKPT_DIR  = $(if $(DTL),ckpt_vcs_dtl,ckpt_vcs)
  DTL_ARGS  = $(if $(DTL),+dtl_add_pkg=DTL_$(DTL_PKG):$(DTL_PKG))

  COMPILE_CMD = $(VCS_BIN) -full64 -sverilog -ntb_opts $(UVM_VER) \
                -timescale=1ns/1ps -debug_access+all +vcs+lic+wait \
                -top $(TOP) $(TOPO_DEFS) $(LIB_FILES) $(TB_FILES) $(VCS_EXTRA) -o $(SIMV)
  RUN_CMD     = ./$(SIMV) $(SIM_ARGS)
  SAVE_CMD    = mkdir -p $(CKPT_DIR) && ./$(SIMV) $(SIM_ARGS) \
                +sim_image_save_enable +sim_image_save_dir_path=$(CKPT_DIR) \
                +sim_image_save_file=$(CKPT_NAME).chk $(SR_FINISH)
  RESTORE_CMD = ./$(SIMV) -r $(CKPT_DIR)/$(CKPT_NAME).chk \
                +sim_image_restore_enable $(DTL_ARGS) $(SIM_ARGS)
  TOOL_CHECK  = true

  # FLOW=dtl: three-step flow; the dynamic package is elaborated against the
  # static partition, so the static image is built first.
  DTL_VLOGAN      = $(VCS_HOME_)/bin/vlogan
  DTL_VCS         = $(VCS_HOME_)/bin/vcs
  DTL_UVM_DIR     = $(VCS_HOME_)/etc/$(UVM_VER)
  DTL_ELAB_OPTS  ?= -full64 -sverilog +vcs+lic+wait
  DTL_AN_OPTS     = -full64 -sverilog -timescale=1ns/1ps +v2k +vcs+lic+wait \
                    +incdir+$(DTL_UVM_DIR)/src
  DTL_AN_STATIC   = $(DTL_AN_OPTS) +define+NV_DTL $(DTL_UVM_DIR)/uvm_pkg.sv \
                    $(LIB_FILES) -f static.f $(VCS_EXTRA)
  DTL_ELAB_STATIC = $(DTL_ELAB_OPTS) -top $(TOP) -partcomp -dir=DTL_STATIC \
                    -enable_dynamic_tb $(DTL_UVM_DIR)/dpi/uvm_dpi.cc -CFLAGS -DVCS \
                    -o $(SIMV)
  DTL_AN_PKG      = $(DTL_AN_OPTS) $(TOPO_DEFS) +incdir+$(LIB_DIR)/src +incdir+$(COMMON_DIR) \
                    $(DTL_PKG).sv
  DTL_ELAB_PKG    = $(DTL_ELAB_OPTS) -partcomp $(DTL_PKG) -dir=DTL_$(DTL_PKG) \
                    -sharedlib=DTL_STATIC -dynamic_tb
  ifneq ($(DTL),)
    TOOL_CHECK = test -n "$(DTL_PKG)" || { echo "DTL_PKG not set by the test Makefile"; exit 1; }; \
                 test -x "$(DTL_VCS)" || { echo "vcs not found: set VCS_HOME or put vcs on PATH"; exit 1; }
  endif

else ifeq ($(SIM),xrun)
  XRUN     ?= $(XCELIUM_HOME)/tools/bin/xrun
  XLIB     ?= xcelium.d

  COMPILE_CMD = $(XRUN) -64bit -sv -uvm -uvmhome $(UVM_HOME) \
                -timescale 1ns/1ps -access +rwc -elaborate -process_save \
                -xmlibdirname $(XLIB) +define+NV_SR_XCELIUM \
                -top $(TOP) $(TOPO_DEFS) $(LIB_FILES) $(TB_FILES) $(XRUN_EXTRA)
  RUN_CMD     = $(XRUN) -64bit -R -process_save -xmlibdirname $(XLIB) $(SIM_ARGS)
  SAVE_CMD    = $(XRUN) -64bit -R -process_save -xmlibdirname $(XLIB) \
                $(SIM_ARGS) +sim_image_save_enable \
                +sim_image_save_file=$(CKPT_NAME) $(SR_FINISH)
  RESTORE_CMD = $(XRUN) -64bit -r $(CKPT_NAME) \
                +sim_image_restore_enable $(SIM_ARGS)
  TOOL_CHECK  = test -n "$(UVM_HOME)" && test -x "$(XRUN)" || \
                { echo "SIM=xrun: set XCELIUM_HOME (or XRUN) and UVM_HOME"; exit 1; }

else
  $(error SIM must be vcs or xrun, got '$(SIM)')
endif

# $(call std_only,<reason>): first recipe line of a target that cannot run
# with FLOW=dtl; stops it there with <reason> (no commas in <reason>).
std_only    = $(if $(DTL),@echo "$@: not available with FLOW=dtl: $(1)"; exit 1)

# $(call sim_run,<log name>,<plusargs>)
sim_run     = $(if $(DTL),@echo "$@: not available with FLOW=dtl: no restore so nothing loads $(DTL_PKG)"; exit 1,\
              mkdir -p $(LOG_DIR) && $(RUN_CMD) $(2) -l $(LOG_DIR)/$(1)_$(LOG_TAG).log)
# $(call sim_save,<log name>,<plusargs>): save at the test's save point
sim_save    = mkdir -p $(LOG_DIR) && $(SAVE_CMD) $(2) -l $(LOG_DIR)/$(1)_$(LOG_TAG).log
# $(call sim_restore,<log name>,<new plusargs>): restore $(CKPT_NAME)
sim_restore = mkdir -p $(LOG_DIR) && $(RESTORE_CMD) $(2) -l $(LOG_DIR)/$(1)_$(LOG_TAG).log

.PHONY: help compile compile_pkg clean

help:
	@awk '/^#/ {print; next} {exit}' $(firstword $(MAKEFILE_LIST))

ifeq ($(DTL),)
compile:
	@$(TOOL_CHECK)
	mkdir -p $(LOG_DIR)
	$(COMPILE_CMD) -l $(LOG_DIR)/compile_$(SIM).log

compile_pkg:
	@echo "compile_pkg: FLOW=dtl only (the dynamic package)"; exit 1
else
compile:
	@$(TOOL_CHECK)
	mkdir -p $(LOG_DIR)
	$(DTL_VLOGAN) $(DTL_AN_STATIC) -l $(LOG_DIR)/compile_static_$(LOG_TAG).an.log
	$(DTL_VCS) $(DTL_ELAB_STATIC) -l $(LOG_DIR)/compile_static_$(LOG_TAG).log
	$(DTL_VLOGAN) $(DTL_AN_PKG) -l $(LOG_DIR)/compile_$(DTL_PKG)_$(LOG_TAG).an.log
	$(DTL_VCS) $(DTL_ELAB_PKG) -l $(LOG_DIR)/compile_$(DTL_PKG)_$(LOG_TAG).log

compile_pkg:
	@$(TOOL_CHECK)
	mkdir -p $(LOG_DIR)
	$(DTL_VLOGAN) $(DTL_AN_PKG) -l $(LOG_DIR)/compile_$(DTL_PKG)_$(LOG_TAG).an.log
	$(DTL_VCS) $(DTL_ELAB_PKG) -l $(LOG_DIR)/compile_$(DTL_PKG)_$(LOG_TAG).log
endif

# Every simulator's and flow's outputs, whatever SIM / FLOW is.
VCS_CLEAN  = simv simv.daidir simv_dtl simv_dtl.daidir csrc ucli.key \
             vc_hdrs.h AN.DB 64 tr_db.log ckpt_vcs ckpt_vcs_dtl \
             DTL_STATIC $(if $(DTL_PKG),DTL_$(DTL_PKG))
XRUN_CLEAN = $(or $(XLIB),xcelium.d) xrun.history xrun.key .simvision \
             waves.shm .process_save .xm_dmtcp_env.txt_* \
             $(CKPT_NAME) $(CKPT_NAME).* $(foreach c,$(EXTRA_CKPTS),$(c) $(c).*)

clean:
	rm -rf $(VCS_CLEAN) $(XRUN_CLEAN) $(LOG_DIR) *.log

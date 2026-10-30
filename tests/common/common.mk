# ============================================================================
# common.mk -- shared VCS / Xcelium flow for the nv_socv_sim_restore tests.
#
# Included by tests/<test>/Makefile, which sets CKPT_NAME and DYN_PKG (and
# TOP if it is not tb_top) and defines the scenario targets with sim_run /
# sim_save / sim_restore.
#
#   SIM=vcs   (default)  vcs -ntb_opts $(UVM_VER)   save: $save    restore: simv -r
#   SIM=xrun             xrun -uvm -uvmhome $(UVM_HOME) -process_save
#                        save: $save("<name>")     restore: xrun -r <name>
#                        needs XCELIUM_HOME (or XRUN) and UVM_HOME
#
#   FLOW=std  (default)  one image with every file (files.f)
#   FLOW=dtl             VCS Dynamic Test Load, SIM=vcs only. Same targets:
#     compile      static image: vlogan +define+NV_DTL +define+NV_DYN_TB
#                  uvm_pkg, library, tests common, static.f; vcs -partcomp
#                  -enable_dynamic_tb -dir=DTL_STATIC -o simv_dtl
#                  then the dynamic package $(DYN_PKG): vlogan $(DYN_PKG).sv;
#                  vcs -partcomp $(DYN_PKG) -dynamic_tb -sharedlib=DTL_STATIC
#                  -dir=DTL_$(DYN_PKG)
#     compile_pkg  the dynamic package only (after editing it, or with
#                  TOPO=v1|v2; the saved checkpoints stay valid)
#     save         ./simv_dtl ... (static image only), into ckpt_vcs_dtl/
#     restore      ./simv_dtl -r ... +dtl_add_pkg=DTL_$(DYN_PKG):$(DYN_PKG);
#                  sim_save_restore.sv calls $dtl_load right after the restore
#     run_*        not available: without a restore nothing loads the package
#   FLOW=dtr             Xcelium Dynamic Test Reload, SIM=xrun only. Same targets:
#     compile      dynamic base snapshot $(DTR_BASE): xrun -elaborate
#                  -process_save -mkdbssnap -name $(DTR_BASE) +define+NV_DYN_TB
#                  library, tests common, static.f, in $(XLIB)
#     save         xrun -r $(DTR_BASE) -name $(DTR_BASE) -process_save
#                  -cds_implicit_tmpdir ckpt_xrun_dtr: $save("<name>")
#     restore      xrun $(DYN_PKG).sv -process_save -uvm -uvmnoautocompile
#                  -dbsname $(DTR_BASE) -dbssnap <name>
#                  -cds_alternate_tmpdir ckpt_xrun_dtr: compiles and links the
#                  package with the saved snapshot, then restarts from it
#     compile_pkg  nothing to do: restore always compiles the package
#     run_*        not available: without a restore nothing links the package
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
#   DTR_BASE     FLOW=dtr: dynamic base snapshot name   (default dbs_base)
#   TOPO         v1 | v2: v2 compiles the testbench with +define+TOPO_V2 (a
#                different topology of the same test, in the package built
#                after the checkpoint). FLOW=dtl / dtr: only the dynamic
#                package gets it, so the existing checkpoint is reused:
#                make compile_pkg restore FLOW=dtl|dtr TOPO=v2   (default v1)
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
DTR_BASE    ?= dbs_base

ifeq ($(filter v1 v2,$(TOPO)),)
  $(error TOPO must be v1 or v2, got '$(TOPO)')
endif
TOPO_DEFS := $(if $(filter v2,$(TOPO)),+define+TOPO_V2)

ifeq ($(filter std dtl dtr,$(FLOW)),)
  $(error FLOW must be std, dtl or dtr, got '$(FLOW)')
endif
DTL := $(filter dtl,$(FLOW))
DTR := $(filter dtr,$(FLOW))
DYN := $(DTL)$(DTR)
ifneq ($(DTL),)
  ifneq ($(SIM),vcs)
    $(error FLOW=dtl is VCS only (SIM=vcs); use FLOW=dtr with SIM=xrun)
  endif
endif
ifneq ($(DTR),)
  ifneq ($(SIM),xrun)
    $(error FLOW=dtr is Xcelium only (SIM=xrun); use FLOW=dtl with SIM=vcs)
  endif
endif

LIB_INCS  = +incdir+$(LIB_DIR)/src +incdir+$(COMMON_DIR)
LIB_FILES = +incdir+$(LIB_DIR)/src \
            $(LIB_DIR)/src/nv_socv_sim_restore_pkg.sv \
            +incdir+$(COMMON_DIR) \
            $(COMMON_DIR)/tests_common_pkg.sv \
            $(COMMON_DIR)/sim_save_restore.sv
TB_FILES  = -f files.f
SIM_ARGS  = +UVM_VERBOSITY=$(VERBOSITY) $(ARGS)
SR_FINISH = $(if $(filter 1,$(SAVE_FINISH)),+sim_finish_after_save)
LOG_TAG   = $(SIM)$(if $(DYN),_$(FLOW))
# $(call ckpt_file,<name>): checkpoint file as given to +sim_image_save_file
ckpt_file = $(if $(filter vcs,$(SIM)),$(1).chk,$(1))
CKPT_FILE = $(call ckpt_file,$(CKPT_NAME))

ifeq ($(SIM),vcs)
  VCS_HOME_ = $(or $(VCS_HOME),$(abspath $(dir $(shell which vcs 2>/dev/null))/..))
  VCS_BIN  ?= $(if $(VCS_HOME),$(VCS_HOME)/bin/vcs,vcs)
  SIMV      = $(if $(DTL),simv_dtl,simv)
  CKPT_DIR  = $(if $(DTL),ckpt_vcs_dtl,ckpt_vcs)
  DTL_ARGS  = $(if $(DTL),+dtl_add_pkg=DTL_$(DYN_PKG):$(DYN_PKG))

  COMPILE_CMD = $(VCS_BIN) -full64 -sverilog -ntb_opts $(UVM_VER) \
                -timescale=1ns/1ps -debug_access+all +vcs+lic+wait \
                -top $(TOP) $(TOPO_DEFS) $(LIB_FILES) $(TB_FILES) $(VCS_EXTRA) -o $(SIMV)
  RUN_CMD     = ./$(SIMV) $(SIM_ARGS)
  SAVE_CMD    = mkdir -p $(CKPT_DIR) && ./$(SIMV) $(SIM_ARGS) \
                +sim_image_save_enable +sim_image_save_dir_path=$(CKPT_DIR) \
                +sim_image_save_file=$(CKPT_FILE) $(SR_FINISH)
  RESTORE_CMD = ./$(SIMV) -r $(CKPT_DIR)/$(CKPT_FILE) \
                +sim_image_restore_enable +sim_image_restore_file=$(CKPT_FILE) \
                $(DTL_ARGS) $(SIM_ARGS)
  TOOL_CHECK  = true

  # FLOW=dtl: three-step flow; the dynamic package is elaborated against the
  # static partition, so the static image is built first.
  DTL_VLOGAN      = $(VCS_HOME_)/bin/vlogan
  DTL_VCS         = $(VCS_HOME_)/bin/vcs
  DTL_UVM_DIR     = $(VCS_HOME_)/etc/$(UVM_VER)
  DTL_ELAB_OPTS  ?= -full64 -sverilog +vcs+lic+wait
  DTL_AN_OPTS     = -full64 -sverilog -timescale=1ns/1ps +v2k +vcs+lic+wait \
                    +incdir+$(DTL_UVM_DIR)/src
  DTL_AN_STATIC   = $(DTL_AN_OPTS) +define+NV_DTL +define+NV_DYN_TB \
                    $(DTL_UVM_DIR)/uvm_pkg.sv $(LIB_FILES) -f static.f $(VCS_EXTRA)
  DTL_ELAB_STATIC = $(DTL_ELAB_OPTS) -top $(TOP) -partcomp -dir=DTL_STATIC \
                    -enable_dynamic_tb $(DTL_UVM_DIR)/dpi/uvm_dpi.cc -CFLAGS -DVCS \
                    -o $(SIMV)
  DTL_AN_PKG      = $(DTL_AN_OPTS) $(TOPO_DEFS) $(LIB_INCS) $(DYN_PKG).sv
  DTL_ELAB_PKG    = $(DTL_ELAB_OPTS) -partcomp $(DYN_PKG) -dir=DTL_$(DYN_PKG) \
                    -sharedlib=DTL_STATIC -dynamic_tb
  ifneq ($(DTL),)
    TOOL_CHECK = test -n "$(DYN_PKG)" || { echo "DYN_PKG not set by the test Makefile"; exit 1; }; \
                 test -x "$(DTL_VCS)" || { echo "vcs not found: set VCS_HOME or put vcs on PATH"; exit 1; }
  endif

else ifeq ($(SIM),xrun)
  XRUN     ?= $(XCELIUM_HOME)/tools/bin/xrun
  XLIB     ?= $(if $(DTR),xcelium_dtr.d,xcelium.d)
  CKPT_DIR  = ckpt_xrun_dtr
  XRUN_ELAB = -64bit -sv -uvm -uvmhome $(UVM_HOME) -timescale 1ns/1ps \
              -access +rwc -process_save -xmlibdirname $(XLIB) +define+NV_SR_XCELIUM

  ifeq ($(DTR),)
  COMPILE_CMD = $(XRUN) $(XRUN_ELAB) -elaborate \
                -top $(TOP) $(TOPO_DEFS) $(LIB_FILES) $(TB_FILES) $(XRUN_EXTRA)
  RUN_CMD     = $(XRUN) -64bit -R -process_save -xmlibdirname $(XLIB) $(SIM_ARGS)
  SAVE_CMD    = $(XRUN) -64bit -R -process_save -xmlibdirname $(XLIB) \
                $(SIM_ARGS) +sim_image_save_enable \
                +sim_image_save_file=$(CKPT_FILE) $(SR_FINISH)
  RESTORE_CMD = $(XRUN) -64bit -r $(CKPT_NAME) \
                +sim_image_restore_enable +sim_image_restore_file=$(CKPT_FILE) $(SIM_ARGS)
  else
  # FLOW=dtr: the base snapshot never contains $(DYN_PKG); each restore
  # compiles it and links it with the saved snapshot (DTS) before restarting.
  COMPILE_CMD = $(XRUN) $(XRUN_ELAB) -elaborate -mkdbssnap -name $(DTR_BASE) \
                +define+NV_DYN_TB -top $(TOP) $(LIB_FILES) -f static.f $(XRUN_EXTRA)
  SAVE_CMD    = mkdir -p $(CKPT_DIR) && $(XRUN) -64bit -r $(DTR_BASE) -name $(DTR_BASE) \
                -process_save -xmlibdirname $(XLIB) -cds_implicit_tmpdir $(CKPT_DIR) \
                $(SIM_ARGS) +sim_image_save_enable \
                +sim_image_save_file=$(CKPT_FILE) $(SR_FINISH)
  RESTORE_CMD = $(XRUN) $(XRUN_ELAB) -uvmnoautocompile $(TOPO_DEFS) $(LIB_INCS) \
                $(DYN_PKG).sv -dbsname $(DTR_BASE) -dbssnap $(CKPT_NAME) \
                -cds_alternate_tmpdir $(CKPT_DIR) $(XRUN_EXTRA) \
                +sim_image_restore_enable +sim_image_restore_file=$(CKPT_FILE) \
                +dtr_pkg=$(DYN_PKG) $(SIM_ARGS)
  endif
  TOOL_CHECK  = test -n "$(UVM_HOME)" && test -x "$(XRUN)" || \
                { echo "SIM=xrun: set XCELIUM_HOME (or XRUN) and UVM_HOME"; exit 1; }
  ifneq ($(DTR),)
    TOOL_CHECK += ; test -n "$(DYN_PKG)" || { echo "DYN_PKG not set by the test Makefile"; exit 1; }
  endif

else
  $(error SIM must be vcs or xrun, got '$(SIM)')
endif

# $(call std_only,<reason>): first recipe line of a target that cannot run
# with FLOW=dtl / dtr; stops it there with <reason> (no commas in <reason>).
std_only    = $(if $(DYN),@echo "$@: not available with FLOW=$(FLOW): $(1)"; exit 1)

# $(call sim_run,<log name>,<plusargs>)
sim_run     = $(if $(DYN),@echo "$@: not available with FLOW=$(FLOW): no restore so nothing loads $(DYN_PKG)"; exit 1,\
              mkdir -p $(LOG_DIR) && $(RUN_CMD) $(2) -l $(LOG_DIR)/$(1)_$(LOG_TAG).log)
# $(call sim_save,<log name>,<plusargs>): save at the test's checkpoint
sim_save    = mkdir -p $(LOG_DIR) && $(SAVE_CMD) $(2) -l $(LOG_DIR)/$(1)_$(LOG_TAG).log
# $(call sim_restore,<log name>,<new plusargs>): restore $(CKPT_NAME)
sim_restore = mkdir -p $(LOG_DIR) && $(RESTORE_CMD) $(2) -l $(LOG_DIR)/$(1)_$(LOG_TAG).log

.PHONY: help compile compile_pkg clean

help:
	@awk '/^#/ {print; next} {exit}' $(firstword $(MAKEFILE_LIST))

ifneq ($(DTL),)
compile:
	@$(TOOL_CHECK)
	mkdir -p $(LOG_DIR)
	$(DTL_VLOGAN) $(DTL_AN_STATIC) -l $(LOG_DIR)/compile_static_$(LOG_TAG).an.log
	$(DTL_VCS) $(DTL_ELAB_STATIC) -l $(LOG_DIR)/compile_static_$(LOG_TAG).log
	$(DTL_VLOGAN) $(DTL_AN_PKG) -l $(LOG_DIR)/compile_$(DYN_PKG)_$(LOG_TAG).an.log
	$(DTL_VCS) $(DTL_ELAB_PKG) -l $(LOG_DIR)/compile_$(DYN_PKG)_$(LOG_TAG).log

compile_pkg:
	@$(TOOL_CHECK)
	mkdir -p $(LOG_DIR)
	$(DTL_VLOGAN) $(DTL_AN_PKG) -l $(LOG_DIR)/compile_$(DYN_PKG)_$(LOG_TAG).an.log
	$(DTL_VCS) $(DTL_ELAB_PKG) -l $(LOG_DIR)/compile_$(DYN_PKG)_$(LOG_TAG).log
else ifneq ($(DTR),)
compile:
	@$(TOOL_CHECK)
	mkdir -p $(LOG_DIR)
	$(COMPILE_CMD) -l $(LOG_DIR)/compile_base_$(LOG_TAG).log

compile_pkg:
	@echo "compile_pkg: FLOW=dtr compiles $(DYN_PKG) as part of restore; nothing to do"
else
compile:
	@$(TOOL_CHECK)
	mkdir -p $(LOG_DIR)
	$(COMPILE_CMD) -l $(LOG_DIR)/compile_$(SIM).log

compile_pkg:
	@echo "compile_pkg: FLOW=dtl / dtr only (the dynamic package)"; exit 1
endif

# Every simulator's and flow's outputs, whatever SIM / FLOW is.
VCS_CLEAN  = simv simv.daidir simv_dtl simv_dtl.daidir csrc ucli.key \
             vc_hdrs.h AN.DB 64 tr_db.log ckpt_vcs ckpt_vcs_dtl \
             DTL_STATIC $(if $(DYN_PKG),DTL_$(DYN_PKG))
XRUN_CLEAN = xcelium.d xcelium_dtr.d $(if $(XLIB),$(XLIB)) ckpt_xrun_dtr \
             xrun.history xrun.key .simvision \
             waves.shm .process_save .xm_dmtcp_env.txt_* \
             $(CKPT_NAME) $(CKPT_NAME).* $(foreach c,$(EXTRA_CKPTS),$(c) $(c).*)

clean:
	rm -rf $(VCS_CLEAN) $(XRUN_CLEAN) $(LOG_DIR) *.log

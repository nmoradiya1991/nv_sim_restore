# ============================================================================
# common.mk -- shared VCS / Xcelium flow for the nv_socv_sim_restore tests.
#
# Included by tests/<test>/Makefile, which sets CKPT_NAME (and TOP if it is
# not tb_top) and defines the scenario targets with sim_run / sim_save /
# sim_restore.
#
#   SIM=vcs   (default)  vcs -ntb_opts $(UVM_VER)   save: $save    restore: simv -r
#   SIM=xrun             xrun -uvm -uvmhome $(UVM_HOME)
#                        save: $stop + Tcl 'save'   restore: xrun -r
#                        needs XCELIUM_HOME (or XRUN) and UVM_HOME
#
# Variables:
#   UVM_VER      VCS UVM library for -ntb_opts       (default uvm-1.2)
#   VCS_HOME     optional; vcs is taken from PATH when unset
#   XCELIUM_HOME Xcelium install (xrun = $(XCELIUM_HOME)/tools/bin/xrun)
#   UVM_HOME     Xcelium -uvmhome (install path or CDNS-1.2 / CDNS-IEEE)
#   VERBOSITY    +UVM_VERBOSITY                       (default UVM_MEDIUM)
#   ARGS         extra plusargs appended to every run
#   SAVE_FINISH  1: $finish right after the save      (default 1)
#   VCS_EXTRA / XRUN_EXTRA   extra compile options
# ============================================================================

COMMON_DIR  := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
LIB_DIR     ?= $(abspath $(COMMON_DIR)/../..)
SIM         ?= vcs
TOP         ?= tb_top
CKPT_NAME   ?= ckpt
LOG_DIR     ?= logs
VERBOSITY   ?= UVM_MEDIUM
SAVE_FINISH ?= 1

LIB_FILES = +incdir+$(LIB_DIR)/src \
            $(LIB_DIR)/src/nv_socv_sim_restore_pkg.sv \
            +incdir+$(COMMON_DIR) \
            $(COMMON_DIR)/tests_common_pkg.sv \
            $(COMMON_DIR)/sim_save_restore.sv
TB_FILES  = -f files.f
SIM_ARGS  = +UVM_VERBOSITY=$(VERBOSITY) $(ARGS)
SR_FINISH = $(if $(filter 1,$(SAVE_FINISH)),+sim_finish_after_save)

ifeq ($(SIM),vcs)
  UVM_VER  ?= uvm-1.2
  VCS_BIN  ?= $(if $(VCS_HOME),$(VCS_HOME)/bin/vcs,vcs)
  SIMV     ?= simv
  CKPT_DIR ?= ckpt_vcs

  COMPILE_CMD = $(VCS_BIN) -full64 -sverilog -ntb_opts $(UVM_VER) \
                -timescale=1ns/1ps -debug_access+all +vcs+lic+wait \
                -top $(TOP) $(LIB_FILES) $(TB_FILES) $(VCS_EXTRA) -o $(SIMV)
  RUN_CMD     = ./$(SIMV) $(SIM_ARGS)
  SAVE_CMD    = mkdir -p $(CKPT_DIR) && ./$(SIMV) $(SIM_ARGS) \
                +sim_image_save_enable +sim_image_save_dir_path=$(CKPT_DIR) \
                +sim_image_save_file=$(CKPT_NAME).chk $(SR_FINISH)
  RESTORE_CMD = ./$(SIMV) -r $(CKPT_DIR)/$(CKPT_NAME).chk \
                +sim_image_restore_enable $(SIM_ARGS)
  CLEAN_FILES = $(SIMV) $(SIMV).daidir csrc ucli.key vc_hdrs.h AN.DB \
                $(CKPT_DIR)
  TOOL_CHECK  = true

else ifeq ($(SIM),xrun)
  XRUN     ?= $(XCELIUM_HOME)/tools/bin/xrun
  XLIB     ?= xcelium.d

  COMPILE_CMD = $(XRUN) -64bit -sv -uvm -uvmhome $(UVM_HOME) \
                -timescale 1ns/1ps -access +rwc -elaborate \
                -xmlibdirname $(XLIB) +define+NV_SR_XCELIUM \
                -top $(TOP) $(LIB_FILES) $(TB_FILES) $(XRUN_EXTRA)
  RUN_CMD     = $(XRUN) -64bit -R -xmlibdirname $(XLIB) $(SIM_ARGS)
  SAVE_CMD    = env XRUN_SNAP=$(CKPT_NAME) $(XRUN) -64bit -R \
                -xmlibdirname $(XLIB) -input $(COMMON_DIR)/xrun_save.tcl \
                $(SIM_ARGS) +sim_image_save_enable $(SR_FINISH)
  RESTORE_CMD = $(XRUN) -64bit -r $(CKPT_NAME) -xmlibdirname $(XLIB) \
                +sim_image_restore_enable $(SIM_ARGS)
  CLEAN_FILES = $(XLIB) xrun.history xrun.key .simvision waves.shm
  TOOL_CHECK  = test -n "$(UVM_HOME)" && test -x "$(XRUN)" || \
                { echo "SIM=xrun: set XCELIUM_HOME (or XRUN) and UVM_HOME"; exit 1; }

else
  $(error SIM must be vcs or xrun, got '$(SIM)')
endif

# $(call sim_run,<log name>,<plusargs>)
sim_run     = mkdir -p $(LOG_DIR) && $(RUN_CMD) $(2) -l $(LOG_DIR)/$(1)_$(SIM).log
# $(call sim_save,<log name>,<plusargs>): save at the test's save point
sim_save    = mkdir -p $(LOG_DIR) && $(SAVE_CMD) $(2) -l $(LOG_DIR)/$(1)_$(SIM).log
# $(call sim_restore,<log name>,<new plusargs>): restore $(CKPT_NAME)
sim_restore = mkdir -p $(LOG_DIR) && $(RESTORE_CMD) $(2) -l $(LOG_DIR)/$(1)_$(SIM).log

.PHONY: help compile clean

help:
	@awk '/^#/ {print; next} {exit}' $(firstword $(MAKEFILE_LIST))

compile:
	@$(TOOL_CHECK)
	mkdir -p $(LOG_DIR)
	$(COMPILE_CMD) -l $(LOG_DIR)/compile_$(SIM).log

clean:
	rm -rf $(CLEAN_FILES) $(LOG_DIR) *.log

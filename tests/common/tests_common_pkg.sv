// ============================================================================
// tests_common_pkg.sv -- components shared by the nv_socv_sim_restore tests.
//
//   phase_logger : logs every common and runtime phase it runs (with its
//                  domain), holds reset/main for reset_delay/main_delay ns
//   heartbeat    : run_phase loop without objections
//   jump_once    : one runtime phase jump out of main_phase
//   save_point   : request a sim image save (sim_save_restore.sv) and resume
//                  once the save point is passed
//   cl_expect    : compare an observed value with +EXP_<key>=<value>
//   cfg_agent    : phase_logger that takes main_delay (uvm_config_int) and
//                  profile (uvm_config_string) from uvm_config_db
// ============================================================================

`timescale 1ns/1ps

package tests_common_pkg;

  import uvm_pkg::*;
  import nv_socv_sim_restore_pkg::*;
  `include "uvm_macros.svh"

  // --------------------------------------------------------------------------
  // Save point. take() is a no-op without +sim_image_save_enable. In the save
  // run it returns right after the save (or the run ends there with
  // +sim_finish_after_save); a restored run resumes inside take() and
  // returns with restored() == 1.
  // --------------------------------------------------------------------------
  class save_point;
    static task automatic take(string where);
      uvm_event saved;
      if (!$test$plusargs("sim_image_save_enable"))
        return;
      saved = uvm_event_pool::get_global("sim_image_saved");
      `uvm_info("SAVEPT", $sformatf("save point %s: requesting a sim image save @%0t",
                where, $time), UVM_NONE)
      uvm_event_pool::get_global("sim_image_save").trigger();
      saved.wait_ptrigger();
      `uvm_info("SAVEPT", $sformatf("save point %s passed @%0t (%s)", where, $time,
                (restored() ? "restored run" : "save run")), UVM_NONE)
    endtask

    static function bit restored();
      return uvm_event_pool::get_global("sim_image_restored").is_on();
    endfunction
  endclass


  // --------------------------------------------------------------------------
  // Command-line expectations. check() compares <actual> with
  // +EXP_<key>=<value> of the current invocation (the restore command line
  // in a restored run): CL_EXPECT error on a mismatch, info on a match, and
  // only an info with the observed value without +EXP_<key>.
  // --------------------------------------------------------------------------
  class cl_expect;
    static int unsigned n_checked;
    static int unsigned n_failed;

    static function void check(string key, string actual, string where = "");
      string expected;
      string at = (where == "") ? "" : {" (", where, ")"};
      if (!$value$plusargs({"EXP_", key, "=%s"}, expected)) begin
        `uvm_info("CL_EXPECT", $sformatf("%s = %s%s @%0t", key, actual, at, $time), UVM_LOW)
        return;
      end
      n_checked++;
      if (actual != expected) begin
        n_failed++;
        `uvm_error("CL_EXPECT", $sformatf("%s = %s, expected %s%s @%0t",
                   key, actual, expected, at, $time))
      end
      else
        `uvm_info("CL_EXPECT", $sformatf("%s = %s as expected%s @%0t",
                  key, actual, at, $time), UVM_NONE)
    endfunction

    static function void check_int(string key, longint actual, string where = "");
      check(key, $sformatf("%0d", actual), where);
    endfunction

    static function void summary();
      `uvm_info("CL_EXPECT", $sformatf("%0d expectation(s) checked, %0d failed",
                n_checked, n_failed), UVM_NONE)
    endfunction
  endclass


  // --------------------------------------------------------------------------
  // Component that logs every common and runtime phase it runs.
  // --------------------------------------------------------------------------
  class phase_logger extends uvm_component;
    `uvm_component_utils(phase_logger)

    int unsigned reset_delay = 10;
    int unsigned main_delay  = 20;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void log(uvm_phase phase, string what = "");
      `uvm_info("PHASE", $sformatf("%-28s @%0t  domain=%s",
                {phase.get_name(), what}, $time,
                (get_domain() == null ? "<null>" : get_domain().get_name())),
                UVM_LOW)
    endfunction

    // Runtime phase ends of this logger's own domain: shows where the
    // domains end a phase together (synced) or alone.
    virtual function void phase_ended(uvm_phase phase);
      if (phase.get_domain() == get_domain() &&
          phase.get_name() inside {"pre_reset", "reset", "post_reset",
                                   "pre_configure", "configure", "post_configure",
                                   "pre_main", "main", "post_main",
                                   "pre_shutdown", "shutdown", "post_shutdown"})
        log(phase, " ENDED");
    endfunction

    virtual function void build_phase(uvm_phase phase);
      log(phase);
    endfunction
    virtual function void connect_phase(uvm_phase phase);
      log(phase);
    endfunction
    virtual function void end_of_elaboration_phase(uvm_phase phase);
      log(phase);
    endfunction
    virtual function void start_of_simulation_phase(uvm_phase phase);
      log(phase);
    endfunction

    virtual task run_phase(uvm_phase phase);
      log(phase);
    endtask

    virtual task pre_reset_phase(uvm_phase phase);
      log(phase);
    endtask
    virtual task reset_phase(uvm_phase phase);
      phase.raise_objection(this);
      log(phase, " (start)");
      #(reset_delay);
      log(phase, " (end)");
      phase.drop_objection(this);
    endtask
    virtual task post_reset_phase(uvm_phase phase);
      log(phase);
    endtask
    virtual task pre_configure_phase(uvm_phase phase);
      log(phase);
    endtask
    virtual task configure_phase(uvm_phase phase);
      log(phase);
    endtask
    virtual task post_configure_phase(uvm_phase phase);
      log(phase);
    endtask
    virtual task pre_main_phase(uvm_phase phase);
      log(phase);
    endtask
    virtual task main_phase(uvm_phase phase);
      phase.raise_objection(this);
      log(phase, " (start)");
      #(main_delay);
      log(phase, " (end)");
      phase.drop_objection(this);
    endtask
    virtual task post_main_phase(uvm_phase phase);
      log(phase);
    endtask
    virtual task pre_shutdown_phase(uvm_phase phase);
      log(phase);
    endtask
    virtual task shutdown_phase(uvm_phase phase);
      log(phase);
    endtask
    virtual task post_shutdown_phase(uvm_phase phase);
      log(phase);
    endtask

    virtual function void extract_phase(uvm_phase phase);
      log(phase);
    endfunction
    virtual function void check_phase(uvm_phase phase);
      log(phase);
    endfunction
    virtual function void report_phase(uvm_phase phase);
      log(phase);
    endfunction
    virtual function void final_phase(uvm_phase phase);
      log(phase);
    endfunction
  endclass


  // --------------------------------------------------------------------------
  // phase_logger configured from uvm_config_db, so +uvm_set_config_int /
  // +uvm_set_config_string and factory overrides can be checked on it.
  // --------------------------------------------------------------------------
  class cfg_agent extends phase_logger;
    `uvm_component_utils(cfg_agent)

    string profile = "default";

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      uvm_bitstream_t v;
      super.build_phase(phase);
      if (uvm_config_int::get(this, "", "main_delay", v))
        main_delay = v;
      void'(uvm_config_string::get(this, "", "profile", profile));
      `uvm_info("CFG", $sformatf("%s (%s) built @%0t: main_delay=%0d profile=%s",
                get_full_name(), get_type_name(), $time, main_delay, profile), UVM_LOW)
    endfunction
  endclass


  // --------------------------------------------------------------------------
  // run_phase loop without objections.
  // --------------------------------------------------------------------------
  class heartbeat extends uvm_component;
    `uvm_component_utils(heartbeat)

    int unsigned period = 25;
    int unsigned beats;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
      `uvm_info("BEAT", $sformatf("run_phase '%s' started @%0t",
                phase.get_name(), $time), UVM_LOW)
      forever begin
        #(period);
        beats++;
        `uvm_info("BEAT", $sformatf("beat %0d @%0t", beats, $time), UVM_HIGH)
      end
    endtask

    virtual function void report_phase(uvm_phase phase);
      `uvm_info("BEAT", $sformatf("%0d beats (report @%0t)", beats, $time),
                UVM_LOW)
    endfunction
  endclass


  // --------------------------------------------------------------------------
  // One-shot jump out of main_phase to the runtime phase jump_to, jump_at ns
  // into it. Empty jump_to: no jump.
  // --------------------------------------------------------------------------
  class jump_once;
    string       who;
    string       jump_to;
    int unsigned jump_at;
    bit          jumped;

    function new(string who, string jump_to, int unsigned jump_at);
      this.who     = who;
      this.jump_to = jump_to;
      this.jump_at = jump_at;
    endfunction

    task run(uvm_component c, uvm_phase phase);
      if (jump_to == "" || jumped)
        return;
      phase.raise_objection(c);
      #(jump_at);
      jumped = 1;
      `uvm_info("JUMP", $sformatf("%s test jumps %s -> %s @%0t", who,
                phase.get_name(), jump_to, $time), UVM_LOW)
      phase.jump(ps_runtime_imp(jump_to));
      phase.drop_objection(c);
    endtask
  endclass

endpackage

// ============================================================================
// test_pkg.sv -- Approach A: tests launched by run_test() after the boot.
//
//   dl_test_a (uvm_test_top)
//     env.drv : drives n_items words on dl_if after rst_n
//   dl_test_b (uvm_test_top), same checkpoint, different topology
//     env.drv : as dl_test_a
//     env.chk : counts the words on the pins, checks against env.drv
//
// Both tests publish "dl_mode" (+DL_MODE=<n>, default 1) in uvm_config_db
// from their build_phase; tb_top reads it from module code through
// nv_socv_config_db.
//
// Plusargs read here:
//   +DL_MODE=<n>                                      published dl_mode (1)
//   +uvm_set_config_int=uvm_test_top.env.drv,n_items,<n>   words driven (4)
// ============================================================================

`timescale 1ns/1ps

package test_pkg;

  import uvm_pkg::*;
  import nv_socv_sim_restore_pkg::*;
  import tests_common_pkg::*;
  `include "uvm_macros.svh"

  class dl_driver extends uvm_component;
    `uvm_component_utils(dl_driver)

    virtual dl_if    vif;
    uvm_bitstream_t  n_items = 4;
    int unsigned     n_sent;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      if (!uvm_config_db#(virtual dl_if)::get(this, "", "dl_vif", vif))
        `uvm_fatal("DRV", "dl_vif not set in uvm_config_db")
      void'(uvm_config_db#(uvm_bitstream_t)::get(this, "", "n_items", n_items));
      `uvm_info("DRV", $sformatf("built @%0t, n_items=%0d", $time, n_items), UVM_LOW)
    endfunction

    virtual task main_phase(uvm_phase phase);
      phase.raise_objection(this);
      wait (vif.rst_n === 1'b1);
      repeat (n_items) begin
        @(posedge vif.clk);
        vif.vld  <= 1'b1;
        vif.data <= 8'(n_sent);
        n_sent++;
      end
      @(posedge vif.clk);
      vif.vld <= 1'b0;
      `uvm_info("DRV", $sformatf("%0d words driven, done @%0t", n_sent, $time), UVM_LOW)
      phase.drop_objection(this);
    endtask
  endclass

  class dl_checker extends uvm_component;
    `uvm_component_utils(dl_checker)

    virtual dl_if vif;
    dl_driver     drv;
    int unsigned  n_seen;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      if (!uvm_config_db#(virtual dl_if)::get(this, "", "dl_vif", vif))
        `uvm_fatal("CHK", "dl_vif not set in uvm_config_db")
    endfunction

    virtual task run_phase(uvm_phase phase);
      forever begin
        @(posedge vif.clk);
        if (vif.vld === 1'b1)
          n_seen++;
      end
    endtask

    virtual function void check_phase(uvm_phase phase);
      if (n_seen != drv.n_sent)
        `uvm_error("CHK", $sformatf("%0d words on the pins, %0d driven", n_seen, drv.n_sent))
      else
        `uvm_info("CHK", $sformatf("%0d words on the pins, as driven", n_seen), UVM_LOW)
    endfunction
  endclass

  class dl_env extends uvm_env;
    `uvm_component_utils(dl_env)

    bit        has_checker;
    dl_driver  drv;
    dl_checker chk;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      drv = dl_driver::type_id::create("drv", this);
      if (has_checker)
        chk = dl_checker::type_id::create("chk", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
      if (chk != null)
        chk.drv = drv;
    endfunction
  endclass

  class dl_test_base extends uvm_test;
    `uvm_component_utils(dl_test_base)

    dl_env env;
    int    dl_mode = 1;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    virtual function void configure_env();
    endfunction

    virtual function void build_phase(uvm_phase phase);
      void'($value$plusargs("DL_MODE=%d", dl_mode));
      uvm_config_db#(int)::set(null, "*", "dl_mode", dl_mode);
      env = dl_env::type_id::create("env", this);
      configure_env();
      `uvm_info("TEST", $sformatf("%s built @%0t (%s), dl_mode=%0d",
                get_type_name(), $time,
                (save_point::restored() ? "restored run" : "fresh run"), dl_mode),
                UVM_NONE)
    endfunction

    virtual function void end_of_elaboration_phase(uvm_phase phase);
      uvm_root::get().print_topology();
    endfunction
  endclass

  class dl_test_a extends dl_test_base;
    `uvm_component_utils(dl_test_a)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
  endclass

  class dl_test_b extends dl_test_base;
    `uvm_component_utils(dl_test_b)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    virtual function void configure_env();
      env.has_checker = 1;
    endfunction
  endclass

endpackage

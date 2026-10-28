// SPDX-FileCopyrightText: Copyright (c) 2024-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
/**
 * @file nv_socv_sim_restore_pkg.sv
 * @brief Package and top-level includes for SOCV save/restore SV support.
 *
 * @details
 * The package contains the reusable SV classes used by the save/restore flow:
 *
 * - `nv_socv_cmdline_processor` refreshes UVM command-line state on restore.
 * - `nv_socv_delayed_test_launch` gates `run_test()` until boot or restore
 *   readiness, and also defines `nv_socv_config_db#(T)`, a `uvm_config_db#(T)`
 *   drop-in so call sites outside UVM phasing (module code, etc.) can wait
 *   for that same gate before reading config_db state.
 * - `nv_socv_pre_domain.sv` (`install_pre_domain()`, `pd_release_main()`): a pre
 *   test in its own domain; the main test is built when the pre test releases it.
 * - `nv_socv_post_domain.sv` (`install_post_domain()`,
 *   `install_post_domain_by_type()`, `pd_release_post()`,
 *   `pd_wait_post_started()`): a post test in its own domain, built at release
 *   during the main test, runtime phases synced with the main test.
 *   Both reprocess the command line before a build that starts at non-zero time
 *   (`nv_socv_cmdline_processor::refresh_cmdline_for_late_build()`).
 *
 */
package nv_socv_sim_restore_pkg;
    timeunit 1fs;
    timeprecision 1fs;
    import uvm_pkg::*;

    `include "nv_socv_cmdline_processor.sv"
    `include "nv_socv_delayed_test_launch.sv"
    `include "nv_socv_pre_domain.sv"
    `include "nv_socv_post_domain.sv"
endpackage: nv_socv_sim_restore_pkg

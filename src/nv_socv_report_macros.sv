`ifndef NV_SOCV_REPORT_MACROS_SV
`define NV_SOCV_REPORT_MACROS_SV

/**
 * @file nv_socv_report_macros.sv
 * @brief Provides UVM report helper macros for SOCV simulation restore code.
 *
 * @details
 * These macros route reports through the global `uvm_root` instance and attach
 * the macro call-site file and line number to simplify debug triage.
 *
 * SOCV simulation restore code can emit diagnostics before `run_test()` is
 * called. At that point, normal UVM phase execution has not started and the
 * standard `uvm_info`, `uvm_warning`, and `uvm_fatal` reporting macros may not
 * be readily usable from this early bootstrap context. Calling the corresponding
 * `uvm_root` report methods directly keeps early restore diagnostics available
 * while preserving UVM report formatting, severity handling, and file/line
 * attribution.
 *
 * Expected usage is limited to save/restore infrastructure code that may run
 * before normal UVM component context exists, such as command-line refresh,
 * delayed launch, and early save-context setup. Testbench and test code that is
 * already inside normal UVM phases should continue to use the standard UVM
 * reporting macros.
 */
import uvm_pkg::*;

/**
 * @def nv_uvm_info(ID, MSG, VERBOSITY)
 * @brief Issues a UVM info report with call-site file and line attribution.
 *
 * @param ID Report identifier string.
 * @param MSG Report message string.
 * @param VERBOSITY UVM verbosity level used to gate the report.
 */
`define nv_uvm_info(ID, MSG, VERBOSITY) uvm_root::get().uvm_report_info(ID, MSG, VERBOSITY, `__FILE__, `__LINE__);

/**
 * @def nv_uvm_warning(ID, MSG)
 * @brief Issues a UVM warning report with call-site file and line attribution.
 *
 * @param ID Report identifier string.
 * @param MSG Report message string.
 */
`define nv_uvm_warning(ID, MSG) uvm_root::get().uvm_report_warning(ID, MSG, UVM_NONE, `__FILE__, `__LINE__);

/**
 * @def nv_uvm_fatal(ID, MSG)
 * @brief Issues a UVM fatal report with call-site file and line attribution.
 *
 * @param ID Report identifier string.
 * @param MSG Report message string.
 */
`define nv_uvm_fatal(ID, MSG) uvm_root::get().uvm_report_fatal(ID, MSG, UVM_NONE, `__FILE__, `__LINE__);

`endif
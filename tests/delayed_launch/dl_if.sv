`timescale 1ns/1ps

interface dl_if (input bit clk);
  logic       rst_n;
  logic       vld;
  logic [7:0] data;
endinterface

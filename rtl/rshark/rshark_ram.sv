// R-Shark MiSTer core -- inferred block RAM primitives (Cyclone V M10K).
// SPDX-License-Identifier: GPL-3.0-or-later

// Port A read/write, port B read-only; registered outputs (1 clock latency).
module rshark_dpram #(
    parameter int AW = 10,
    parameter int DW = 8,
    parameter INIT = ""
) (
    input  logic          clk,
    input  logic [AW-1:0] a_addr,
    input  logic          a_we,
    input  logic [DW-1:0] a_din,
    output logic [DW-1:0] a_dout,
    input  logic [AW-1:0] b_addr,
    output logic [DW-1:0] b_dout
);
    logic [DW-1:0] mem [0:(1<<AW)-1];
    initial if (INIT != "") $readmemh(INIT, mem);
    always @(posedge clk) begin
        if (a_we) mem[a_addr] <= a_din;
        a_dout <= mem[a_addr];
    end
    always @(posedge clk) b_dout <= mem[b_addr];
endmodule

// One write port, one read port (simple dual port); registered read.
module rshark_sdpram #(
    parameter int AW = 10,
    parameter int DW = 8,
    parameter INIT = ""
) (
    input  logic          clk,
    input  logic [AW-1:0] w_addr,
    input  logic          we,
    input  logic [DW-1:0] din,
    input  logic [AW-1:0] r_addr,
    output logic [DW-1:0] dout
);
    logic [DW-1:0] mem [0:(1<<AW)-1];
    initial if (INIT != "") $readmemh(INIT, mem);
    always @(posedge clk) begin
        if (we) mem[w_addr] <= din;
        dout <= mem[r_addr];
    end
endmodule

// 16-bit single-port RAM with byte lanes (two 8-bit RAMs).
module rshark_spram16 #(
    parameter int AW = 10
) (
    input  logic          clk,
    input  logic [AW-1:0] addr,
    input  logic  [1:0]   we,       // [1] = bits 15-8, [0] = bits 7-0
    input  logic [15:0]   din,
    output logic [15:0]   dout
);
    logic [7:0] hi [0:(1<<AW)-1];
    logic [7:0] lo [0:(1<<AW)-1];
    always @(posedge clk) begin
        if (we[1]) hi[addr] <= din[15:8];
        if (we[0]) lo[addr] <= din[7:0];
        dout <= {hi[addr], lo[addr]};
    end
endmodule

// Simple dual-port RAM with separate write and read clocks; registered read.
module rshark_dcram #(
    parameter int AW = 10,
    parameter int DW = 8,
    parameter INIT = ""
) (
    input  logic          wclk,
    input  logic [AW-1:0] w_addr,
    input  logic          we,
    input  logic [DW-1:0] din,
    input  logic          rclk,
    input  logic [AW-1:0] r_addr,
    output logic [DW-1:0] dout
);
    logic [DW-1:0] mem [0:(1<<AW)-1];
    initial if (INIT != "") $readmemh(INIT, mem);
    always @(posedge wclk) if (we) mem[w_addr] <= din;
    always @(posedge rclk) dout <= mem[r_addr];
endmodule

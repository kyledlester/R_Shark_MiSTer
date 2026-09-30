// M6: inputs and DIP switches as the 68000 sees them.
// Drives MiSTer joystick bits and an MRA DIP download (ioctl index 254) into rshark_core and checks
// the values presented on the 68000 read ports (rshark_main's dsw / p1p2 / system inputs) against
// MAME's port definitions (dooyongm68_generic, all active low):
//   P1_P2 bit 0 right, 1 left, 2 down, 3 up, 4-7 buttons 1-4 (P1); bits 8-15 P2
//   SYSTEM bit 0 coin 1, 1 start 1, 2 coin 2, 3 start 2, 4 service, 5-7 = 1
`timescale 1ns/1ps
module m6_inputs_tb;
    logic clk = 0, clk_snd = 0;
    always #5.298 clk = ~clk;
    always @(posedge clk) clk_snd <= ~clk_snd;
    logic [31:0] joy0 = 0, joy1 = 0;
    logic ioctl_download = 0, ioctl_wr = 0; logic [15:0] ioctl_index = 0; logic [26:0] ioctl_addr = 0;
    logic [15:0] ioctl_dout = 0; logic ioctl_wait;
    logic [63:0] sd_dout = '0;

    rshark_core dut (
        .clk(clk), .clk_snd(clk_snd), .init(1'b1), .reset(1'b1), .pause(1'b0),
        .ioctl_download(ioctl_download), .ioctl_index(ioctl_index), .ioctl_wr(ioctl_wr),
        .ioctl_addr(ioctl_addr), .ioctl_dout(ioctl_dout), .ioctl_wait(ioctl_wait),
        .sd_addr(), .sd_din(), .sd_be(), .sd_req(), .sd_rnw(), .sd_dout(sd_dout), .sd_ready(1'b0),
        .joy0(joy0), .joy1(joy1), .test_pattern(1'b0), .dbg_overlay(1'b0),
        .ce_pix(), .rgb(), .hblank(), .vblank(), .hsync(), .vsync(), .snd());

    int errors = 0, checks = 0;
    task automatic expect16(input string what, input logic [15:0] got, input logic [15:0] exp);
        checks++;
        if (got !== exp) begin errors++; $display("MISMATCH %s: got %04x expected %04x", what, got, exp); end
    endtask

    initial begin
        #100;
        expect16("idle P1_P2", dut.p1p2, 16'hFFFF);
        expect16("idle SYSTEM", {8'h00, dut.system}, 16'h00FF);
        expect16("default DSW", dut.dsw, 16'hFFFF);
        // each MiSTer bit alone
        for (int b = 0; b < 8; b++) begin
            joy0 = 32'd1 << b; #20; expect16($sformatf("P1 bit %0d", b), dut.p1p2, ~(16'd1 << b));
            joy0 = 0; joy1 = 32'd1 << b; #20; expect16($sformatf("P2 bit %0d", b), dut.p1p2, ~(16'd1 << (b + 8)));
            joy1 = 0;
        end
        joy0 = 32'd1 << 9;  #20; expect16("coin 1",  {8'h00, dut.system}, 16'h00FE);
        joy0 = 32'd1 << 8;  #20; expect16("start 1", {8'h00, dut.system}, 16'h00FD);
        joy0 = 0; joy1 = 32'd1 << 9; #20; expect16("coin 2",  {8'h00, dut.system}, 16'h00FB);
        joy1 = 32'd1 << 8;  #20; expect16("start 2", {8'h00, dut.system}, 16'h00F7);
        joy1 = 32'd1 << 10; #20; expect16("service (P2)", {8'h00, dut.system}, 16'h00EF);
        joy1 = 0; joy0 = 32'd1 << 10; #20; expect16("service (P1)", {8'h00, dut.system}, 16'h00EF);
        joy0 = 32'd1 << 11; #20; expect16("pause is not a game input", {8'h00, dut.system}, 16'h00FF);
        joy0 = 0;
        // MRA DIP download: bytes SWA, SWB -> ioctl word at address 0 (WIDE)
        @(posedge clk); ioctl_download <= 1; ioctl_index <= 16'd254; ioctl_addr <= 0; ioctl_dout <= 16'h7EF3; ioctl_wr <= 1;
        @(posedge clk); ioctl_wr <= 0; @(posedge clk); ioctl_download <= 0;
        #20; expect16("DSW after download", dut.dsw, 16'h7EF3);
        if (errors == 0) $display("PASS M6_INPUTS: %0d checks", checks);
        else $display("FAIL M6_INPUTS: %0d/%0d checks failed", errors, checks);
        $finish;
    end
endmodule

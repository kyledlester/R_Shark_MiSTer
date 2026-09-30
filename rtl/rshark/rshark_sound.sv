// R-Shark MiSTer core -- Z80 sound board.
// SPDX-License-Identifier: GPL-3.0-or-later
//
// MAME 0.289 dooyong_state::bluehawk_sound_map + sound_2151 (docs/AUDIO.md):
//   Z80 (T80s) at 4 MHz: 0000-EFFF ROM (rse3), F000-F7FF RAM, F800 R sound latch,
//   F808-F809 YM2151, F80A OKI M6295. YM2151 IRQ -> Z80 INT (the program runs IM 1). No NMI.
//   YM2151 (jt51) clock 4 MHz; OKI M6295 (jt6295) clock 1 MHz, pin 7 high (divider 132 = 7.576 kHz).
// Mono mix as MAME: YM left and right x 0.35 each + OKI x 0.42 (MAME scales OKI's 12-bit voices to
// full range: x16 against the YM's 16-bit scale), saturated to 16 bits like MAME's output.
//
// Clocking: the board runs on clk_snd = clk_sys / 2 (same PLL, phase aligned: all crossings are
// synchronous and timing-analysed). ce_4m is an exact-average fractional 4 MHz enable of clk_snd
// (4,000,000 / 47,185,920), ce_1m = ce_4m / 4. The download port and the OKI SDRAM client stay in
// the clk_sys domain (dual-clock ROM, level handshake for OKI reads).
module rshark_sound #(
    parameter int CE_NUM = 4_000_000,     // ce_4m = CE_NUM / CE_DEN of clk_snd
    parameter int CE_DEN = 47_185_920
) (
    input  logic        clk,            // clk_sys: download, OKI SDRAM port, audio output
    input  logic        clk_snd,        // sound board clock
    input  logic        reset,          // clk_sys domain
    input  logic        pause,          // clk_sys domain

    input  logic  [7:0] latch,

    // Z80 program download
    input  logic        rom_we,
    input  logic [15:0] rom_waddr,
    input  logic  [7:0] rom_wdata,

    // OKI sample ROM (SDRAM word reads through rshark_sdram_arb, 4-word bursts)
    output logic        oki_req,
    output logic [25:1] oki_addr,
    input  logic        oki_ack,
    input  logic [63:0] oki_data,

    output logic signed [15:0] snd,

    output logic [15:0] dbg_latch_reads,
    output logic [15:0] dbg_ym_writes,
    output logic [15:0] dbg_oki_writes,
    output logic [15:0] dbg_z80_irqs
);
    // ------------------------------------------------------------------ clk_snd domain basics
    // Reset is synchronised and stretched to 4096 clk_snd (> 300 ce_4m): jt51's shift-register
    // pipelines only take their reset value if reset spans as many enabled clocks as they have
    // stages (jt51_sh.v), so the enables keep running during reset.
    logic [1:0]  rst_s = 2'b11, pause_s = 2'b00;
    logic [11:0] rst_cnt = '1;
    logic        rst = 1'b1;
    always_ff @(posedge clk_snd) begin
        rst_s   <= {rst_s[0], reset};
        pause_s <= {pause_s[0], pause};
        if (rst_s[1]) rst_cnt <= '1;
        else if (rst_cnt != 0) rst_cnt <= rst_cnt - 12'd1;
        rst <= rst_s[1] || rst_cnt != 0;
    end

    logic [26:0] acc4 = '0;
    logic [1:0]  q = '0;
    logic        ce_4m, ce_1m;
    always_ff @(posedge clk_snd) begin
        ce_4m <= 1'b0;
        ce_1m <= 1'b0;
        if (!pause_s[1] || rst) begin
            if (acc4 + 27'(CE_NUM) >= 27'(CE_DEN)) begin
                acc4  <= acc4 + 27'(CE_NUM) - 27'(CE_DEN);
                ce_4m <= 1'b1;
                q     <= q + 2'd1;
                ce_1m <= q == 2'd3;
            end else
                acc4 <= acc4 + 27'(CE_NUM);
        end
    end

    logic [7:0] latch_s;
    always_ff @(posedge clk_snd) latch_s <= latch;     // written rarely; related clocks

    // ------------------------------------------------------------------ Z80
    logic        mreq_n, iorq_n, rd_n, wr_n, m1_n, rfsh_n;
    logic [15:0] A;
    logic  [7:0] cpu_di, cpu_do;
    logic        irq_n;

    T80s #(.Mode(0), .T2Write(1), .IOWait(1)) z80 (
        .RESET_n(!rst), .CLK(clk_snd), .CEN(ce_4m), .WAIT_n(1'b1), .INT_n(irq_n), .NMI_n(1'b1),
        .BUSRQ_n(1'b1), .M1_n(m1_n), .MREQ_n(mreq_n), .IORQ_n(iorq_n), .RD_n(rd_n), .WR_n(wr_n),
        .RFSH_n(rfsh_n), .HALT_n(), .BUSAK_n(), .OUT0(1'b0), .A(A), .DI(cpu_di), .DO(cpu_do));

    wire mem   = !mreq_n && rfsh_n;
    wire sel_rom = mem && A < 16'hF000;
    wire sel_ram = mem && A[15:11] == 5'b11110;
    wire sel_lat = mem && A == 16'hF800;
    wire sel_ym  = mem && A[15:1] == 15'h7C04;          // F808-F809
    wire sel_oki = mem && A == 16'hF80A;

    logic [7:0] rom_q, ram_q;
    rshark_dcram #(.AW(16), .DW(8)
`ifdef RSHARK_SIM_Z80ROM
        , .INIT(`RSHARK_SIM_Z80ROM)
`endif
    ) rom (.wclk(clk), .w_addr(rom_waddr), .we(rom_we), .din(rom_wdata),
           .rclk(clk_snd), .r_addr(A), .dout(rom_q));

    // one write strobe per Z80 write cycle
    logic wr_n_d;
    always_ff @(posedge clk_snd) wr_n_d <= wr_n;
    wire wr_edge = wr_n_d && !wr_n;

    rshark_dpram #(.AW(11), .DW(8)) ram (
        .clk(clk_snd), .a_addr(A[10:0]), .a_we(sel_ram && wr_edge), .a_din(cpu_do), .a_dout(ram_q),
        .b_addr(11'd0), .b_dout());

    // ------------------------------------------------------------------ YM2151
    logic [7:0] ym_dout;
    logic signed [15:0] ym_l, ym_r;
    logic ym_sample;
    logic ce_2m;
    always_ff @(posedge clk_snd) begin
        if (rst) ce_2m <= 1'b0;
        else if (ce_4m) ce_2m <= !ce_2m;
    end
    wire cen_p1 = ce_4m && ce_2m;

    jt51 ym (
        .rst(rst), .clk(clk_snd), .cen(ce_4m), .cen_p1(cen_p1),
        .cs_n(!(sel_ym && (wr_edge || !rd_n))), .wr_n(!(sel_ym && wr_edge)), .a0(A[0]),
        .din(cpu_do), .dout(ym_dout), .ct1(), .ct2(), .irq_n(irq_n),
        .sample(ym_sample), .left(), .right(), .xleft(ym_l), .xright(ym_r));

    // ------------------------------------------------------------------ OKI M6295
    logic [7:0]  oki_dout;
    logic [17:0] oki_rom_addr;
    logic [7:0]  oki_rom_data;
    logic        oki_rom_ok;
    logic signed [13:0] oki_snd;
    jt6295 #(.INTERPOL(0)) oki (
        .rst(rst), .clk(clk_snd), .cen(ce_1m), .ss(1'b1),
        .wrn(!(sel_oki && !wr_n)), .din(cpu_do), .dout(oki_dout),
        .rom_addr(oki_rom_addr), .rom_data(oki_rom_data), .rom_ok(oki_rom_ok),
        .sound(oki_snd), .sample());

    // 8-byte line cache in front of SDRAM (OKI region at SDRAM byte 0x800000, bytes little-endian
    // within each word: byte address k -> word k/2, byte k&1). Crossing to the clk_sys SDRAM port by
    // a level handshake: clk_snd raises fill_rq with fill_tag; clk_sys performs the burst, stores it
    // in fill_data and raises fill_done; clk_snd takes the line and drops fill_rq; clk_sys drops
    // fill_done.
    logic [14:0] line_tag, fill_tag;
    logic        line_valid;
    logic [63:0] line_data, fill_data;
    logic        fill_rq, fill_done;
    wire hit = line_valid && line_tag == oki_rom_addr[17:3];
    always_ff @(posedge clk_snd) begin
        if (rst) begin
            line_valid <= 1'b0;
            fill_rq    <= 1'b0;
        end else if (fill_rq) begin
            if (fill_done) begin
                fill_rq    <= 1'b0;
                line_data  <= fill_data;
                line_tag   <= fill_tag;
                line_valid <= 1'b1;
            end
        end else if (!hit && !fill_done) begin
            fill_rq  <= 1'b1;
            fill_tag <= oki_rom_addr[17:3];
        end
    end
    always_ff @(posedge clk) begin
        if (reset) begin
            oki_req   <= 1'b0;
            fill_done <= 1'b0;
        end else if (!fill_rq) begin
            fill_done <= 1'b0;
        end else if (!fill_done) begin
            if (!oki_req) begin
                oki_req  <= 1'b1;
                oki_addr <= 25'h400000 + {8'd0, fill_tag, 2'b00};
            end else if (oki_ack) begin
                oki_req   <= 1'b0;
                fill_data <= oki_data;
                fill_done <= 1'b1;
            end
        end
    end
    assign oki_rom_ok   = hit;
    assign oki_rom_data = line_data[oki_rom_addr[2:0]*8 +: 8];

    // ------------------------------------------------------------------ CPU read mux
    always_comb begin
        cpu_di = 8'h00;                                 // MAME unmapped read value
        if (sel_rom)      cpu_di = rom_q;
        else if (sel_ram) cpu_di = ram_q;
        else if (sel_lat) cpu_di = latch_s;
        else if (sel_ym)  cpu_di = ym_dout;
        else if (sel_oki) cpu_di = oki_dout;
        else if (!iorq_n && !m1_n) cpu_di = 8'hFF;      // IM 1 acknowledge (bus floats high)
    end

    // ------------------------------------------------------------------ mix (clk_snd), output (clk)
    logic signed [15:0] snd_s;
    always_ff @(posedge clk) snd <= snd_s;
    always_ff @(posedge clk_snd) begin
        logic signed [23:0] acc;
        acc = (($signed(ym_l) + $signed(ym_r)) * 24'sd45 + $signed(oki_snd) * 24'sd860) >>> 7;
        if (acc > 24'sd32767) snd_s <= 16'sd32767;
        else if (acc < -24'sd32768) snd_s <= -16'sd32768;
        else snd_s <= acc[15:0];
    end

    // ------------------------------------------------------------------ debug counters
    logic irq_n_d;
    logic rd_n_d;
    always_ff @(posedge clk_snd) begin
        irq_n_d <= irq_n;
        rd_n_d  <= rd_n;
        if (rst) begin
            dbg_latch_reads <= '0; dbg_ym_writes <= '0; dbg_oki_writes <= '0; dbg_z80_irqs <= '0;
        end else begin
            if (sel_lat && rd_n_d && !rd_n) dbg_latch_reads <= dbg_latch_reads + 16'd1;
            if (sel_ym && wr_edge) dbg_ym_writes <= dbg_ym_writes + 16'd1;
            if (sel_oki && wr_edge) dbg_oki_writes <= dbg_oki_writes + 16'd1;
            if (irq_n_d && !irq_n) dbg_z80_irqs <= dbg_z80_irqs + 16'd1;
        end
    end
endmodule

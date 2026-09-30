// R-Shark MiSTer core -- board top.
// SPDX-License-Identifier: GPL-3.0-or-later
//
// docs/ARCHITECTURE.md. Everything runs on clk_sys (94.371840 MHz) with clock enables:
//   rshark_clocks  -> ce_pix 7.864320 MHz, FX68K phi1/phi2 (8 MHz), 4 MHz (Z80/YM2151), 1 MHz (OKI)
//   rshark_video_timing -> 512 x 256 raster; IRQ6 at line 120, IRQ5 + sprite copy + tilemap
//                          register latch at line 248 (MAME dooyong_68k_state::scanline)
//   rshark_loader  -> ROM stream to BRAM / SDRAM          rshark_main  -> 68000 board
//   rshark_video   -> tilemaps, sprites, palette, mixer   rshark_sound -> Z80, YM2151, OKI
//   rshark_sdram_arb -> SDRAM channel 1 (loader > OKI > tilemaps > sprites)
module rshark_core (
    input  logic        clk,
    input  logic        init,
    input  logic        reset,
    input  logic        pause,

    input  logic        ioctl_download,
    input  logic [15:0] ioctl_index,
    input  logic        ioctl_wr,
    input  logic [26:0] ioctl_addr,
    input  logic [15:0] ioctl_dout,
    output logic        ioctl_wait,

    output logic [26:1] sd_addr,
    output logic [15:0] sd_din,
    output logic  [1:0] sd_be,
    output logic        sd_req,
    output logic        sd_rnw,
    input  logic [63:0] sd_dout,
    input  logic        sd_ready,

    input  logic [31:0] joy0,
    input  logic [31:0] joy1,
    input  logic        test_pattern,
    input  logic        dbg_overlay,

    output logic        ce_pix,
    output logic [23:0] rgb,
    output logic        hblank,
    output logic        vblank,
    output logic        hsync,
    output logic        vsync,
    output logic signed [15:0] snd
);
    // ------------------------------------------------------------------ clocks / raster
    logic tick16, phi1, phi2, ce_4m, ce_1m;
    rshark_clocks clocks (
        .clk(clk), .rst(reset), .rst_video(init), .pause(pause),
        .ce_pix(ce_pix), .tick16(tick16), .phi1(phi1), .phi2(phi2), .ce_4m(ce_4m), .ce_1m(ce_1m));

    logic [8:0] hcount;
    logic [7:0] vcount;
    logic hb, vb, hs, vs, line_start;
    rshark_video_timing timing (
        .clk(clk), .rst(init), .ce_pix(ce_pix),
        .hcount(hcount), .vcount(vcount), .hblank(hb), .vblank(vb), .hsync(hs), .vsync(vs),
        .line_start(line_start));

    // interrupts / vblank work are part of emulated time: frozen while paused
    wire irq5_evt = line_start && vcount == 8'd248 && !pause;
    wire irq6_evt = line_start && vcount == 8'd120 && !pause;

    // ------------------------------------------------------------------ DIP switches (index 254)
    logic [15:0] dsw = 16'hFFFF;
    always_ff @(posedge clk)
        if (ioctl_download && ioctl_wr && ioctl_index == 16'd254 && ioctl_addr[26:1] == 0)
            dsw <= ioctl_dout;

    // ------------------------------------------------------------------ inputs (MAME active low)
    // MiSTer joystick: 0 right, 1 left, 2 down, 3 up, 4-7 buttons 1-4, 8 start, 9 coin, 10 service
    wire [15:0] p1p2   = ~{joy1[7:0], joy0[7:0]};
    wire  [7:0] system = ~{3'b000, joy0[10] | joy1[10], joy1[8], joy1[9], joy0[8], joy0[9]};

    // ------------------------------------------------------------------ loader
    logic        ld_req, ld_ack;
    logic [25:1] ld_addr;
    logic [15:0] ld_wdata;
    logic        rom68_we, romz80_we;
    logic [16:0] rom68_addr;
    logic [15:0] rom68_data, romz80_addr;
    logic  [7:0] romz80_data;
    logic        loaded;
    rshark_loader loader (
        .clk(clk), .rst(init),
        .ioctl_download(ioctl_download), .ioctl_index(ioctl_index), .ioctl_wr(ioctl_wr),
        .ioctl_addr(ioctl_addr), .ioctl_dout(ioctl_dout), .ioctl_wait(ioctl_wait),
        .mem_req(ld_req), .mem_addr(ld_addr), .mem_wdata(ld_wdata), .mem_ack(ld_ack),
        .rom68_we(rom68_we), .rom68_addr(rom68_addr), .rom68_data(rom68_data),
        .romz80_we(romz80_we), .romz80_addr(romz80_addr), .romz80_data(romz80_data),
        .loaded(loaded));

    // ------------------------------------------------------------------ 68000 board
    logic [7:0]   latch, ctrl_byte;
    logic         latch_wr, flip, bg1_pri;
    logic [255:0] tm_regs;
    logic [1:0]   pal_we;
    logic [10:0]  pal_addr;
    logic [15:0]  pal_wdata;
    logic [7:0]   ytab_addr, atab_addr;
    logic [13:0]  ytab_data;
    logic [32:0]  atab_data;
    logic         spr_busy;
    logic [23:0]  dbg_pc;
    logic [15:0]  dbg_irq5, dbg_irq6, dbg_frames, dbg_latch;
    rshark_main main (
        .clk(clk), .reset(reset), .phi1(phi1), .phi2(phi2),
        .rom_we(rom68_we), .rom_waddr(rom68_addr), .rom_wdata(rom68_data),
        .irq5_evt(irq5_evt), .irq6_evt(irq6_evt), .vblank_evt(irq5_evt),
        .dsw(dsw), .p1p2(p1p2), .system(system),
        .snd_latch(latch), .snd_latch_wr(latch_wr), .flip(flip), .bg1_pri(bg1_pri), .ctrl_byte(ctrl_byte),
        .tm_regs(tm_regs), .pal_we(pal_we), .pal_addr(pal_addr), .pal_wdata(pal_wdata),
        .ytab_addr(ytab_addr), .ytab_data(ytab_data), .atab_addr(atab_addr), .atab_data(atab_data),
        .spr_copy_busy(spr_busy),
        .dbg_pc(dbg_pc), .dbg_irq5(dbg_irq5), .dbg_irq6(dbg_irq6), .dbg_frames(dbg_frames),
        .dbg_latch_writes(dbg_latch));

    // ------------------------------------------------------------------ video
    logic        tm_req, tm_ack, sp_req, sp_ack;
    logic [25:1] tm_addr, sp_addr;
    logic [63:0] mem_rdata;
    logic [23:0] vid_rgb;
    logic        vhb, vvb, vhs, vvs;
    logic [15:0] dbg_overruns;
    rshark_video video (
        .clk(clk), .rst(reset), .ce_pix(ce_pix), .hcount(hcount), .vcount(vcount), .line_start(line_start),
        .hblank_in(hb), .vblank_in(vb), .hsync_in(hs), .vsync_in(vs),
        .regs(tm_regs), .bg1_pri(bg1_pri),
        .pal_we(pal_we), .pal_addr(pal_addr), .pal_wdata(pal_wdata),
        .ytab_addr(ytab_addr), .ytab_data(ytab_data), .atab_addr(atab_addr), .atab_data(atab_data),
        .tm_req(tm_req), .tm_addr(tm_addr), .tm_ack(tm_ack),
        .sp_req(sp_req), .sp_addr(sp_addr), .sp_ack(sp_ack), .mem_data(mem_rdata),
        .rgb(vid_rgb), .hblank(vhb), .vblank(vvb), .hsync(vhs), .vsync(vvs), .dbg_overruns(dbg_overruns));

    // ------------------------------------------------------------------ sound
    logic        oki_req, oki_ack;
    logic [25:1] oki_addr;
    logic [15:0] dbg_lat_rd, dbg_ym, dbg_oki, dbg_zirq;
    rshark_sound sound (
        .clk(clk), .reset(reset), .ce_4m(ce_4m), .ce_1m(ce_1m), .latch(latch),
        .rom_we(romz80_we), .rom_waddr(romz80_addr), .rom_wdata(romz80_data),
        .oki_req(oki_req), .oki_addr(oki_addr), .oki_ack(oki_ack), .oki_data(mem_rdata),
        .snd(snd),
        .dbg_latch_reads(dbg_lat_rd), .dbg_ym_writes(dbg_ym), .dbg_oki_writes(dbg_oki), .dbg_z80_irqs(dbg_zirq));

    // ------------------------------------------------------------------ SDRAM
    logic [3:0]  arb_ack;
    logic [25:1] arb_addr [4];
    assign arb_addr[0] = ld_addr;
    assign arb_addr[1] = oki_addr;
    assign arb_addr[2] = tm_addr;
    assign arb_addr[3] = sp_addr;
    rshark_sdram_arb arb (
        .clk(clk), .rst(init),
        .req({sp_req, tm_req, oki_req, ld_req}), .addr(arb_addr), .we(4'b0001),
        .wdata(ld_wdata), .wbe(2'b11), .ack(arb_ack), .rdata(mem_rdata),
        .sd_addr(sd_addr), .sd_din(sd_din), .sd_be(sd_be), .sd_req(sd_req), .sd_rnw(sd_rnw),
        .sd_dout(sd_dout), .sd_ready(sd_ready));
    assign ld_ack  = arb_ack[0];
    assign oki_ack = arb_ack[1];
    assign tm_ack  = arb_ack[2];
    assign sp_ack  = arb_ack[3];

    // ------------------------------------------------------------------ output (test pattern / debug overlay)
    logic [23:0] ovl_rgb;
    rshark_overlay overlay (
        .clk(clk), .ce_pix(ce_pix), .hcount(hcount), .vcount(vcount), .enable(dbg_overlay),
        .values('{ {8'h00, dbg_pc}, {dbg_frames, dbg_irq5}, {dbg_irq6, dbg_latch},
                   {dbg_lat_rd, dbg_zirq}, {dbg_ym, dbg_oki}, {dbg_overruns, 7'd0, loaded, ctrl_byte} }),
        .rgb_in(vid_rgb), .rgb_out(ovl_rgb));

    always_ff @(posedge clk) if (ce_pix) begin
        if (test_pattern) begin
            // 8 colour bars across the active width with a white border, raster timing unchanged
            if (hcount == 9'd65 || hcount == 9'd448 || vcount == 8'd8 || vcount == 8'd247)
                rgb <= 24'hFFFFFF;
            else begin
                logic [2:0] bar;
                bar = 3'((hcount - 9'd65) / 9'd48);
                rgb <= {{8{bar[2]}}, {8{bar[1]}}, {8{bar[0]}}};
            end
        end else
            rgb <= ovl_rgb;
        {hblank, vblank, hsync, vsync} <= {vhb, vvb, vhs, vvs};
    end
endmodule

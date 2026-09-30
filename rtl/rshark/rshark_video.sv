// R-Shark MiSTer core -- video: line renderers, line buffers, palette, output mixer.
// SPDX-License-Identifier: GPL-3.0-or-later
//
// docs/VIDEO.md. During raster line v the tilemap and sprite engines render line v+1 (8..247) into
// the line-buffer half selected by (v+1)[0]; the output side reads (and clears) half v[0].
// Output pixel: sprite {colour, pen} shown unless pen 15 or (colour 0/15 and the tile pixel has
// priority bit 1) - MAME prio_transpen with GFX_PMASK_4 | (colour 0/15 ? GFX_PMASK_2 : 0);
// otherwise the tile pixel, otherwise black. Palette xRGB_555 -> 8 bit (x<<3 | x>>2).
// Output is one dot late relative to the raster counters; blank/sync are delayed with it.
module rshark_video (
    input  logic         clk,
    input  logic         rst,
    input  logic         ce_pix,
    input  logic   [8:0] hcount,
    input  logic   [7:0] vcount,
    input  logic         line_start,
    input  logic         hblank_in,
    input  logic         vblank_in,
    input  logic         hsync_in,
    input  logic         vsync_in,

    input  logic [255:0] regs,
    input  logic         bg1_pri,

    // palette CPU write port
    input  logic   [1:0] pal_we,
    input  logic  [10:0] pal_addr,
    input  logic  [15:0] pal_wdata,

    // sprite tables (in rshark_main)
    output logic   [7:0] ytab_addr,
    input  logic  [13:0] ytab_data,
    output logic   [7:0] atab_addr,
    input  logic  [32:0] atab_data,

    // SDRAM clients (to rshark_sdram_arb)
    output logic         tm_req,
    output logic  [25:1] tm_addr,
    input  logic         tm_ack,
    output logic         sp_req,
    output logic  [25:1] sp_addr,
    input  logic         sp_ack,
    input  logic  [63:0] mem_data,

    output logic  [23:0] rgb,
    output logic         hblank,
    output logic         vblank,
    output logic         hsync,
    output logic         vsync,

    output logic  [15:0] dbg_overruns       // lines whose render had not finished in time
);
    // ------------------------------------------------------------------ render start
    wire [7:0] next_line = vcount + 8'd1;      // vcount is already the new line at line_start
    logic      render_start, render_pend, abort;
    logic [7:0] render_y;
    logic      tm_busy, sp_busy;

    // An engine still busy at the next line start is aborted (reset) one clock before it restarts.
    always_ff @(posedge clk) begin
        render_start <= 1'b0;
        abort        <= 1'b0;
        render_pend  <= 1'b0;
        if (rst) dbg_overruns <= '0;
        else begin
            if (line_start && next_line >= 8'd8 && next_line < 8'd248) begin
                if (tm_busy || sp_busy) begin
                    dbg_overruns <= dbg_overruns + 16'd1;
                    abort <= 1'b1;
                end
                render_pend <= 1'b1;
                render_y    <= next_line;
            end
            render_start <= render_pend;
        end
    end

    // ------------------------------------------------------------------ engines
    logic        tlb_we;
    logic [8:0]  tlb_x;
    logic [12:0] tlb_data;
    rshark_tilemap tilemap (
        .clk(clk), .rst(rst || abort), .start(render_start), .y(render_y),
        .regs(regs), .bg1_pri(bg1_pri), .busy(tm_busy),
        .mem_req(tm_req), .mem_addr(tm_addr), .mem_ack(tm_ack), .mem_data(mem_data),
        .lb_we(tlb_we), .lb_x(tlb_x), .lb_data(tlb_data));

    logic [1:0]  slb_we;
    logic [7:0]  slb_addr [2];
    logic [7:0]  slb_data [2];
    rshark_sprites sprites (
        .clk(clk), .rst(rst || abort), .start(render_start), .y(render_y), .busy(sp_busy),
        .ytab_addr(ytab_addr), .ytab_data(ytab_data), .atab_addr(atab_addr), .atab_data(atab_data),
        .mem_req(sp_req), .mem_addr(sp_addr), .mem_ack(sp_ack), .mem_data(mem_data),
        .lb_we(slb_we), .lb_addr(slb_addr), .lb_data(slb_data));

    // ------------------------------------------------------------------ line buffers
    // port A: output side (read, then clear), port B: renderer (write)
    wire        wr_half = render_y[0];
    wire        rd_half = vcount[0];
    logic [12:0] tq;
    logic [7:0]  sq [2];
    logic        clr;                 // clear the entry read one clock earlier
    logic [8:0]  rd_x;

    rshark_tdpram #(.AW(10), .DW(13)) tlb (
        .clk(clk),
        .a_addr({rd_half, rd_x}), .a_we(clr), .a_din(13'd0), .a_dout(tq),
        .b_addr({wr_half, tlb_x}), .b_we(tlb_we), .b_din(tlb_data));
    for (genvar b = 0; b < 2; b++) begin : slb_banks
        rshark_tdpram #(.AW(9), .DW(8), .FILL(8'hFF)) slb (
            .clk(clk),
            .a_addr({rd_half, rd_x[8:1]}), .a_we(clr && rd_x[0] == b[0]), .a_din(8'hFF), .a_dout(sq[b]),
            .b_addr({wr_half, slb_addr[b]}), .b_we(slb_we[b]), .b_din(slb_data[b]));
    end

    // ------------------------------------------------------------------ palette
    logic [10:0] pal_raddr;
    logic [15:0] pal_q;
    logic [7:0]  pal_hi_q, pal_lo_q;
    rshark_sdpram #(.AW(11), .DW(8)) pal_hi (
        .clk(clk), .w_addr(pal_addr), .we(pal_we[1]), .din(pal_wdata[15:8]), .r_addr(pal_raddr), .dout(pal_hi_q));
    rshark_sdpram #(.AW(11), .DW(8)) pal_lo (
        .clk(clk), .w_addr(pal_addr), .we(pal_we[0]), .din(pal_wdata[7:0]), .r_addr(pal_raddr), .dout(pal_lo_q));
    assign pal_q = {pal_hi_q, pal_lo_q};

    // ------------------------------------------------------------------ output pipeline
    // c0 (ce_pix): address = hcount; c1: line-buffer data, clear; c2: palette address; c3: colour.
    logic [3:0] ph;
    logic       vis_d1, vis_d2, black_d2;
    logic [23:0] rgb_next;
    logic       hb_d, vb_d, hs_d, vs_d;           // timing of the dot whose colour is in rgb_next

    function automatic [7:0] c5(input [4:0] x); c5 = {x, x[4:2]}; endfunction

    always_ff @(posedge clk) begin
        clr <= 1'b0;
        if (ce_pix) begin
            rd_x   <= hcount;
            ph     <= 4'd1;
            vis_d1 <= !hblank_in && !vblank_in;
            // present the colour computed for the previous dot, with the previous dot's timing
            rgb    <= rgb_next;
            {hblank, vblank, hsync, vsync} <= {hb_d, vb_d, hs_d, vs_d};
            {hb_d, vb_d, hs_d, vs_d} <= {hblank_in, vblank_in, hsync_in, vsync_in};
        end else if (ph != 0) begin
            ph <= ph + 4'd1;
            case (ph)
                4'd2: begin                          // line-buffer data valid for rd_x
                    logic [7:0] s;
                    logic       spr_vis;
                    s = sq[rd_x[0]];
                    spr_vis = s[3:0] != 4'hF && !((s[7:4] == 4'h0 || s[7:4] == 4'hF) && tq[11]);
                    pal_raddr <= spr_vis ? {3'b000, s} : tq[10:0];
                    black_d2  <= !spr_vis && !tq[12];
                    vis_d2    <= vis_d1;
                    clr       <= vis_d1;
                end
                4'd4: begin                          // palette data valid
                    rgb_next <= (!vis_d2 || black_d2) ? 24'h000000 :
                                {c5(pal_q[14:10]), c5(pal_q[9:5]), c5(pal_q[4:0])};
                    ph <= 4'd0;
                end
                default: ;
            endcase
        end
    end
endmodule

// True dual-port RAM: both ports read/write (used with disjoint halves), registered reads.
module rshark_tdpram #(
    parameter int AW = 9,
    parameter int DW = 8,
    parameter logic [DW-1:0] FILL = '0
) (
    input  logic          clk,
    input  logic [AW-1:0] a_addr,
    input  logic          a_we,
    input  logic [DW-1:0] a_din,
    output logic [DW-1:0] a_dout,
    input  logic [AW-1:0] b_addr,
    input  logic          b_we,
    input  logic [DW-1:0] b_din
);
    logic [DW-1:0] mem [0:(1<<AW)-1];
    initial for (int i = 0; i < (1 << AW); i++) mem[i] = FILL;
    always @(posedge clk) begin
        if (a_we) mem[a_addr] <= a_din;
        a_dout <= mem[a_addr];
    end
    always @(posedge clk) if (b_we) mem[b_addr] <= b_din;
endmodule

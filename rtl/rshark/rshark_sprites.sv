// R-Shark MiSTer core -- sprite line renderer.
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Hardware form of MAME 0.289 dooyong_68k_state::draw_sprites (docs/VIDEO.md). For render line y
// the 256 buffered entries are scanned in index order 0..255 (Y table, one entry per clock); for
// every entry covering the line, each of its (width+1) tiles contributes one 16-pixel row, written
// 2 pixels per clock into the even/odd banked sprite line buffer {colour, pen}. Later entries
// overwrite earlier ones, which reproduces MAME's "entry 255 drawn first, pri=31 blocks the rest"
// result (the colour 0/15 priority test is applied at output). Pixels at x >= 512 are dropped
// (MAME clips, no wrap).
// SDRAM: sprite tile rows at code*64 + row*4 words (docs/MRA_FORMAT.md), 4-word burst = 16 pixels,
// pixel p = nibble p of the row (high nibble first).
module rshark_sprites (
    input  logic        clk,
    input  logic        rst,
    input  logic        start,
    input  logic  [7:0] y,
    output logic        busy,

    output logic  [7:0] ytab_addr,      // combinational (registered read in the table RAM)
    input  logic [13:0] ytab_data,      // {en, h[3:0], y[8:0]}
    output logic  [7:0] atab_addr,
    input  logic [32:0] atab_data,      // {w[3:0], x[8:0], code[15:0], colour[3:0]}

    output logic        mem_req,
    output logic [25:1] mem_addr,
    input  logic        mem_ack,
    input  logic [63:0] mem_data,

    output logic  [1:0] lb_we,          // [0] even-x bank, [1] odd-x bank
    output logic  [7:0] lb_addr [2],    // x >> 1 per bank
    output logic  [7:0] lb_data [2]     // {colour, pen}
);
    typedef enum logic [2:0] {S_IDLE, S_SCAN, S_HIT, S_ATTR, S_FETCH, S_PUSH, S_WAITW} st_t;
    st_t st;

    logic [8:0]  scan;           // next Y-table address to present (256 = none left)
    logic [7:0]  pe;             // entry whose data is on ytab_data
    logic        pv;
    logic [7:0]  hit_dy;         // y - sprite y (0..255)
    logic [3:0]  sw;             // width - 1
    logic [8:0]  sx;
    logic [15:0] base_code;      // code + row * (width + 1)
    logic [3:0]  scol;
    logic [3:0]  scolour;

    assign ytab_addr = scan[7:0];

    // Y-table hit test: dy = (y - sign-extended Y) mod 1024; negative dy wraps above 511
    wire        en   = ytab_data[13];
    wire [3:0]  h    = ytab_data[12:9];
    wire [9:0]  dy   = {2'b00, y} - {ytab_data[8], ytab_data[8:0]};
    wire        hit  = en && dy < ({1'b0, h, 4'b0000} + 10'd16);

    // writer: 8 clocks per 16-pixel row
    logic        w_busy;
    logic [2:0]  w_cnt;
    logic [63:0] w_pix;
    logic [9:0]  w_x;            // bitmap x of pixel 0 (may exceed 511 -> dropped)
    logic [3:0]  w_colour;
    wire         w_load = st == S_PUSH && !w_busy;
    logic [63:0] pix_q;

    assign busy = st != S_IDLE || w_busy;

    always_ff @(posedge clk) begin
        if (rst) begin
            st <= S_IDLE;
            mem_req <= 1'b0;
            pv <= 1'b0;
            scan <= 9'd0;
        end else case (st)
            S_IDLE: if (start) begin
                scan <= 9'd0;
                pv   <= 1'b0;
                st   <= S_SCAN;
            end
            S_SCAN: begin
                if (pv && hit) begin
                    hit_dy    <= dy[7:0];
                    atab_addr <= pe;
                    pv        <= 1'b0;
                    scan      <= {1'b0, pe} + 9'd1;     // resume after this entry
                    st        <= S_HIT;
                end else if (scan[8]) begin
                    pv <= 1'b0;
                    st <= S_WAITW;
                end else begin
                    pe   <= scan[7:0];
                    pv   <= 1'b1;
                    scan <= scan + 9'd1;
                end
            end
            S_HIT: st <= S_ATTR;                         // atab read latency
            S_ATTR: begin
                sw        <= atab_data[32:29];
                sx        <= atab_data[28:20];
                base_code <= atab_data[19:4] + hit_dy[7:4] * ({1'b0, atab_data[32:29]} + 5'd1);
                scolour   <= atab_data[3:0];
                scol      <= 4'd0;
                st        <= S_FETCH;
            end
            S_FETCH: begin
                if (!mem_req) begin
                    logic [13:0] c;
                    logic [9:0]  x0;
                    c  = base_code[13:0] + scol;
                    x0 = {1'b0, sx} + {2'b00, scol, 4'b0000};
                    // tiles entirely outside bitmap x 64..449 (the visible area, and its flipped
                    // read window) are never shown: skip their fetch
                    if (x0 + 10'd15 < 10'd64 || x0 > 10'd449) begin
                        if (scol == sw) st <= S_SCAN;
                        else scol <= scol + 4'd1;
                    end else begin
                        mem_req  <= 1'b1;
                        mem_addr <= {5'b00000, c, hit_dy[3:0], 2'b00};
                    end
                end else if (mem_ack) begin
                    mem_req <= 1'b0;
                    st      <= S_PUSH;
                end
            end
            S_PUSH: if (!w_busy) begin
                if (scol == sw) st <= S_SCAN;
                else begin
                    scol <= scol + 4'd1;
                    st   <= S_FETCH;
                end
            end
            S_WAITW: if (!w_busy) st <= S_IDLE;
            default: st <= S_IDLE;
        endcase
    end

    always_ff @(posedge clk) if (st == S_FETCH && mem_ack) pix_q <= mem_data;

    always_ff @(posedge clk) begin
        lb_we <= 2'b00;
        if (rst) begin
            w_busy <= 1'b0;
        end else if (w_load) begin
            w_busy   <= 1'b1;
            w_cnt    <= 3'd0;
            w_pix    <= pix_q;
            w_x      <= {1'b0, sx} + {2'b00, scol, 4'b0000};
            w_colour <= scolour;
        end else if (w_busy) begin
            // pixels 2k and 2k+1: word k>>1, byte k&1 (high nibble = first pixel)
            logic [15:0] wd;
            logic [7:0]  b;
            logic [9:0]  xa, xb;
            logic [3:0]  pa, pb;
            wd = w_pix[w_cnt[2:1]*16 +: 16];
            b  = w_cnt[0] ? wd[7:0] : wd[15:8];
            pa = b[7:4];
            pb = b[3:0];
            xa = w_x + {6'd0, w_cnt, 1'b0};
            xb = xa + 10'd1;
            // xa and xb always fall in different banks
            lb_addr[xa[0]] <= xa[8:1];
            lb_data[xa[0]] <= {w_colour, pa};
            lb_addr[xb[0]] <= xb[8:1];
            lb_data[xb[0]] <= {w_colour, pb};
            lb_we[xa[0]]   <= !xa[9] && pa != 4'd15;
            lb_we[xb[0]]   <= !xb[9] && pb != 4'd15;
            w_cnt <= w_cnt + 3'd1;
            if (w_cnt == 3'd7) w_busy <= 1'b0;
        end
    end
endmodule

// R-Shark MiSTer core -- ROM tilemap line renderer (BG0, BG1, FG0, FG1).
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Hardware form of MAME 0.289 rshark_rom_tilemap_device (docs/VIDEO.md), one engine shared by the
// four layers. For render line y it draws, in order BG0, BG1, FG0, FG1, the 24-25 tile columns
// covering bitmap x 64..447 of each enabled layer into the tile line buffer:
//   entry {valid, pri, index[10:0]}: BG0 writes every pixel (pri 0), the others only pens != 15
//   (pri = 1 for FG0/FG1, and for BG1 when the control byte's bit 4 is set).
// SDRAM (docs/ROM_LAYOUT.md): map+colour at MAP_BASE[layer] + (row*4096 + column)*2 words, a
// 4-word burst returns columns 2k and 2k+1 {attr, colour, attr, colour}; tile pixel rows at
// GFX_BASE[layer] + code*64 + row*4 words, a burst = the 16 pixels of the row.
module rshark_tilemap (
    input  logic         clk,
    input  logic         rst,
    input  logic         start,         // begin rendering line y
    input  logic   [7:0] y,
    input  logic [255:0] regs,          // layer*64 + reg*8
    input  logic         bg1_pri,
    output logic         busy,

    output logic         mem_req,
    output logic  [25:1] mem_addr,
    input  logic         mem_ack,
    input  logic  [63:0] mem_data,

    output logic         lb_we,
    output logic   [8:0] lb_x,
    output logic  [12:0] lb_data
);
    localparam logic [25:1] GFX_BASE [4] = '{25'h100000, 25'h180000, 25'h200000, 25'h280000}; // byte 0x200000.. /2
    localparam logic [25:1] MAP_BASE [4] = '{25'h300000, 25'h340000, 25'h380000, 25'h3C0000}; // byte 0x600000.. /2
    localparam logic [10:0] PAL_BASE [4] = '{11'd1024, 11'd768, 11'd512, 11'd256};

    typedef enum logic [2:0] {S_IDLE, S_LAYER, S_MAP, S_MAPC1, S_MAPC2, S_PIX, S_PUSH, S_NEXT} st_t;
    st_t st;

    logic [1:0]  layer;
    logic [7:0]  r [8];
    always_comb for (int i = 0; i < 8; i++) r[i] = regs[layer*64 + i*8 +: 8];

    logic [8:0]  ty;             // (y + scrolly) & 511
    logic [5:0]  col;            // tilemap column (0..43)
    logic [5:0]  col_end;
    logic [11:0] gc;             // global column
    logic [31:0] pair;           // {attr, colour} of column gc (from the map burst)
    logic [63:0] map_q;
    logic        map_valid;
    logic [10:0] map_gc_pair;    // gc >> 1 held in map_q

    wire [8:0]  scrolly = {r[4][0], r[3]};
    wire [9:0]  tx0     = 10'd64 + r[0];
    wire [9:0]  txl     = 10'd447 + r[0];

    // Map cache: tilemap entries are ROM and a tile row serves 16 lines, so each layer keeps the
    // (up to 13) column-pair bursts of its current tile row, tagged {row, first pair}.
    logic [4:0]  ctag_row [4];
    logic [10:0] ctag_p0  [4];
    logic [15:0] cvalid   [4];
    logic [5:0]  c_raddr, c_waddr;
    logic        c_we;
    logic [63:0] c_q;
    rshark_sdpram #(.AW(6), .DW(64)) mcache (
        .clk(clk), .w_addr(c_waddr), .we(c_we), .din(mem_data), .r_addr(c_raddr), .dout(c_q));
    wire [10:0] p0_now = ({r[1], 4'b0000} + {6'd0, tx0[9:4]}) >> 1;
    wire [8:0]  ty_now = y + scrolly;
    wire [3:0]  ck     = 4'(gc[11:1] - ctag_p0[layer]);

    // pixel writer: 16 pixels, one per clock
    logic        w_busy;
    logic [4:0]  w_cnt;
    logic [63:0] w_pix;          // the 4 words of the row
    logic        w_flipx;
    logic [3:0]  w_col;          // colour
    logic [8:0]  w_x0;           // bitmap x of screen pixel 0 of this tile
    logic [1:0]  w_layer;
    logic        w_pri;
    wire         w_load;             // hand the fetched row to the writer (same clock as the FSM step)


    // tilemap attribute decoding for the column being fetched
    wire [15:0] attr   = gc[0] ? map_q[47:32] : map_q[15:0];
    wire [3:0]  colour = gc[0] ? map_q[51:48] : map_q[19:16];
    wire        alt    = r[6][5];                       // "lastday" format
    wire [12:0] code   = alt ? {3'b000, attr[15], attr[8:0]} : attr[12:0];
    wire        flipx  = alt ? attr[9]  : attr[14];
    wire        flipy  = alt ? attr[10] : attr[15];
    wire [3:0]  prow   = ty[3:0] ^ {4{flipy}};

    assign busy = st != S_IDLE || w_busy;
    assign w_load = st == S_PUSH && !w_busy;

    always_ff @(posedge clk) begin
        c_we <= 1'b0;
        if (rst) begin
            st <= S_IDLE;
            mem_req <= 1'b0;
            for (int i = 0; i < 4; i++) cvalid[i] <= '0;
        end else case (st)
            S_IDLE: if (start) begin
                layer <= 2'd0;
                st    <= S_LAYER;
            end
            S_LAYER: begin
                if (r[6][4]) begin                           // layer disabled
                    st <= S_NEXT;
                end else begin
                    ty        <= ty_now;
                    col       <= tx0[9:4];
                    if (ctag_row[layer] != ty_now[8:4] || ctag_p0[layer] != p0_now) begin
                        ctag_row[layer] <= ty_now[8:4];
                        ctag_p0[layer]  <= p0_now;
                        cvalid[layer]   <= '0;
                    end
                    col_end   <= txl[9:4];
                    gc        <= {r[1], 4'b0000} + tx0[9:4];
                    map_valid <= 1'b0;
                    st        <= S_MAP;
                end
            end
            S_MAP: begin
                if (map_valid && map_gc_pair == gc[11:1]) st <= S_PIX;
                else if (!mem_req && cvalid[layer][ck]) begin
                    c_raddr <= {layer, ck};
                    st      <= S_MAPC1;
                end else if (!mem_req) begin
                    mem_req  <= 1'b1;
                    mem_addr <= MAP_BASE[layer] + {ty[8:4], gc[11:1], 2'b00};
                end else if (mem_ack) begin
                    mem_req     <= 1'b0;
                    map_q       <= mem_data;
                    map_valid   <= 1'b1;
                    map_gc_pair <= gc[11:1];
                    c_we        <= 1'b1;
                    c_waddr     <= {layer, ck};
                    cvalid[layer][ck] <= 1'b1;
                    st          <= S_PIX;
                end
            end
            S_MAPC1: st <= S_MAPC2;                          // cache read latency
            S_MAPC2: begin
                map_q       <= c_q;
                map_valid   <= 1'b1;
                map_gc_pair <= gc[11:1];
                st          <= S_PIX;
            end
            S_PIX: begin
                if (!mem_req) begin
                    mem_req  <= 1'b1;
                    mem_addr <= GFX_BASE[layer] + {code, prow, 2'b00};
                end else if (mem_ack) begin
                    mem_req <= 1'b0;
                    st      <= S_PUSH;
                end
            end
            S_PUSH: if (!w_busy) begin
                if (col == col_end) st <= S_NEXT;
                else begin
                    col <= col + 6'd1;
                    gc  <= gc + 12'd1;
                    st  <= S_MAP;
                end
            end
            S_NEXT: if (!w_busy) begin
                if (layer == 2'd3) st <= S_IDLE;
                else begin
                    layer <= layer + 2'd1;
                    st    <= S_LAYER;
                end
            end
            default: st <= S_IDLE;
        endcase
    end

    // capture the pixel burst for the writer (mem_data is valid with mem_ack in S_PIX)
    logic [63:0] pix_q;
    always_ff @(posedge clk) if (st == S_PIX && mem_ack) pix_q <= mem_data;

    always_ff @(posedge clk) begin
        lb_we <= 1'b0;
        if (rst) begin
            w_busy <= 1'b0;
        end else if (w_load) begin
            w_busy  <= 1'b1;
            w_cnt   <= 5'd0;
            w_pix   <= pix_q;
            w_flipx <= flipx;
            w_col   <= colour;
            w_x0    <= {col, 4'b0000} - {1'b0, r[0]};
            w_layer <= layer;
            w_pri   <= (layer == 2'd1) ? bg1_pri : (layer != 2'd0);
        end else if (w_busy) begin
            logic [3:0]  tp;          // tile pixel
            logic [15:0] wd;
            logic [3:0]  pen;
            tp  = w_cnt[3:0] ^ {4{w_flipx}};
            wd  = w_pix[tp[3:2]*16 +: 16];
            pen = {wd[15 - tp[1:0]], wd[11 - tp[1:0]], wd[7 - tp[1:0]], wd[3 - tp[1:0]]};
            lb_x    <= w_x0 + w_cnt[3:0];
            lb_data <= {1'b1, w_pri, PAL_BASE[w_layer] + {w_col, pen}};
            lb_we   <= (w_layer == 2'd0) || (pen != 4'd15);
            w_cnt   <= w_cnt + 5'd1;
            if (w_cnt == 5'd15) w_busy <= 1'b0;
        end
    end
endmodule

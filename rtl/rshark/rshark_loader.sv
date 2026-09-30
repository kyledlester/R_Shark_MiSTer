// R-Shark MiSTer core -- ROM loader (ioctl index 0, hps_io WIDE=1).
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Stream layout and SDRAM image: docs/ROM_LAYOUT.md (scripts/romtool.py is the executable form;
// its SDRAM image is what this module writes, word for word).
//   000000-5FFFFF graphics words  -> SDRAM word (stream/2) with the in-tile row reorder
//   600000-6FFFFF tilemap words   -> SDRAM map area, entry (row*4096 + column)*2
//   700000-77FFFF tmap_hi bytes   -> SDRAM map area, entry*2 + 1 = {00, colour} (2 entries/word)
//   780000-7BFFFF OKI bytes       -> SDRAM 0x800000.. (the ioctl word as is: low byte = even byte)
//   7C0000-7FFFFF 68000 program   -> BRAM 128K x 16 (big-endian words)
//   800000-80FFFF Z80 program     -> BRAM 64K x 8 (2 bytes per ioctl word)
// ioctl_wait is held from ioctl_wr until every write of that word is done.
module rshark_loader (
    input  logic        clk,
    input  logic        rst,

    input  logic        ioctl_download,
    input  logic [15:0] ioctl_index,
    input  logic        ioctl_wr,
    input  logic [26:0] ioctl_addr,
    input  logic [15:0] ioctl_dout,
    output logic        ioctl_wait,

    output logic        mem_req,
    output logic [25:1] mem_addr,
    output logic [15:0] mem_wdata,
    input  logic        mem_ack,

    output logic        rom68_we,
    output logic [16:0] rom68_addr,
    output logic [15:0] rom68_data,
    output logic        romz80_we,
    output logic [15:0] romz80_addr,
    output logic  [7:0] romz80_data,

    output logic        loaded           // a complete stream has been received
);
    localparam logic [25:1] MAP_BASE [4] = '{25'h300000, 25'h340000, 25'h380000, 25'h3C0000};

    typedef enum logic [2:0] {IDLE, W1, W2, W3, Z2, DONE} st_t;
    st_t st;
    logic [26:0] a;
    logic [15:0] d;
    logic        second;          // colour word: the entry i+1 write is pending/issued

    wire sel = ioctl_download && ioctl_index == 16'd0;

    function automatic [16:0] map_pos(input [16:0] i);   // entry index col*32+row -> row*4096+col
        map_pos = {i[4:0], i[16:5]};
    endfunction

    assign ioctl_wait = st != IDLE;

    always_ff @(posedge clk) begin
        rom68_we  <= 1'b0;
        romz80_we <= 1'b0;
        if (rst) begin
            st <= IDLE;
            mem_req <= 1'b0;
            loaded <= 1'b0;
        end else case (st)
            IDLE: if (sel && ioctl_wr) begin
                a <= ioctl_addr;
                d <= ioctl_dout;
                second <= 1'b0;
                st <= W1;
                if (ioctl_addr == 27'h80FFFE) loaded <= 1'b1;
            end
            W1: begin
                if (a < 27'h600000) begin                       // graphics
                    logic [23:0] w;
                    w = a[24:1];
                    mem_addr  <= {1'b0, w[23:6], w[4:1], w[5], w[0]};
                    mem_wdata <= d;
                    mem_req   <= 1'b1;
                    st        <= W2;
                end else if (a < 27'h700000) begin              // tilemaps
                    logic [1:0]  layer;
                    logic [16:0] i;
                    layer = a[19:18];
                    i     = a[17:1];
                    mem_addr  <= MAP_BASE[layer] + {7'd0, map_pos(i), 1'b0};
                    mem_wdata <= d;
                    mem_req   <= 1'b1;
                    st        <= W2;
                end else if (a < 27'h780000) begin              // colours: entry i (low byte), i+1
                    logic [1:0]  layer;
                    logic [16:0] i;
                    layer = 2'd3 - a[18:17];                    // tmap_hi order fg1, fg0, bg1, bg0
                    i     = {a[16:1], 1'b0};
                    mem_addr  <= MAP_BASE[layer] + {7'd0, map_pos(i), 1'b1};
                    mem_wdata <= {8'h00, d[7:0]};
                    mem_req   <= 1'b1;
                    st        <= W2;
                end else if (a < 27'h7C0000) begin              // OKI samples
                    mem_addr  <= 25'h400000 + {7'd0, a[18:1]};
                    mem_wdata <= d;
                    mem_req   <= 1'b1;
                    st        <= W2;
                end else if (a < 27'h800000) begin              // 68000 program
                    rom68_we   <= 1'b1;
                    rom68_addr <= a[17:1];
                    rom68_data <= d;
                    st         <= DONE;
                end else if (a < 27'h810000) begin              // Z80 program, 2 bytes
                    romz80_we   <= 1'b1;
                    romz80_addr <= {a[15:1], 1'b0};
                    romz80_data <= d[7:0];
                    st          <= Z2;
                end else
                    st <= DONE;
            end
            W2: if (mem_ack) begin
                mem_req <= 1'b0;                              // drop req after every ack
                if (a >= 27'h700000 && a < 27'h780000 && !second) begin
                    // second colour of the word: entry i+1
                    logic [1:0]  layer;
                    logic [16:0] i;
                    layer = 2'd3 - a[18:17];
                    i     = {a[16:1], 1'b1};
                    mem_addr  <= MAP_BASE[layer] + {7'd0, map_pos(i), 1'b1};
                    mem_wdata <= {8'h00, d[15:8]};
                    second    <= 1'b1;
                    st        <= W3;
                end else
                    st <= DONE;
            end
            W3: begin
                mem_req <= 1'b1;
                st      <= W2;
            end
            Z2: begin
                romz80_we   <= 1'b1;
                romz80_addr <= {a[15:1], 1'b1};
                romz80_data <= d[15:8];
                st          <= DONE;
            end
            DONE: st <= IDLE;                                   // ioctl_wr already low again
            default: st <= IDLE;
        endcase
    end
endmodule

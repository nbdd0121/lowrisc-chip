module dual_port_bram #(
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 32,
    parameter DEFAULT_CONTENT = "video.mem"
) (
    input  wire                          clk_a,
    input  wire                          en_a,
    input  wire [(DATA_WIDTH / 8) - 1:0] we_a,
    input  wire [ADDR_WIDTH - 1:0]       addr_a,
    input  wire [DATA_WIDTH - 1:0]       write_a,
    output reg  [DATA_WIDTH - 1:0]       read_a,

    input  wire                          clk_b,
    input  wire                          en_b,
    input  wire [(DATA_WIDTH / 8) - 1:0] we_b,
    input  wire [ADDR_WIDTH - 1:0]       addr_b,
    input  wire [DATA_WIDTH - 1:0]       write_b,
    output reg  [DATA_WIDTH - 1:0]       read_b
);

reg [DATA_WIDTH - 1:0] mem [0:2 ** ADDR_WIDTH - 1];

always_ff @(posedge clk_a)
    if (en_a) begin
        read_a <= mem[addr_a];
        foreach(we_a[i]) if(we_a[i]) mem[addr_a][i*8+:8] <= write_a[i*8+:8];
    end

always_ff @(posedge clk_b)
    if (en_b) begin
        read_b <= mem[addr_b];
        foreach(we_b[i]) if(we_b[i]) mem[addr_b][i*8+:8] <= write_b[i*8+:8];
    end

initial $readmemh(DEFAULT_CONTENT, mem);

endmodule


module clk_en_gen #(
    parameter INPUT_FREQ  = 128,
    parameter INPUT_WIDTH = 8,
    parameter WIDTH = 8
) (
    input  wire clk,
    input  wire rst,
    input  wire [INPUT_WIDTH - 1:0] freq,
    output reg  en
);

logic [WIDTH - 1:0] counter, counter_nxt;

assign counter_nxt = counter + freq;

always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        counter <= 0;
        en <= 1;
    end
    else if (counter_nxt >= INPUT_FREQ) begin
        counter <= counter_nxt - INPUT_FREQ;
        en <= 1;
    end
    else begin
        counter <= counter_nxt;
        en <= 0;
    end
end

endmodule


module video_unit (
    /*  VGA IOs */
    input  wire clk,
    // Reset, active high
    input  wire rst,
    output reg  [7:0] red,
    output reg  [7:0] green,
    output reg  [7:0] blue,
    output reg  hsync,
    output reg  vsync,

    /* Video Memory & Control Register Acccess */
    input  wire        mem_clk,
    input  wire        mem_en,
    input  wire [3:0]  mem_we,
    input  wire [15:0] mem_addr,
    input  wire [31:0] mem_write,
    output wire [31:0] mem_read
);

/* VGA controller related logic */
logic en;
logic pxl_clk;
logic pxl_clk_en;
logic [15:0] x, y;
logic [31:0] rawcolor;
logic [23:0] color;
logic [14:0] scraddr;
logic [14:0] scraddr_delayed;
logic [14:0] pxladdr;
logic [14:0] addr;

/* Mux to control if it's a control register access or memory access */
logic is_mem_access;
logic [31:0] bram_read;
reg   [31:0] cr_read;

assign is_mem_access = mem_addr[15] == 0;
assign mem_read = is_mem_access ? bram_read : cr_read;

/* Control registers */
reg   [14:0] cr_base;
reg   [14:0] cr_base_delay;

reg   [1:0]  cr_depth;
reg   [1:0]  cr_depth_delay;

logic cr_enable;
logic [7:0] cr_pxlfreq;

// hsync, vsync polarity. 0 selects positive, 1 selects negative
logic cr_hsync_pol;
logic cr_vsync_pol;

// CRT registers
logic [15:0] cr_h_total;
logic [15:0] cr_h_end_disp;
logic [15:0] cr_h_srt_sync;
logic [15:0] cr_h_end_sync;
logic [15:0] cr_v_total;
logic [15:0] cr_v_end_disp;
logic [15:0] cr_v_srt_sync;
logic [15:0] cr_v_end_sync;

/* Constants and enumerations */
localparam CR_BASE     = 15'd0;
localparam CR_DEPTH    = 15'd1;
localparam CR_ENABLE   = 15'd2;
localparam CR_POLARITY = 15'd3;
localparam CR_PXLFREQ  = 15'd4;

localparam CR_H_TOTAL    = 15'h10;
localparam CR_H_END_DISP = 15'h11;
localparam CR_H_SRT_SYNC = 15'h12;
localparam CR_H_END_SYNC = 15'h13;
localparam CR_V_TOTAL    = 15'h14;
localparam CR_V_END_DISP = 15'h15;
localparam CR_V_SRT_SYNC = 15'h16;
localparam CR_V_END_SYNC = 15'h17;

/* Address calculation */
always_comb begin
    scraddr = {1'd0, y[7:1], x[7:1]};
    case (cr_depth)
        2'b00:
            pxladdr = scraddr;
        2'b01:
            pxladdr = {1'b0, scraddr[14:1]};
        2'b10:
            pxladdr = {1'b00, scraddr[14:2]};
        2'b11:
            pxladdr = {1'b000, scraddr[14:3]};
    endcase
    addr = pxladdr + cr_base;
end

/* Color extraction */

function [23:0] unpack16 (input [15:0] color);
    unpack16 = {
        color[15:11], color[15:13],
        color[10: 5], color[10: 9],
        color[ 4: 0], color[ 4: 2]
    };
endfunction

function [23:0] unpack8 (input [7:0] color);
    unpack8 = {
        {2{color[7:5]}}, color[7:6],
        {2{color[4:2]}}, color[4:3],
        {4{color[1:0]}}
    };
endfunction

always_ff @(posedge pxl_clk)
    if (pxl_clk_en)
        scraddr_delayed <= scraddr;

always_comb begin
    case (cr_depth)
        2'b00:
            color = rawcolor[23:0];
        2'b01:
            color = unpack16(scraddr_delayed[0] ? rawcolor[31:16] : rawcolor[15:0]);
        2'b10:
            case (scraddr_delayed[1:0])
                2'b00: color = unpack8(rawcolor[ 7: 0]);
                2'b01: color = unpack8(rawcolor[15: 8]);
                2'b10: color = unpack8(rawcolor[23:16]);
                2'b11: color = unpack8(rawcolor[31:24]);
            endcase
        2'b11:
            case (scraddr_delayed[2:0])
                3'b000: color = {6{rawcolor[ 3: 0]}};
                3'b001: color = {6{rawcolor[ 7: 4]}};
                3'b010: color = {6{rawcolor[11: 8]}};
                3'b011: color = {6{rawcolor[15:12]}};
                3'b100: color = {6{rawcolor[19:16]}};
                3'b101: color = {6{rawcolor[23:20]}};
                3'b110: color = {6{rawcolor[27:24]}};
                3'b111: color = {6{rawcolor[31:28]}};
            endcase
    endcase
end

/* Clock freq choosing */
clk_en_gen clk_gen (
    .clk  (pxl_clk),
    .rst  (rst),
    .freq (cr_pxlfreq),
    .en   (pxl_clk_en)
);

/* Control register R/W */
always_ff @(posedge mem_clk or posedge rst)
    if (rst) begin
        cr_base_delay  <= 15'd0;
        cr_depth_delay <= 2'd0;
        cr_enable      <= 1'd1;
        cr_pxlfreq     <= 8'd65;
        cr_hsync_pol   <= 1'd1;
        cr_vsync_pol   <= 1'd1;

        cr_h_total     <= 16'd1344;
        cr_h_end_disp  <= 16'd1024;
        cr_h_srt_sync  <= 16'd1048;
        cr_h_end_sync  <= 16'd1184;
        cr_v_total     <= 16'd806;
        cr_v_end_disp  <= 16'd768;
        cr_v_srt_sync  <= 16'd771;
        cr_v_end_sync  <= 16'd777;
    end
    else if (mem_en & !is_mem_access) begin
        case (mem_addr[14:0])
            CR_BASE: cr_read <= {17'd0, cr_base};
            CR_DEPTH: cr_read <= {30'd0, cr_depth};
            CR_ENABLE: cr_read <= {31'd0, cr_enable};
            CR_POLARITY: cr_read <= {30'd0, cr_vsync_pol, cr_hsync_pol};
            CR_PXLFREQ: cr_read <= {24'd0, cr_pxlfreq};

            CR_H_TOTAL   : cr_read <= {16'd0, cr_h_total   };
            CR_H_END_DISP: cr_read <= {16'd0, cr_h_end_disp};
            CR_H_SRT_SYNC: cr_read <= {16'd0, cr_h_srt_sync};
            CR_H_END_SYNC: cr_read <= {16'd0, cr_h_end_sync};
            CR_V_TOTAL   : cr_read <= {16'd0, cr_v_total   };
            CR_V_END_DISP: cr_read <= {16'd0, cr_v_end_disp};
            CR_V_SRT_SYNC: cr_read <= {16'd0, cr_v_srt_sync};
            CR_V_END_SYNC: cr_read <= {16'd0, cr_v_end_sync};
            default: cr_read <= 32'd0;
        endcase

        if (&mem_we)
            case (mem_addr[14:0])
                CR_BASE: cr_base_delay <= mem_write[14:0];
                CR_DEPTH: cr_depth_delay <= mem_write[1:0];
                CR_ENABLE: cr_enable <= mem_write[0];
                CR_POLARITY:
                    if (!cr_enable) begin
                        cr_vsync_pol <= mem_write[1];
                        cr_hsync_pol <= mem_write[0];
                    end
                CR_PXLFREQ   : if (!cr_enable) cr_pxlfreq    <= mem_write[ 7:0];
                CR_H_TOTAL   : if (!cr_enable) cr_h_total    <= mem_write[15:0];
                CR_H_END_DISP: if (!cr_enable) cr_h_end_disp <= mem_write[15:0];
                CR_H_SRT_SYNC: if (!cr_enable) cr_h_srt_sync <= mem_write[15:0];
                CR_H_END_SYNC: if (!cr_enable) cr_h_end_sync <= mem_write[15:0];
                CR_V_TOTAL   : if (!cr_enable) cr_v_total    <= mem_write[15:0];
                CR_V_END_DISP: if (!cr_enable) cr_v_end_disp <= mem_write[15:0];
                CR_V_SRT_SYNC: if (!cr_enable) cr_v_srt_sync <= mem_write[15:0];
                CR_V_END_SYNC: if (!cr_enable) cr_v_end_sync <= mem_write[15:0];
            endcase
    end

// Delay write to cr_base until next vsync to avoid tearing
always_ff @(posedge pxl_clk or posedge rst)
    if (rst) begin
        cr_base      <= 15'd0;
        cr_depth     <= 2'd0;
    end
    else if (pxl_clk_en) begin
        if (vsync == !cr_vsync_pol | !cr_enable) begin
            cr_base    <= cr_base_delay;
            cr_depth   <= cr_depth_delay;
        end
    end


dual_port_bram #(
    .ADDR_WIDTH (15)
) videomem (
    .clk_a   (mem_clk),
    .en_a    (mem_en & is_mem_access),
    .we_a    (mem_we),
    .addr_a  (mem_addr[14:0]),
    .write_a (mem_write),
    .read_a  (bram_read),

    .clk_b   (pxl_clk),
    .en_b    (en & pxl_clk_en),
    .we_b    (4'd0),
    .addr_b  (addr),
    .write_b (32'd0),
    .read_b  (rawcolor)
);

clk_wiz_vga clk_conv(
    .clk_in1  (clk),
    .reset    (rst),
    .clk_out1 (pxl_clk)
);

/* VGA Controller */
reg [15:0] h_counter;
reg [15:0] v_counter;
reg hsync_delay, vsync_delay;
reg en_delayed;

// Logic to update h and v counters
always_ff @(posedge pxl_clk or posedge rst)
begin
    if (rst | !cr_enable)
        begin
            h_counter <= 0;
            v_counter <= 0;
        end
    else if (pxl_clk_en) begin
        if (h_counter == cr_h_total - 1)
            begin
                h_counter <= 0;
                if (v_counter == cr_v_total - 1)
                    v_counter <= 0;
                else
                    v_counter <= v_counter + 1;
            end
        else
            begin
                h_counter <= h_counter + 1;
            end
    end
end

// This delays the generation of hsync and vsync signals by one clock cycle
// since we need one clock cycle to get the RGB data
always_ff @(posedge pxl_clk)
begin
    if (pxl_clk_en) begin
        hsync <= hsync_delay;
        if (!cr_enable)
            hsync_delay <= 0;
        else if (h_counter >= cr_h_srt_sync && h_counter < cr_h_end_sync)
            hsync_delay <= !cr_hsync_pol;
        else
            hsync_delay <= cr_hsync_pol;
    end
end

always_ff @(posedge pxl_clk)
begin
    if (pxl_clk_en) begin
        vsync <= vsync_delay;
        if (!cr_enable)
            vsync_delay <= 0;
        else if (v_counter >= cr_v_srt_sync && v_counter < cr_v_end_sync)
            vsync_delay <= !cr_vsync_pol;
        else
            vsync_delay <= cr_vsync_pol;
    end
end

always_ff @(posedge pxl_clk) begin
    if (pxl_clk_en)
        en_delayed <= en;
end

// Wire to image provider
// `en` check is not necessary as we've disabled clock when `en` is false
// but this is just an additional safe guard
assign x = en ? h_counter : 0;
assign y = en ? v_counter : 0;

// Enable image output
assign en = h_counter < cr_h_end_disp && v_counter < cr_v_end_disp;

// Output color if enabled
assign red   = en_delayed & cr_enable ? color[23:16] : 0;
assign green = en_delayed & cr_enable ? color[15: 8] : 0;
assign blue  = en_delayed & cr_enable ? color[ 7: 0] : 0;

endmodule

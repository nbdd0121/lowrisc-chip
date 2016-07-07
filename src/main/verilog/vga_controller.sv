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
begin
	read_a <= mem[addr_a];
	foreach(we_a[i])
		if(we_a[i])
			mem[addr_a][i*8+:8] <= write_a[i*8+:8];
end

always_ff @(posedge clk_b) begin
	read_b <= mem[addr_b];
	foreach(we_b[i])
		if(we_b[i])
			mem[addr_b][i*8+:8] <= write_b[i*8+:8];
end

initial $readmemh(DEFAULT_CONTENT, mem);

endmodule


module video_unit (
    /*  VGA IOs */
    input  wire clk,
    // Reset, active high
    input  wire rst,
    output wire [7:0] red,
    output wire [7:0] green,
    output wire [7:0] blue,
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
logic [15:0] x ,y;
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

localparam CR_BASE  = 15'd0;
localparam CR_DEPTH = 15'd1;

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

always_ff @(posedge clk)
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

/* Control register R/W */
always_ff @(posedge mem_clk or posedge rst)
    if (rst) begin
        cr_base_delay <= 15'd0;
        cr_depth_delay <= 2'd0;
    end
    else if (mem_en & !is_mem_access) begin
        case (mem_addr[14:0])
            CR_BASE: begin
                cr_read <= {17'd0, cr_base};
                if (&mem_we) cr_base_delay <= mem_write[14:0];
            end
            CR_DEPTH: begin
                cr_read <= {30'd0, cr_depth};
                if (&mem_we) cr_depth_delay <= mem_write[1:0];
            end
            default:
                cr_read <= 32'd0;
        endcase
    end

// Delay write to cr_base until next vsync to avoid tearing
always_ff @(posedge clk)
    if (vsync == 0) begin
        cr_base  <= cr_base_delay;
        cr_depth <= cr_depth_delay;
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

    .clk_b   (clk),
    .en_b    (en),
    .we_b    (4'd0),
    .addr_b  (addr),
    .write_b (32'd0),
    .read_b  (rawcolor)
);

vga_controller vga(
    .*
);

endmodule


module vga_controller # (
    parameter H_SYNC_ACTIVE = 0,
    parameter V_SYNC_ACTIVE = 0,

    parameter H_FRONT_PORCH = 16'd16,
    parameter H_SYNC_PULSE  = 16'd96,
    parameter H_FRAME_WIDTH = 16'd640,
    parameter H_BACK_PORCH  = 16'd48,
    parameter H_TOTAL_WIDTH = 16'd800,

    parameter V_FRONT_PORCH = 16'd10,
    parameter V_SYNC_PULSE  = 16'd2,
    parameter V_FRAME_WIDTH = 16'd480,
    parameter V_BACK_PORCH  = 16'd33,
    parameter V_TOTAL_WIDTH = 16'd525
) (
    input  wire clk,
    // Reset, active high
    input  wire rst,
    output wire [7:0] red,
    output wire [7:0] green,
    output wire [7:0] blue,
    output reg  hsync,
    output reg  vsync,

    // External image provider
    output wire en,
    output wire [15:0] x,
    output wire [15:0] y,
    input  wire [23:0] color
);

reg [15:0] h_counter;
reg [15:0] v_counter;
reg hsync_delay, vsync_delay;
reg en_delayed;

// Logic to update h and v counters
always_ff @(posedge clk or posedge rst)
begin
    if (rst)
        begin
            h_counter <= 0;
            v_counter <= 0;
        end
    else
        begin
            if (h_counter == H_TOTAL_WIDTH - 1)
                begin
                    h_counter <= 0;
                    if (v_counter == V_TOTAL_WIDTH - 1)
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
always_ff @(posedge clk)
begin
    hsync <= hsync_delay;
    if (h_counter >= H_FRAME_WIDTH + H_FRONT_PORCH && h_counter < H_FRAME_WIDTH + H_FRONT_PORCH + H_SYNC_PULSE)
        hsync_delay <= H_SYNC_ACTIVE;
    else
        hsync_delay <= !H_SYNC_ACTIVE;
end

always_ff @(posedge clk)
begin
    vsync <= vsync_delay;
    if (v_counter >= V_FRAME_WIDTH + V_FRONT_PORCH && v_counter < V_FRAME_WIDTH + V_FRONT_PORCH + V_SYNC_PULSE)
        vsync_delay <= V_SYNC_ACTIVE;
    else
        vsync_delay <= !V_SYNC_ACTIVE;
end

always_ff @(posedge clk) begin
    en_delayed <= en;
end

// Wire to image provider
// `en` check is not necessary as we've disabled clock when `en` is false
// but this is just an additional safe guard
assign x = en ? h_counter : 0;
assign y = en ? v_counter : 0;

// Enable image output
assign en = h_counter < H_FRAME_WIDTH && v_counter < V_FRAME_WIDTH;

// Output color if enabled
assign red   = en_delayed ? color[23:16] : 0;
assign green = en_delayed ? color[15: 8] : 0;
assign blue  = en_delayed ? color[ 7: 0] : 0;

endmodule

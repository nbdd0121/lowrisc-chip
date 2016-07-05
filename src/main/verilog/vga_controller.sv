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


module video_unit (
    /*  VGA IOs */
    input  wire clk,
    // Reset, active high
    input  wire rst,
    output wire [7:0] red,
    output wire [7:0] green,
    output wire [7:0] blue,
    output reg hsync,
    output reg vsync,

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
logic [31:0] color;
logic [14:0] addr;

assign addr = {1'd0, y[7:1], x[7:1]} + cr_base;

/* Mux to control if it's a control register access or memory access */
logic is_mem_access;
logic [31:0] bram_read;
reg   [31:0] cr_read;

assign is_mem_access = mem_addr[15] == 0;
assign mem_read = is_mem_access ? bram_read : cr_read;

/* Control registers */
reg   [14:0] cr_base;
reg   [14:0] cr_base_delay;

always_ff @(posedge mem_clk)
    if (mem_en & !is_mem_access) begin
        case (mem_addr[14:0])
            15'd0: begin
                cr_read <= {17'd0, cr_base};
                if (&mem_we) cr_base_delay <= mem_write[14:0];
            end
            default:
                cr_read <= 32'd0;
        endcase
    end

// Delay write to cr_base until next vsync to avoid tearing
always_ff @(posedge clk) begin
    if (vsync == 0)
        cr_base <= cr_base_delay;
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
    .read_b  (color)
);

vga_controller vga(
    .*,
    .color (color[23:0])
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
always @(posedge clk or posedge rst)
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
always @(posedge clk)
begin
    hsync <= hsync_delay;
    if (h_counter >= H_FRAME_WIDTH + H_FRONT_PORCH && h_counter < H_FRAME_WIDTH + H_FRONT_PORCH + H_SYNC_PULSE)
        hsync_delay <= H_SYNC_ACTIVE;
    else
        hsync_delay <= !H_SYNC_ACTIVE;
end

always @(posedge clk)
begin
    vsync <= vsync_delay;
    if (v_counter >= V_FRAME_WIDTH + V_FRONT_PORCH && v_counter < V_FRAME_WIDTH + V_FRONT_PORCH + V_SYNC_PULSE)
        vsync_delay <= V_SYNC_ACTIVE;
    else
        vsync_delay <= !V_SYNC_ACTIVE;
end

always @(posedge clk) begin
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

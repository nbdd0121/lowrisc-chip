module vga_controller (
	input  wire clk,
	input  wire rst, /* reset, active high */
	output wire [7:0] red,
	output wire [7:0] green,
	output wire [7:0] blue,
	output reg hsync,
	output reg vsync
);

parameter H_FRONT_PORCH = 16'd16;
parameter H_SYNC_PULSE  = 16'd96;
parameter H_FRAME_WIDTH = 16'd640;
parameter H_BACK_PORCH  = 16'd48;
parameter H_TOTAL_WIDTH = 16'd800;

parameter V_FRONT_PORCH = 16'd10;
parameter V_SYNC_PULSE  = 16'd2;
parameter V_FRAME_WIDTH = 16'd480;
parameter V_BACK_PORCH  = 16'd33;
parameter V_TOTAL_WIDTH = 16'd525;

parameter COLOR_R = 8'hF0;
parameter COLOR_G = 8'hDF;
parameter COLOR_B = 8'h60;

reg [15:0] h_counter;
reg [15:0] v_counter;
reg en;

always @(posedge clk)
begin
	if(rst == 1)
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

always @(posedge clk)
begin
	if (h_counter >= H_FRAME_WIDTH + H_FRONT_PORCH && h_counter < H_FRAME_WIDTH + H_FRONT_PORCH + H_SYNC_PULSE)
		hsync <= 1;
	else
		hsync <= 0;
end

always @(posedge clk)
begin
	if (v_counter >= V_FRAME_WIDTH + V_FRONT_PORCH && v_counter < V_FRAME_WIDTH + V_FRONT_PORCH + V_SYNC_PULSE)
		vsync <= 1;
	else
		vsync <= 0;
end

always @(posedge clk)
begin
	if (h_counter < H_FRAME_WIDTH && v_counter < V_FRAME_WIDTH)
		en <= 1;
	else
		en <= 0;
end

assign red = COLOR_R & {8{en}};
assign green = COLOR_G & {8{en}};
assign blue = COLOR_B & {8{en}};

endmodule

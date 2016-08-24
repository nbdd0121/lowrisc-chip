module dual_port_bram #(
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 32,
    parameter DEFAULT_CONTENT = ""
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

generate
   if (DEFAULT_CONTENT)
      initial $readmemh(DEFAULT_CONTENT, mem);
   else
      initial begin
         foreach(mem[i]) mem[i] <= {DATA_WIDTH{1'b0}};
      end
endgenerate

endmodule


module clk_en_gen #(
   parameter INPUT_FREQ  = 125,
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
   input  clk,
   // Reset, active high
   input  rst,
   output [7:0] red,
   output [7:0] green,
   output [7:0] blue,
   output logic hsync,
   output logic vsync,

   /* DMA Controller */
   input  aclk,
   input  aresetn,
   nasti_channel.master dma,

   /* Control Register Acccess */
   input  s_nasti_aclk,
   input  s_nasti_aresetn,
   nasti_channel.slave  s_nasti
);

logic pxl_clk;
logic pxl_clk_en;

/* VGA controller related logic */
logic en;
logic [63:0] rawcolor;
logic [23:0] color;
// Pixel address in memory, unit is 8-byte
logic [11:0]  pxl_addr;
// Offset within the byte
logic [7:0]  pxl_offset;
logic [7:0]  pxl_offset_delayed;

/* Control registers */

// Base register, must be 8-byte aligned
logic [63:0] cr_base;
logic [63:0] cr_base_delay;

logic [1:0]  cr_depth;

logic cr_enable;
logic [7:0] cr_pxlfreq;

// hsync, vsync polarity. 0 selects positive, 1 selects negative
logic cr_hsync_pol;
logic cr_vsync_pol;

// Framebuffer dimension control
logic [11:0] cr_fb_width;
logic [11:0] cr_fb_height;
// Since this is fed to DMA, it must be 8-byte aligned
logic [13:0] cr_fb_bpl;

// Outside framebuffer fallback color
logic [23:0] cr_bg_color;
logic [23:0] cr_bg_color_delay;

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
localparam CR_BASE       = 10'h0;
localparam CR_BASE_HIGH  = 10'h1;
localparam CR_DEPTH      = 10'h2;
localparam CR_ENABLE     = 10'h3;
localparam CR_POLARITY   = 10'h4;
localparam CR_PXLFREQ    = 10'h5;
localparam CR_FB_WIDTH   = 10'h6;
localparam CR_FB_HEIGHT  = 10'h7;
localparam CR_FB_BPL     = 10'h8;
localparam CR_BG_COLOR   = 10'h9;

localparam CR_H_TOTAL    = 10'h10;
localparam CR_H_END_DISP = 10'h11;
localparam CR_H_SRT_SYNC = 10'h12;
localparam CR_H_END_SYNC = 10'h13;
localparam CR_V_TOTAL    = 10'h14;
localparam CR_V_END_DISP = 10'h15;
localparam CR_V_SRT_SYNC = 10'h16;
localparam CR_V_END_SYNC = 10'h17;

/* Control register R/W */
logic mem_clk;
logic mem_rst;
logic mem_en;
logic [3:0] mem_we;
logic [11:0] mem_addr;
logic [31:0] mem_write;
logic [31:0] mem_read;

nasti_lite_bram_ctrl # (
   .ADDR_WIDTH (64),
   .DATA_WIDTH (32),
   .BRAM_ADDR_WIDTH (12)
) ctrl (
   .s_nasti_aclk    (s_nasti_aclk),
   .s_nasti_aresetn (s_nasti_aresetn),
   .s_nasti         (s_nasti),
   .bram_clk        (mem_clk),
   .bram_rst        (mem_rst),
   .bram_en         (mem_en),
   .bram_we         (mem_we),
   .bram_addr       (mem_addr),
   .bram_wrdata     (mem_write),
   .bram_rddata     (mem_read)
);

always_ff @(posedge mem_clk or posedge rst)
   if (rst) begin
      cr_base_delay  <= 15'd0;
      cr_depth       <= 2'd0;
      cr_enable      <= 1'd0;
      cr_pxlfreq     <= 8'd25;
      cr_hsync_pol   <= 1'd1;
      cr_vsync_pol   <= 1'd1;
      cr_fb_width    <= 12'd640;
      cr_fb_height   <= 12'd480;
      cr_fb_bpl      <= 14'd2048;
      cr_bg_color_delay <= 24'hFFFFFF;

      cr_h_total     <= 16'd800;
      cr_h_end_disp  <= 16'd640;
      cr_h_srt_sync  <= 16'd656;
      cr_h_end_sync  <= 16'd752;
      cr_v_total     <= 16'd525;
      cr_v_end_disp  <= 16'd480;
      cr_v_srt_sync  <= 16'd490;
      cr_v_end_sync  <= 16'd492;
   end
   else if (mem_en) begin
      case (mem_addr[11:2])
         CR_BASE      : mem_read <= cr_base[31:0];
         CR_BASE_HIGH : mem_read <= cr_base[63:32];
         CR_DEPTH     : mem_read <= {30'd0, cr_depth};
         CR_ENABLE    : mem_read <= {31'd0, cr_enable};
         CR_POLARITY  : mem_read <= {30'd0, cr_vsync_pol, cr_hsync_pol};
         CR_PXLFREQ   : mem_read <= {24'd0, cr_pxlfreq};
         CR_FB_WIDTH  : mem_read <= {20'd0, cr_fb_width};
         CR_FB_HEIGHT : mem_read <= {20'd0, cr_fb_height};
         CR_FB_BPL    : mem_read <= {18'd0, cr_fb_bpl};
         CR_BG_COLOR  : mem_read <= { 8'd0, cr_bg_color};

         CR_H_TOTAL   : mem_read <= {16'd0, cr_h_total   };
         CR_H_END_DISP: mem_read <= {16'd0, cr_h_end_disp};
         CR_H_SRT_SYNC: mem_read <= {16'd0, cr_h_srt_sync};
         CR_H_END_SYNC: mem_read <= {16'd0, cr_h_end_sync};
         CR_V_TOTAL   : mem_read <= {16'd0, cr_v_total   };
         CR_V_END_DISP: mem_read <= {16'd0, cr_v_end_disp};
         CR_V_SRT_SYNC: mem_read <= {16'd0, cr_v_srt_sync};
         CR_V_END_SYNC: mem_read <= {16'd0, cr_v_end_sync};
         default: mem_read <= 32'd0;
      endcase

      if (&mem_we)
         case (mem_addr[11:2])
            CR_BASE      : cr_base_delay[31:0] <= mem_write;
            CR_BASE_HIGH : cr_base_delay[63:32] <= mem_write;
            CR_DEPTH     : if (!cr_enable) cr_depth      <= mem_write[1:0];
            CR_ENABLE    : cr_enable <= mem_write[0];
            CR_POLARITY  :
               if (!cr_enable) begin
                  cr_vsync_pol <= mem_write[1];
                  cr_hsync_pol <= mem_write[0];
               end
            CR_PXLFREQ   : if (!cr_enable) cr_pxlfreq    <= mem_write[ 7:0];
            CR_FB_WIDTH  : if (!cr_enable) cr_fb_width   <= mem_write[11:0];
            CR_FB_HEIGHT : if (!cr_enable) cr_fb_height  <= mem_write[11:0];
            CR_FB_BPL    : if (!cr_enable) cr_fb_bpl     <= {mem_write[13:3], 3'd0};
            CR_BG_COLOR  : cr_bg_color_delay  <= mem_write[23:0];
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
      cr_bg_color  <= 24'hFFFFFF;
   end
   else if (pxl_clk_en) begin
      if (vsync == !cr_vsync_pol | !cr_enable) begin
         cr_base     <= cr_base_delay;
         cr_bg_color <= cr_bg_color_delay;
      end
   end

/* Framebuffer */

logic buffer_clk;
logic buffer_en;
logic [7:0] buffer_we;
logic [16:0] buffer_addr;
logic [63:0] buffer_wrdata;
logic [63:0] buffer_rddata;

logic dma_done;
logic [63:0] dma_src_addr;
logic [63:0] dma_dest_addr;
logic [63:0] dma_length;
logic dma_en;

// 32KiB Line Buffer, (1 << 12) * 64Bits
dual_port_bram #(
   .ADDR_WIDTH (12),
   .DATA_WIDTH (64)
) videomem (
   .clk_a   (buffer_clk),
   .en_a    (buffer_en),
   .we_a    (buffer_we),
   .addr_a  (buffer_addr[14:3]),
   .write_a (buffer_wrdata),
   .read_a  (buffer_rddata),

   .clk_b   (pxl_clk),
   .en_b    (en & pxl_clk_en),
   .we_b    (8'd0),
   .addr_b  (pxl_addr),
   .write_b (64'd0),
   .read_b  (rawcolor)
);

// Internal NASTI Channel connecting buffer with DMA
nasti_channel # (
   .ADDR_WIDTH(64),
   .DATA_WIDTH(64)
) buffer_ch();

// Internal NASTI BRAM Controller to write to the buffer
nasti_bram_ctrl # (
   .ADDR_WIDTH (64),
   .DATA_WIDTH (64),
   .BRAM_ADDR_WIDTH (15)
) buffer_ctrl (
   .s_nasti_aclk (aclk),
   .s_nasti_aresetn (aresetn),
   .s_nasti (buffer_ch),
   .bram_clk (buffer_clk),
   .bram_en (buffer_en),
   .bram_we (buffer_we),
   .bram_addr (buffer_addr),
   .bram_wrdata (buffer_wrdata),
   .bram_rddata (buffer_rddata)
);

// Data mover from framebuffer to internal buffer
nasti_data_mover # (
   .ADDR_WIDTH(64),
   .DATA_WIDTH(64),
   .MAX_BURST_LENGTH(8)
) data_mover (
   .aclk (aclk),
   .aresetn (aresetn),
   .src (dma),
   .dest (buffer_ch),
   .r_src (dma_src_addr),
   .r_dest (dma_dest_addr),
   .r_len (dma_length),
   .r_valid (dma_en),
   .r_ready (dma_done)
);

/* Clock freq choosing */
clk_en_gen clk_gen (
   .clk  (pxl_clk),
   .rst  (rst),
   .freq (cr_pxlfreq),
   .en   (pxl_clk_en)
);

clk_wiz_vga clk_conv(
    .clk_in1  (clk),
    .reset    (rst),
    .clk_out1 (pxl_clk)
);

/* VGA Controller */

// This is a three-stage pipeline VGA controller
// In the first stage, updated value of h_counter and v_counter
// In the second stage, screen address will be updated and DMA request for next line is initiated
// In the third stage, BRAM will be accessed to retrieve the pixel

// First stage

logic [15:0] h_counter;
logic [15:0] v_counter;

// Logic to update h and v counters
always_ff @(posedge pxl_clk or posedge rst) begin
   if (rst | !cr_enable) begin
      // If monitor is turned off, reset counters
      h_counter <= 0;
      v_counter <= 0;
   end
    else if (pxl_clk_en) begin
      if (h_counter == cr_h_total - 1) begin
            h_counter <= 0;
            if (v_counter == cr_v_total - 1) begin
               v_counter <= 0;
            end
            else begin
               v_counter <= v_counter + 1;
            end
      end
      else begin
         h_counter <= h_counter + 1;
      end
   end
end

// Second stage

logic hsync_delay, vsync_delay;

// These values should be delayed until next aclk
// to avoid inter-clock slacks
logic dma_done_delayed;
logic [63:0] dma_src_addr_delay;
logic [63:0] dma_dest_addr_delay;
logic [63:0] dma_length_delay;
logic dma_en_delay;

logic pxl_en;

always_ff @(posedge pxl_clk) begin
   if (pxl_clk_en) begin
      // Mute output when monitor is disabled
      if (!cr_enable)
         hsync_delay <= 0;
      else if (h_counter >= cr_h_srt_sync && h_counter < cr_h_end_sync)
         hsync_delay <= !cr_hsync_pol;
      else
         hsync_delay <= cr_hsync_pol;

      if (!cr_enable)
         vsync_delay <= 0;
      else if (v_counter >= cr_v_srt_sync && v_counter < cr_v_end_sync)
         vsync_delay <= !cr_vsync_pol;
      else
         vsync_delay <= cr_vsync_pol;

      if (!cr_enable) begin
         en <= 0;
         pxl_en <= 0;
      end
      else begin
         // Enable image output if within display area
         en <= h_counter < cr_fb_width && v_counter < cr_fb_height;
         pxl_en <= h_counter < cr_h_end_disp && v_counter < cr_v_end_disp;
      end
   end
end

logic [14:0] fb_width_in_bytes;

always_comb begin
   case (cr_depth)
      2'b00: fb_width_in_bytes = cr_fb_width * 4;
      2'b01: fb_width_in_bytes = cr_fb_width * 2;
      2'b10: fb_width_in_bytes = cr_fb_width;
      2'b11: fb_width_in_bytes = cr_fb_width / 2;
   endcase
end

always_ff @(posedge pxl_clk or posedge rst) begin
   if (rst) begin
      dma_en_delay <= 0;
      dma_src_addr_delay <= 0;
   end
   else if (pxl_clk_en && cr_enable) begin
      if (h_counter == 0) begin
         if (v_counter < cr_fb_height) begin
            pxl_addr <= {v_counter[0], 11'd0};
            pxl_offset <= 0;

            if (v_counter == 0)
               // Special case if this is first line
               // After screen is re-enabled, we need to make sure
               // dma_src_addr_delay is updated
               dma_src_addr_delay <= cr_base_delay + cr_fb_bpl;
            else
            if (v_counter == cr_fb_height - 1)
               // For last line, reset start address to base
               dma_src_addr_delay <= cr_base_delay;
            else
               dma_src_addr_delay <= dma_src_addr_delay + cr_fb_bpl;

            dma_dest_addr_delay <= {49'd0, ~v_counter[0], 14'd0};
            dma_length_delay <= fb_width_in_bytes;
            dma_en_delay <= 1;
         end
      end
      else begin
         // Advance screen address and offset within qword, depending on color depth
         case (cr_depth)
            2'b00:
               if (pxl_offset == 32) begin
                  pxl_addr <= pxl_addr + 1;
                  pxl_offset <= 0;
               end
               else
                  pxl_offset <= pxl_offset + 32;
            2'b01:
               if (pxl_offset == 48) begin
                  pxl_addr <= pxl_addr + 1;
                  pxl_offset <= 0;
               end
               else
                  pxl_offset <= pxl_offset + 16;
            2'b10:
               if (pxl_offset == 56) begin
                  pxl_addr <= pxl_addr + 1;
                  pxl_offset <= 0;
               end
               else
                  pxl_offset <= pxl_offset + 8;
            2'b11:
               if (pxl_offset == 60) begin
                  pxl_addr <= pxl_addr + 1;
                  pxl_offset <= 0;
               end
               else
                  pxl_offset <= pxl_offset + 4;
         endcase

         // Prevent data mover from repeating the action
         if (dma_done_delayed == 0) dma_en_delay <= 0;
      end
   end
end

always_ff @(posedge aclk or negedge aresetn) begin
   if (!aresetn) begin
      dma_en <= 0;
   end
   else begin
      dma_src_addr <= dma_src_addr_delay;
      dma_dest_addr <= dma_dest_addr_delay;
      dma_length <= dma_length_delay;
      dma_en <= dma_en_delay;
      dma_done_delayed <= dma_done;
   end
end

// Third stage

logic en_delayed;
logic pxl_en_delayed;

always_ff @(posedge pxl_clk) begin
   if (pxl_clk_en) begin
      // These delays the generation of hsync and vsync signals by one clock cycle
      // since we need one clock cycle to get the RGB data
      hsync <= hsync_delay;
      vsync <= vsync_delay;

      en_delayed <= en;
      pxl_en_delayed <= pxl_en;

      pxl_offset_delayed <= pxl_offset;
   end
end

// Combinational logic for output

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

function [23:0] unpack4 (input [3:0] color);
   unpack4 = {6{color}};
endfunction

always_comb begin
   case (cr_depth)
      2'b00:
         color = rawcolor >> pxl_offset_delayed;
      2'b01:
         color = unpack16(rawcolor >> pxl_offset_delayed);
      2'b10:
         color = unpack8 (rawcolor >> pxl_offset_delayed);
      2'b11:
         color = unpack4 (rawcolor >> pxl_offset_delayed);
    endcase
end

logic [23:0] disp_color;

assign disp_color = pxl_en_delayed & cr_enable ? (en_delayed ? color : cr_bg_color) : 0;

// Output color if enabled
assign red   = disp_color[23:16];
assign green = disp_color[15: 8];
assign blue  = disp_color[ 7: 0];

endmodule

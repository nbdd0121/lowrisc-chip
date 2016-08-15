module video_acc #(
   parameter COEF_WIDTH = 16, // Int size for DCT/IDCT
   parameter ADDR_WIDTH = 64,
   parameter DATA_WIDTH = 64
) (
   input clk,
   input rst,

   // DMA Controller
   input  aclk,
   input  aresetn,
   nasti_channel dma,

   // Instruction Cache Acccess
   input  s_nasti_aclk,
   input  s_nasti_aresetn,
   nasti_channel.slave  s_nasti
);

   // Number of different stream processing units
   localparam NR_FUN_UNITS = 2;
   localparam DEST_WIDTH = 3;

   // Registers used to control the movement of data
   logic [63:0] r_src, r_len, r_dest;
   logic r_valid_to_local, r_ready_to_local, r_valid_from_local, r_ready_from_local;
   logic [DATA_WIDTH - 1:0] routing_dest;

   // Internal channels to connect to stream processors.
   nasti_stream_channel # (
      .DATA_WIDTH(DATA_WIDTH)
   ) input_buf_ch(), output_buf_ch();

   nasti_stream_channel # (
      .DATA_WIDTH(DATA_WIDTH)
   ) dma_to_local_ch(), local_to_dma_ch(),routed_ch();

   nasti_stream_channel # (
      .DATA_WIDTH(DATA_WIDTH)
   ) to_idct_ch(), from_idct_ch();

   nasti_stream_channel # (
      .DATA_WIDTH(DATA_WIDTH)
   ) to_dct_ch(), from_dct_ch();

   nasti_stream_channel # (
      .N_PORT(NR_FUN_UNITS + 1),
      .DEST_WIDTH(DEST_WIDTH),
      .DATA_WIDTH(DATA_WIDTH)
   ) in_vein_ch(), out_vein_ch();

   nasti_channel # (
      .ADDR_WIDTH(64),
      .DATA_WIDTH(DATA_WIDTH)
   ) mover_in_ch(), mover_out_ch();

   // Nasti-stream router
   nasti_stream_router #(
      .DEST_WIDTH(DEST_WIDTH)
   ) router (
      .aclk(aclk),
      .aresetn(aresetn),
      .dest(routing_dest),
      .master(input_buf_ch),
      .slave(routed_ch)
   );

   // Nasti-stream Crossbar
   nasti_stream_crossbar # (
      .N_MASTER(NR_FUN_UNITS),
      .N_SLAVE(NR_FUN_UNITS),
      .DEST_WIDTH(DEST_WIDTH),
      .DATA_WIDTH(DATA_WIDTH)
   ) crossbar (
      .aclk(aclk),
      .aresetn(aresetn),
      .master(out_vein_ch),
      .slave(in_vein_ch)
   );

   // Data movers that convert to/from AXI Stream and buffers
   nasti_stream_mover # (
      .ADDR_WIDTH(ADDR_WIDTH),
      .DATA_WIDTH(DATA_WIDTH)
   ) dm_data_to_local (
      .aclk(aclk),
      .aresetn(aresetn),
      .src(mover_in_ch),
      .dest(dma_to_local_ch),
      .r_src(r_src),
      .r_len(r_len),
      .r_valid(r_valid_to_local),
      .r_ready(r_ready_to_local)
   );

   nasti_stream_buf # (
      .BUF_SIZE(16)
   ) input_buf (
      .aclk(aclk),
      .aresetn(aresetn),

      .src(dma_to_local_ch),
      .dest(input_buf_ch)
   );

   stream_nasti_mover# (
      .ADDR_WIDTH(ADDR_WIDTH),
      .DATA_WIDTH(DATA_WIDTH)
   ) dm_data_from_local (
      .aclk(aclk),
      .aresetn(aresetn),
      .src(local_to_dma_ch),
      .dest(mover_out_ch),
      .r_dest(r_dest),
      .r_valid(r_valid_from_local),
      .r_ready(r_ready_from_local)
   );

   nasti_stream_buf # (
      .BUF_SIZE(16)
   ) output_buf (
      .aclk(aclk),
      .aresetn(aresetn),

      .src(output_buf_ch),
      .dest(local_to_dma_ch)
   );

   // Dummy channel connected to unused ports in splicer and combiner
   nasti_stream_channel # (
      .DATA_WIDTH(DATA_WIDTH)
   ) dummy_ch();

   nasti_stream_combiner #(
      .N_PORT(NR_FUN_UNITS + 1)
   ) glue(
      .slave(out_vein_ch),
      .master_0(routed_ch),
      .master_1(from_dct_ch),
      .master_2(from_idct_ch),
      .master_3(dummy_ch),
      .master_4(dummy_ch),
      .master_5(dummy_ch),
      .master_6(dummy_ch),
      .master_7(dummy_ch)
   );

   nasti_stream_slicer #(
         .N_PORT(NR_FUN_UNITS + 1)
   )  unglue(
      .master(in_vein_ch),
      .slave_0(output_buf_ch),
      .slave_1(to_dct_ch),
      .slave_2(to_idct_ch),
      .slave_3(dummy_ch),
      .slave_4(dummy_ch),
      .slave_5(dummy_ch),
      .slave_6(dummy_ch),
      .slave_7(dummy_ch)
   );

   assign mover_in_ch.r_data  = dma.r_data ;
   assign mover_in_ch.r_last  = dma.r_last ;
   assign mover_in_ch.r_id    = dma.r_id   ;
   assign mover_in_ch.r_resp  = dma.r_resp ;
   assign mover_in_ch.r_user  = dma.r_user ;
   assign mover_in_ch.r_valid = dma.r_valid;

   assign dma.r_ready = mover_in_ch.r_ready;

   assign dma.ar_id     = mover_in_ch.ar_id    ;
   assign dma.ar_addr   = mover_in_ch.ar_addr  ;
   assign dma.ar_len    = mover_in_ch.ar_len   ;
   assign dma.ar_size   = mover_in_ch.ar_size  ;
   assign dma.ar_burst  = mover_in_ch.ar_burst ;
   assign dma.ar_lock   = mover_in_ch.ar_lock  ;
   assign dma.ar_cache  = mover_in_ch.ar_cache ;
   assign dma.ar_prot   = mover_in_ch.ar_prot  ;
   assign dma.ar_qos    = mover_in_ch.ar_qos   ;
   assign dma.ar_region = mover_in_ch.ar_region;
   assign dma.ar_user   = mover_in_ch.ar_user  ;
   assign dma.ar_valid  = mover_in_ch.ar_valid ;

   assign mover_in_ch.ar_ready = dma.ar_ready;

   assign dma.aw_id     = mover_out_ch.aw_id    ;
   assign dma.aw_addr   = mover_out_ch.aw_addr  ;
   assign dma.aw_len    = mover_out_ch.aw_len   ;
   assign dma.aw_size   = mover_out_ch.aw_size  ;
   assign dma.aw_burst  = mover_out_ch.aw_burst ;
   assign dma.aw_lock   = mover_out_ch.aw_lock  ;
   assign dma.aw_cache  = mover_out_ch.aw_cache ;
   assign dma.aw_prot   = mover_out_ch.aw_prot  ;
   assign dma.aw_qos    = mover_out_ch.aw_qos   ;
   assign dma.aw_region = mover_out_ch.aw_region;
   assign dma.aw_user   = mover_out_ch.aw_user  ;
   assign dma.aw_valid  = mover_out_ch.aw_valid ;

   assign mover_out_ch.aw_ready = dma.aw_ready;

   assign dma.w_data  = mover_out_ch.w_data ;
   assign dma.w_strb  = mover_out_ch.w_strb ;
   assign dma.w_last  = mover_out_ch.w_last ;
   assign dma.w_user  = mover_out_ch.w_user ;
   assign dma.w_valid = mover_out_ch.w_valid;

   assign mover_out_ch.w_ready = dma.w_ready;

   assign mover_out_ch.b_id    = dma.b_id   ;
   assign mover_out_ch.b_resp  = dma.b_resp ;
   assign mover_out_ch.b_user  = dma.b_user ;
   assign mover_out_ch.b_valid = dma.b_valid;

   assign dma.b_ready = mover_out_ch.b_ready;

   // Instruction FIFO R/W
   logic        inst_clk;
   logic        inst_rst;
   logic        inst_en;
   logic [3:0]  inst_we;
   logic [11:0] inst_addr;
   logic [31:0] inst_write;
   logic [31:0] inst_read;

   // Instruction FIFO
   logic fifo_w_en, fifo_r_en;
   logic [31:0] fifo_w_data, fifo_r_data;
   logic inst_full, inst_empty;

   fifo #(
      .WIDTH(32),
      .DEPTH(5)
   ) inst_fifo (
      .aclk(aclk),
      .aresetn(aresetn),
      .w_en(fifo_w_en),
      .w_data(fifo_w_data),
      .r_en(fifo_r_en),
      .r_data(fifo_r_data),
      .full(inst_full),
      .empty(inst_empty)
   );

   // AXI-Lite BRAM controller used to populate the instruction FIFO
   nasti_lite_bram_ctrl # (
      .ADDR_WIDTH (64),
      .DATA_WIDTH (32),
      .BRAM_ADDR_WIDTH (12)
   ) inst_ctrl (
      .s_nasti_aclk    (s_nasti_aclk),
      .s_nasti_aresetn (s_nasti_aresetn),
      .s_nasti         (s_nasti),
      .bram_clk        (inst_clk),
      .bram_rst        (inst_rst),
      .bram_en         (inst_en),
      .bram_we         (inst_we),
      .bram_addr       (inst_addr),
      .bram_wrdata     (inst_write),
      .bram_rddata     (inst_read)
   );

   // OPCODES
   localparam  OP_NOP       = 6'h0;
   localparam  OP_MOV       = 6'h1;
   localparam  OP_LOAD_FULL = 6'h2;
   localparam  OP_LOAD_LOW  = 6'h3;
   localparam  OP_DCT       = 6'h4;
   localparam  OP_IDCT      = 6'h5;
   localparam  OP_CHROMA    = 6'h6;
   // Instruction Decode States
   localparam DECODE_IDLE                  = 2'h0; // Initial state of the decoder;
   localparam DECODE_LOAD_FULL_LOW         = 2'h1;
   localparam DECODE_LOAD_FULL_HIGH        = 2'h2;
   localparam DECODE_WAITING_ON_PIPELINE   = 2'h3;
   logic [1:0] current_state;

   // Control Plane States
   localparam  CTRL_IDLE   = 2'h0;
   localparam  CTRL_INIT   = 2'h1;
   logic [1:0] control_state;

   // Base address for the information of instructions to follow
   logic [63:0] base_addr_rd;
   logic [63:0] base_addr_wr;

   // Variables used to decode instructions
   logic [9: 0] src_delay;
   logic [9: 0] dest_delay;
   logic [12:0] len_delay;
   logic [4: 0] attrib_delay;

   logic [5: 0] opcode;
   logic [9: 0] src;
   logic [9: 0] dest;
   logic [12:0] len;
   logic [4: 0] attrib;

   assign opcode =  fifo_r_data[ 5: 0];
   assign src    = {fifo_r_data[12: 6], 6'b0};
   assign dest   = {fifo_r_data[19:13], 6'b0};
   assign len    = {fifo_r_data[26:20], 6'b0};
   assign attrib =  fifo_r_data[31:27];


   // Comb logic as we want to update the read enable signal within the same cycle
   always_comb begin
      fifo_r_en = 0;
      case (current_state)
         DECODE_IDLE: begin
            if (!inst_empty) begin
               case (fifo_r_data[5:0])
                  OP_NOP:
                     fifo_r_en = 1;
                  OP_LOAD_FULL :
                     fifo_r_en = 1;
                  OP_LOAD_LOW  :
                     fifo_r_en = 1;
               endcase
            end
         end
         DECODE_LOAD_FULL_LOW: begin
            if (!inst_empty)
               fifo_r_en = 1;
            end
         DECODE_LOAD_FULL_HIGH: begin
            if (!inst_empty)
               fifo_r_en = 1;
            end
         DECODE_WAITING_ON_PIPELINE: begin
            if (local_to_dma_ch.t_valid && local_to_dma_ch.t_last)
               fifo_r_en = 1;
            end
      endcase
   end

   // Instruction fetch and instruction decode
   always_ff @(posedge clk or posedge rst)
   begin
      if (rst) begin
         base_addr_rd       <= 64'b0;
         base_addr_wr       <= 64'b0;
         control_state      <= CTRL_IDLE;
         r_src              <= 'd0;
         r_dest             <= 'd0;
         r_len              <= 'd0;
         r_valid_to_local   <= 'd0;
         r_valid_from_local <= 'd0;
         fifo_w_en          <= 'd0;
         routing_dest       <= 'd0;
      end
      else begin
         // Maintain low unless we are in a state that requires otherwise.
         fifo_w_en <= 0;

         if (inst_en) begin
            inst_read <= inst_empty ? 0 : fifo_r_data;

               if (&inst_we) begin
                  if (!inst_full) begin
                     $display("Receddived an instruction: %b", inst_write);
                     fifo_w_data <= inst_write;
                     fifo_w_en   <= 1;
                  end
                  // If FIFO is full, input is discarded
               end
         end

         case (current_state)
            DECODE_IDLE: begin
               if (!inst_empty) begin
                  case (opcode)
                     OP_NOP: begin
                        current_state <= DECODE_IDLE;
                        routing_dest  <= 'd0;
                     end
                     OP_LOAD_FULL: begin
                        $display("Executing LOAD_FULL");
                        current_state <= DECODE_LOAD_FULL_LOW;
                        routing_dest  <= 'd0;
                     end
                     OP_LOAD_LOW: begin
                        $display("Executing LOAD_LOW");
                        if (attrib == 5'h0)
                           base_addr_rd[26:6] <= fifo_r_data[26:6];
                        else if (attrib == 5'h1)
                           base_addr_wr[26:6] <= fifo_r_data[26:6];
                        routing_dest  <= 'd0;
                     end
                     OP_MOV: begin
                        $display("Executing MOV");
                        control_state <= CTRL_INIT;
                        current_state <= DECODE_WAITING_ON_PIPELINE;
                        routing_dest  <= 'd0;
                     end
                     default:
                        current_state <= DECODE_IDLE;
                  endcase
                  src_delay    <= src;
                  dest_delay   <= dest;
                  len_delay    <= len;
                  attrib_delay <= attrib;
               end
            end
            DECODE_LOAD_FULL_LOW: begin
               if (!inst_empty) begin
                  $display("Load %x to low dword", fifo_r_data);
                  current_state    <= DECODE_LOAD_FULL_HIGH;
                  if (attrib_delay == 5'h0)
                     base_addr_rd[31: 0] <= fifo_r_data &~63;
                  else if (attrib_delay == 5'h1)
                     base_addr_wr[31: 0] <= fifo_r_data &~63;
               end else
                  current_state    <= DECODE_LOAD_FULL_LOW;
            end
            DECODE_LOAD_FULL_HIGH: begin
               if (!inst_empty) begin
                  $display("Load %x to high dword", fifo_r_data);
                  current_state    <= DECODE_IDLE;
                  if (attrib_delay == 5'h0)
                     base_addr_rd[63:32] <= fifo_r_data;
                  else if (attrib_delay == 5'h1)
                     base_addr_wr[63:32] <= fifo_r_data;
               end else
                  current_state    <= DECODE_LOAD_FULL_HIGH;
            end
            DECODE_WAITING_ON_PIPELINE: begin
                 if (local_to_dma_ch.t_valid && local_to_dma_ch.t_last)
                 begin
                    $display("Execution of command finished.");
                    current_state <= DECODE_IDLE;
                 end else current_state <= DECODE_WAITING_ON_PIPELINE;
              end
            default: current_state <= DECODE_IDLE;
         endcase

         case (control_state)
            CTRL_IDLE: begin
               if (r_ready_to_local & r_valid_to_local) r_valid_to_local <= 0;
               if (r_ready_from_local & r_valid_from_local) r_valid_from_local <= 0;
            end
            CTRL_INIT: begin
               r_src              <= base_addr_rd + src_delay;
               r_dest             <= base_addr_wr + dest_delay;
               r_len              <= len_delay;
               r_valid_to_local   <= 1;
               r_valid_from_local <= 1;
               control_state      <= CTRL_IDLE;
            end
            default: control_state <= CTRL_IDLE;
         endcase
      end
   end

endmodule

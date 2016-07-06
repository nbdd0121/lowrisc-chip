/*
* Possible extension: take input from FIFO, rather than directly from CPU
*/
module video_dma_controller #(
		parameter LOWRISC_TILELINK_DATA_WIDTH = 64,
		parameter VIDEOMEM_SIZE = 18 // 2^18 -> 256 KiB
	)(
		input		  clk,		   // Bus clock
		input		  rst,

		// DMA request inputs
		output		   fetch_data,
		input  [15:0]  read_from,
		input  [15:0]  length_data,
		inout  [17:0]  write_to,		// Needs to be the same as parameter VIDEOMEM_SIZE-1
		input 		   rd_en, 			// read enable for video RAM

		// Video memory 
		output [LOWRISC_TILELINK_DATA_WIDTH-1:0] dma_data,
		input [31:0]   videomem_rddata,   // For future use with acceleration
		output reg     videomem_we
	);
  
localparam IDLE			 = 3'b000,
		   INIT_ATTR	 = 3'b001,
		   DECIDE_LENGTH = 3'b010,
		   ASSERT_REQ	 = 3'b011,
		   WAIT_ACK		 = 3'b100;

reg   [2:0]                              dma_state;
logic                                    ack_fetch_data;

dma_descriptor_process #(
	.IDLE            (IDLE),
	.INIT_ATTR       (INIT_ATTR),
	.DECIDE_LENGTH   (DECIDE_LENGTH),
	.ASSERT_REQ      (ASSERT_REQ),
	.WAIT_ACK        (WAIT_ACK)
	)
	dma_descriptor_process_0
	(
	.clk		 	(clk),
	.rst		 	(rst),
	.descp_avail 	(rd_en),
	.read_from   	(read_from),
	.write_to		(write_to),
	.length_data 	(length_data),
	.fetch_data 	(fetch_data),
	.dma_data 		(dma_data),
	.proc_state     (dma_state),
	.ack_fetch_data (ack_fetch_data)
	);


always @(posedge clk)
	begin
		ack_fetch_data <= 1'b0;
		if (dma_state == ASSERT_REQ)
			begin 
				videomem_we <= 1'b0;
				// TODO: logic for reading from DDR and placing on data wire
				// assert ack_fetch_data once done
				ack_fetch_data <= 1'b1;
			end
		else
			begin 
				videomem_we <= 1'b1;
				// Can read from BRAM
			end
	end


endmodule // video_dma_controller
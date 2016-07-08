module write_transaction #(
        parameter LOWRISC_AXI_DATA_WIDTH = 64,
        parameter VIDEOMEM_SIZE          = 18
    )(
    input wire clk,
    input wire rst,

    // Request (from DMA)
    input                                   wire data_avail,
    input [VIDEOMEM_SIZE-1:0]               wire addr,
    input [LOWRISC_AXI_DATA_WIDTH-1:0]      wire data,
    input                                   wire final_packet,

    // Address Channel
    output [VIDEOMEM_SIZE-1:0] wire AWADDR,
    output                     wire AWVALID,
    input                      wire AWREADY,

    // Data Channel
    output [LOWRISC_AXI_DATA_WIDTH-1:0] logic WDATA,
    output                              logic WLAST,
    output                              logic WVALID,
    input                               wire  WREADY,

    // Response Channel
    input  wire  BRESP,
    input  wire  BVALID,
    output logic BREADY
    );

    localparam 
           IDLE     = 2'b00,
           ADDR     = 2'b01,
           WRITE    = 2'b10,
           RESPONSE = 2'b11;

    reg [1:0] axi_write_state, axi_write_state_next;

    always @(*)
        begin 
            axi_write_state_next = axi_write_state;
            case (axi_write_state)
                IDLE:
                    begin 
                        if (data_avail)
                            begin 
                                axi_write_state_next = ADDR;
                            end
                    end
                ADDR:
                    begin 
                        AWADDR = addr;
                        AWVALID = 1'b1;
                        if (AWREADY == 1'b0)
                            begin 
                                axi_write_state_next = ADDR;
                        	end
                        else
                            begin
                                axi_write_state_next = WRITE;
                            end
                    end
                WRITE:
                    begin 
                        WDATA = data;
                        WVALID = 1'b1;
                        if (WREADY == 1'b0)
                            begin 
                            	axi_write_state_next = WRITE;
                            end
                        else
                            begin 
                                axi_write_state_next = RESPONSE
                            end
                    end
                RESPONSE:
                    begin
                        BREADY = 1'b1;
                        if (BVALID == 1'b0)
                            begin 
                                axi_write_state_next = RESPONSE;
                            end
                        else
                            begin 
                                axi_write_state_next = IDLE;
                            end
                    end
                default : begin end

            endcase // axi_write_state
        end


    always @(posedge clk or posedge rst)
        begin 
            if (rst)
                begin
                    axi_write_state <= IDLE;
                end
            else
                begin 
                    axi_write_state <= axi_write_state_next;
                end
        end


endmodule // write_transaction



module read_transaction #(
        parameter LOWRISC_AXI_DATA_WIDTH = 64,
        parameter VIDEOMEM_SIZE = 18
    )(
    input wire clk,
    input wire rst,

    // Request (from DMA)
    input                               wire data_req,
    input  [VIDEOMEM_SIZE-1:0]          wire addr,
    output [LOWRISC_AXI_DATA_WIDTH-1:0] wire data,

    // Address Channel
    output [VIDEOMEM_SIZE-1:0] wire ARADDR,
    output                     wire ARVALID,
    input                      wire ARREADY,

    // Data Channel
    output [LOWRISC_AXI_DATA_WIDTH-1:0] logic RDATA,
    output                              logic RLAST,
    output                              logic RVALID,
    input                               wire  RREADY,

    );

    localparam 
           IDLE     = 2'b00,
           ADDR     = 2'b01,
           READ     = 2'b10;

    reg [1:0] axi_read_state, axi_read_state_next;


    always @(*)
        begin 
            axi_read_state_next = axi_read_state;
            case (axi_read_state)
                IDLE:
                    begin 
                        if (data_req)
                            begin 
                                axi_read_state_next = ADDR;
                            end
                    end
                ADDR:
                    begin 
                        ARADDR = addr;
                        ARVALID = 1'b1;
                        if (ARREADY == 1'b0)
                            begin
                                axi_read_state_next = ADDR;
                            end
                        else
                            begin
                                axi_read_state_next = READ
                            end
                    end
                READ:
                    begin
                    	RREADY = 1'b1;
                        if (RVALID == 1'b0)
                            begin
                                axi_read_state_next = READ;
                            end
                        else
                            begin
                                data = RDATA;
                                if (RLAST == 1'b1)
                                    begin 
                                    	axi_read_state_next = IDLE;
                                    end
                                else
                                    begin 
                                    	axi_read_state_next = READ;
                                    end
                            end
                    end
                default : begin end

            endcase // axi_read_state
        end


    always @(posedge clk or posedge rst)
        begin 
            if (rst)
                begin
                    axi_read_state <= IDLE;
                end
            else
                begin 
                    axi_read_state <= axi_read_state_next;
                end
        end


endmodule // read_transaction
`include "consts.vh"

module write_transaction #(
        parameter LOWRISC_AXI_DATA_WIDTH = `ROCKET_MEM_DAT_WIDTH,
        parameter VIDEOMEM_SIZE          = 18
    )(
    input wire clk,
    input wire rst,

    // Request (from DMA)
    input wire data_avail,
    input wire [VIDEOMEM_SIZE-1:0] addr,
    input wire [LOWRISC_AXI_DATA_WIDTH-1:0] data,
    input wire final_packet,

    // Address Channel
    output reg [VIDEOMEM_SIZE-1:0] AWADDR,
    output reg                 AWVALID,
    input  reg                 AWREADY,

    // Data Channel
    output reg [LOWRISC_AXI_DATA_WIDTH-1:0] WDATA,
    output reg                              WLAST,
    output reg                              WVALID,
    input  reg                              WREADY,

    // Response Channel
    input  reg  BRESP,
    input  reg  BVALID,
    output reg  BREADY
    );

    enum { AXIW_IDLE, AXIW_ADDR, AXIW_WRITE, AXIW_RESPONSE } axi_write_state, axi_write_state_next;

    always @(*)
        begin 
            axi_write_state_next = axi_write_state;
            case (axi_write_state)
                AXIW_IDLE:
                    begin 
                        if (data_avail)
                            begin 
                                axi_write_state_next = AXIW_ADDR;
                            end
                    end
                AXIW_ADDR:
                    begin 
                        AWADDR = addr;
                        AWVALID = 1'b1;
                        if (AWREADY == 1'b0)
                            begin 
                                axi_write_state_next = AXIW_ADDR;
                        	end
                        else
                            begin
                                axi_write_state_next = AXIW_WRITE;
                            end
                    end
                AXIW_WRITE:
                    begin 
                        WDATA = data;
                        WVALID = 1'b1;
                        if (WREADY == 1'b0)
                            begin 
                            	axi_write_state_next = AXIW_WRITE;
                            end
                        else
                            begin 
                                axi_write_state_next = AXIW_RESPONSE;
                            end
                    end
                AXIW_RESPONSE:
                    begin
                        BREADY = 1'b1;
                        if (BVALID == 1'b0)
                            begin 
                                axi_write_state_next = AXIW_RESPONSE;
                            end
                        else
                            begin 
                                axi_write_state_next = AXIW_IDLE;
                            end
                    end
                default : begin end

            endcase // axi_write_state
        end


    always @(posedge clk or posedge rst)
        begin 
            if (rst)
                begin
                    axi_write_state <= AXIW_IDLE;
                end
            else
                begin 
                    axi_write_state <= axi_write_state_next;
                end
        end


endmodule // write_transaction



module read_transaction #(
        parameter LOWRISC_AXI_DATA_WIDTH = `ROCKET_MEM_DAT_WIDTH,
        parameter VIDEOMEM_SIZE = 18
    )(
    input wire clk,
    input wire rst,

    // Request (from DMA)
    input  reg data_req,
    input  reg [VIDEOMEM_SIZE-1:0] addr,
    output reg [LOWRISC_AXI_DATA_WIDTH-1:0] data,

    // Address Channel
    output reg [VIDEOMEM_SIZE-1:0] ARADDR,
    output reg                     ARVALID,
    input  reg                     ARREADY,

    // Data Channel
    output reg [LOWRISC_AXI_DATA_WIDTH-1:0] RDATA,
    output reg                              RLAST,
    output reg                              RVALID,
    input  reg                              RREADY

    );


    enum {AXIR_IDLE, AXIR_ADDR, AXIR_READ} axi_read_state, axi_read_state_next;


    always @(*)
        begin 
            axi_read_state_next = axi_read_state;
            case (axi_read_state)
                AXIR_IDLE:
                    begin 
                        if (data_req)
                            begin 
                                axi_read_state_next = AXIR_ADDR;
                            end
                    end
                AXIR_ADDR:
                    begin 
                        ARADDR = addr;
                        ARVALID = 1'b1;
                        if (ARREADY == 1'b0)
                            begin
                                axi_read_state_next = AXIR_ADDR;
                            end
                        else
                            begin
                                axi_read_state_next = AXIR_READ;
                            end
                    end
                AXIR_READ:
                    begin
                    	RREADY = 1'b1;
                        if (RVALID == 1'b0)
                            begin
                                axi_read_state_next = AXIR_READ;
                            end
                        else
                            begin
                                data = RDATA;
                                if (RLAST == 1'b1)
                                    begin 
                                    	axi_read_state_next = AXIR_IDLE;
                                    end
                                else
                                    begin 
                                    	axi_read_state_next = AXIR_READ;
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
                    axi_read_state <= AXIR_IDLE;
                end
            else
                begin 
                    axi_read_state <= axi_read_state_next;
                end
        end


endmodule // read_transaction
/*
* Possible extension: take input from FIFO, rather than directly from CPU
*
* 146------145-----------81----------------17------------0
* | Enable |  Read From  |   Length Data   |  Write To   |
* --------------------------------------------------------
*/
`include "consts.vh"
import pkg_dma_type::Dma_State;

module video_dma_controller #(
        parameter LOWRISC_AXI_DATA_WIDTH = `ROCKET_MEM_DAT_WIDTH,
        parameter VIDEOMEM_SIZE = 18 // 2^18 -> 256 KiB
    )(
        input          clk,           // Bus clock
        input          rst,

        input dmareqmem_we,
        input dmareqmem_addr,
        input dmareqmem_wrdata,

        // Video memory
        output [LOWRISC_AXI_DATA_WIDTH-1:0] dma_data,
        input [31:0] videomem_rddata,   // For future use with acceleration
        output reg   videomem_we,

        // AXI interaction
        // Address Channel
        output [VIDEOMEM_SIZE-1:0] ARADDR,
        output                     ARVALID,
        input                      ARREADY,

        // Data Channel
        output [LOWRISC_AXI_DATA_WIDTH-1:0] RDATA,
        output                              RLAST,
        output                              RVALID,
        input                               RREADY
    );

typedef enum { DMA_IDLE, DMA_INIT_ATTR, DMA_DECIDE__LENGTH, 
        DMA_FIRST_ASSERT_REQ, DMA_ASSERT_REQ, DMA_WAIT_ACK} Dma_State;
pkg_dma_type::Dma_State dma_state;

// DMA request inputs
reg  [147:0] req_packet;

reg         enable;
reg  [63:0] read_from;
reg  [63:0] length_data;
reg  [17:0] write_to;     
reg         rd_en;            


reg          fetch_data;
logic        ack_fetch_data;

// Receiving requests from CPU (via BRAM)
single_port_bram single_port_bram_0 (
    .clk  (clk),
    .en   (rd_en),
    .we   (dmareqmem_we),
    .addr (dmareqmem_addr),
    .write(dmareqmem_wrdata),
    .read (req_packet)
    );


always_ff @(posedge clk)
    begin
        if (!dmareqmem_we)
            begin
                write_to    = req_packet[17:0];
                length_data = req_packet[81:18];
                read_from   = req_packet[145:82];
                enable      = req_packet[146];
            end
    end

dma_descriptor_process
    dma_descriptor_process_0
    (
    .clk            (clk),
    .rst            (rst),
    .descp_avail    (enable),
    .read_from      (read_from),
    .write_to       (write_to),
    .length_data    (length_data),
    .fetch_data     (fetch_data),
    .proc_state     (dma_state),
    .ack_fetch_data (ack_fetch_data)
    );


// Placing read request on AXI bus

reg perform_read;

read_transaction #(
    .LOWRISC_AXI_DATA_WIDTH (LOWRISC_AXI_DATA_WIDTH),
    .VIDEOMEM_SIZE          (VIDEOMEM_SIZE)
    )
    read_transaction_0 (
        .clk(clk),
        .rst(rst),

        .data_req (perform_read),
        .addr     (read_from),
        .data     (dma_data),

        .ARADDR   (ARADDR), 
        .ARVALID  (ARVALID), 
        .ARREADY  (ARREADY), 

        .RDATA    (RDATA), 
        .RLAST    (RLAST), 
        .RVALID   (RVALID), 
        .RREADY   (RREADY) 
    );


always @(posedge clk)
    begin
        ack_fetch_data <= 1'b0;
        case (dma_state)
            DMA_FIRST_ASSERT_REQ:
                begin
                    videomem_we    <= 1'b0;
                    // dma_data       <= from DDR
                    // TODO: logic for reading from DDR and placing on data wire

                    ack_fetch_data <= 1'b1;
                end
            DMA_ASSERT_REQ:    
                begin
                    videomem_we    <= 1'b0;
                    // dma_data       <= from DDR

                    // TODO: logic for reading from DDR and placing on data wire
                    // assert ack_fetch_data once done
                    ack_fetch_data <= 1'b1;
                end
            default: 
                begin
                    videomem_we <= 1'b1;
                end
        endcase // dma_state
    end


endmodule // video_dma_controller
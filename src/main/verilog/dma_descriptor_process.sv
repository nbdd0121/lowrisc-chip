/*
*
* Reads descriptors from FIFO, performs read from cache and write to BRAM
* 
*/
import pkg_dma_type::*;

module dma_descriptor_process
    ( 
        input  wire        clk,
        input  wire        rst,
        input  wire        descp_avail,     // read enable
        input  wire [63:0] read_from, 
        inout  wire [17:0] write_to,  
        input  wire [63:0] length_data,      
        output reg         fetch_data,

        output logic        videomem_we,
        output pkg_dma_type::Dma_State    proc_state,
        input  wire         ack_fetch_data

    );

    pkg_dma_type::Dma_State proc_state_next;
    reg          fetch_data_next;
    reg   [15:0] read_from_local, read_from_local_next;
    reg   [17:0] write_to_local, write_to_local_next;
    reg   [15:0] length_data_local, length_data_local_next;
    reg   [15:0] remain_length, remain_length_next;

parameter PKT_LENGTH = 64; // AXI4: 32, 64, 128, or 256 bits

always @(*)
    begin
        read_from_local_next   = read_from;
        proc_state_next        = proc_state;
        fetch_data_next        = 1'b0;
        length_data_local_next = length_data;
        write_to_local_next    = write_to;
        remain_length_next     = remain_length;
        length_data_local_next = length_data_local;

        case(proc_state)
           DMA_IDLE: 
                begin
                    if (descp_avail) 
                        begin
                            proc_state_next = DMA_INIT_ATTR;
                        end
                end
            DMA_INIT_ATTR:
                begin
                    remain_length_next   = length_data_local;
                    read_from_local_next = read_from_local;
                    write_to_local_next  = write_to_local;
                    proc_state_next      = DMA_DECIDE_LENGTH;
                end
            DMA_DECIDE_LENGTH:
                begin
                    proc_state_next = DMA_FIRST_ASSERT_REQ;
                    if(remain_length >= PKT_LENGTH)
                        length_data_local_next = PKT_LENGTH;
                    else 
                        length_data_local_next = remain_length;
                end
            DMA_FIRST_ASSERT_REQ:
                begin
                    fetch_data_next        = 1'b1;
                    read_from_local_next   = read_from_local;
                    write_to_local_next    = write_to_local;
                    length_data_local_next = length_data_local;
                    remain_length_next     = remain_length - length_data_local;             
                    proc_state_next        = DMA_WAIT_ACK;
                end
            DMA_ASSERT_REQ: // at the moment this state is unused, need to put checks in for when to loop
                begin
                    fetch_data_next        = 1'b1;
                    read_from_local_next   = read_from_local;
                    write_to_local_next    = write_to_local;
                    length_data_local_next = length_data_local;
                    remain_length_next     = remain_length - length_data_local;             
                    proc_state_next        = DMA_WAIT_ACK;
                end
            DMA_WAIT_ACK:
                begin 
                    if (ack_fetch_data)
                        begin
                            fetch_data_next = 1'b0;
                            if (remain_length == 'd0) // no more data
                                begin
                                    proc_state_next = DMA_IDLE;
                                end
                            else
                                begin 
                                    proc_state_next      = DMA_DECIDE_LENGTH;
                                    read_from_local_next = read_from_local + {length_data_local, 2'b00}; // length_data_local is multiplied by 4 to reflect the value in bytes as it is in dwords
                                    write_to_local_next  = write_to_local + {length_data_local, 2'b00};
                                end
                        end
                    else
                        begin
                            fetch_data_next        = 1'b1;
                            read_from_local_next   = read_from_local;
                            write_to_local_next    = write_to_local;
                            length_data_local_next = length_data_local;
                        end
                end
            default : begin end 
        endcase // proc_state
    end

always @(posedge clk or posedge rst)
    begin
        if (rst)
            begin
                proc_state        <= DMA_IDLE;
                fetch_data        <= 1'b0;
                read_from_local   <= 'd0;
                length_data_local <= 'd0;
                remain_length     <= 'd0;
            end
        else
            begin 
                proc_state        <= proc_state_next;
                fetch_data        <= fetch_data_next;
                read_from_local   <= read_from_local_next;
                write_to_local    <= write_to_local_next;
                length_data_local <= length_data_local_next;
                remain_length     <= remain_length_next;
            end
    end

endmodule // dma_descriptor_process
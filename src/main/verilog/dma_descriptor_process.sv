/*
* Reads descriptors from FIFO, performs read from cache and write to BRAM
* 
* ADDR_WIDTH = 16,
* DATA_WIDTH = 32
*/
module dma_descriptor_process #(
    parameter IDLE             = 3'b000,
    parameter INIT_ATTR        = 3'b001,
    parameter DECIDE_LENGTH    = 3'b010,
    parameter FIRST_ASSERT_REQ = 3'b011,
    parameter ASSERT_REQ       = 3'b100,
    parameter WAIT_ACK         = 3'b101
    )
    ( 
        input  wire        clk,
        input  wire        rst,
        input  wire        descp_avail,     // read enable
        input  wire [15:0] read_from, 
        inout  wire [17:0] write_to,  
        input  wire [15:0] length_data,      
        output reg         fetch_data,

        output logic        videomem_we,
        output logic [2:0]  proc_state,
        input  wire         ack_fetch_data

    );

    reg   [2:0]  proc_state_next;
    reg          fetch_data_next;
    reg   [15:0] read_from_local, read_from_local_next;
    reg   [17:0] write_to_local, write_to_local_next;
    reg   [15:0] length_data_local, length_data_local_next;
    reg   [15:0] remain_length, remain_length_next;

parameter PKT_LENGTH = 'd8; // Set for TileLink, can be changed based on bus interface protocol and burst length supported

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
            IDLE: 
                begin
                    if (descp_avail) 
                        begin
                            proc_state_next = INIT_ATTR;
                        end
                end
            INIT_ATTR:
                begin
                    remain_length_next   = length_data_local;
                    read_from_local_next = read_from_local;
                    write_to_local_next  = write_to_local;
                    proc_state_next      = DECIDE_LENGTH;
                end
            DECIDE_LENGTH:
                begin
                    proc_state_next = FIRST_ASSERT_REQ;
                    if(remain_length >= PKT_LENGTH)
                        length_data_local_next = PKT_LENGTH;
                    else 
                        length_data_local_next = remain_length;
                end
            FIRST_ASSERT_REQ:
                begin
                    fetch_data_next        = 1'b1;
                    read_from_local_next   = read_from_local;
                    write_to_local_next    = write_to_local;
                    length_data_local_next = length_data_local;
                    remain_length_next     = remain_length - length_data_local;             
                    proc_state_next        = WAIT_ACK;
                end
            ASSERT_REQ:
                begin
                    fetch_data_next        = 1'b1;
                    read_from_local_next   = read_from_local;
                    write_to_local_next    = write_to_local;
                    length_data_local_next = length_data_local;
                    remain_length_next     = remain_length - length_data_local;             
                    proc_state_next        = WAIT_ACK;
                end
            WAIT_ACK:
                begin 
                    if (ack_fetch_data)
                        begin
                            fetch_data_next = 1'b0;
                            if (remain_length == 'd0) // no more data
                                begin
                                    proc_state_next = IDLE;
                                end
                            else
                                begin 
                                    proc_state_next      = DECIDE_LENGTH;
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
                proc_state        <= IDLE;
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
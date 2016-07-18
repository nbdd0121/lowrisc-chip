module single_port_bram #(
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 32,
    parameter DEFAULT_CONTENT = "video.mem" // TODO: Come up with a default 
) (
    input  wire                          clk,
    input  wire                          en,
    input  wire [(DATA_WIDTH / 8) - 1:0] we,
    input  wire [ADDR_WIDTH - 1:0]       addr,
    input  wire [DATA_WIDTH - 1:0]       write,
    output reg  [DATA_WIDTH - 1:0]       read
);

reg [DATA_WIDTH - 1:0] mem [0:2 ** ADDR_WIDTH - 1];

always_ff @(posedge clk) begin
    read <= mem[addr];
    foreach(we[i])
        if(we[i])
            mem[addr][i*8+:8] <= write[i*8+:8];
end


initial $readmemh(DEFAULT_CONTENT, mem);

endmodule
module clockdiv(
	input wire clk, 	// master clock: 100MHz
	input wire clr, 	// asynchronous reset
	output wire dclk 	// pixel clock: 25MHz
);

// 2‐bitcountervariable
reg [1:0] q;

// Clock divider‐‐
// Each bit in q is a clock signal that is
// only a fraction of the master clock.
always @(posedge clk or posedge clr)
begin
	// reset condition
	if (clr == 1)
	q <= 0;
	// increment counter byone
	else
	q <= q + 1;
end

// 100Mhz ÷ 2^2 = 25MHz
assign dclk = q[1];

endmodule

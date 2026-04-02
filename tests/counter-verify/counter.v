// 4-bit counter that outputs each bit to a separate IO pad.
// After N rising clock edges, counter should equal N mod 16.
// This verifies carry chain propagation and FF behavior.

module counter (
    input  wire clk,
    output wire [3:0] out
);

    reg [3:0] count;

    always @(posedge clk)
        count <= count + 4'd1;

    assign out = count;

endmodule

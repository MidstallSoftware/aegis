// 4-bit shift register.
// Smaller than 8-bit to reduce routing pressure.
// Data shifts from din through 4 FFs to dout on each clock.

module shift (
    input  wire clk,
    input  wire din,
    output wire dout
);

    reg [3:0] sr;

    always @(posedge clk)
        sr <= {sr[2:0], din};

    assign dout = sr[3];

endmodule

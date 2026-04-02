// Combinational logic gates.
// Tests that LUT INIT values are correctly packed and simulated.

module gates (
    input  wire a,
    input  wire b,
    output wire out_and,
    output wire out_or,
    output wire out_xor,
    output wire out_not
);

    assign out_and = a & b;
    assign out_or  = a | b;
    assign out_xor = a ^ b;
    assign out_not = ~a;

endmodule

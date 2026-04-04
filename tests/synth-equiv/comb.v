// Pure combinational logic test for synthesis equivalence.
module comb (
    input  wire a,
    input  wire b,
    input  wire c,
    input  wire d,
    output wire y_and,
    output wire y_or,
    output wire y_xor,
    output wire y_mux
);
    assign y_and = a & b & c & d;
    assign y_or  = a | b | c | d;
    assign y_xor = a ^ b ^ c ^ d;
    assign y_mux = c ? a : b;
endmodule

// Formal properties for the Aegis LUT4 module.
// Proves the LUT implements an exact truth table lookup.
module lut4_props (
    input  wire [15:0] cfg,
    input  wire        in0,
    input  wire        in1,
    input  wire        in2,
    input  wire        in3,
    input  wire        out
);
    wire [3:0] addr = {in3, in2, in1, in0};

    // The LUT output must equal the cfg bit at the address formed by inputs
    always @(*) begin
        assert (out == cfg[addr]);
    end
endmodule

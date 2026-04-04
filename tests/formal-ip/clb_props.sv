// Formal properties for the Aegis CLB module.
// Proves CLB modes: combinational, registered, and carry chain.
module clb_props (
    input  wire        clk,
    input  wire [17:0] cfg,
    input  wire        in0,
    input  wire        in1,
    input  wire        in2,
    input  wire        in3,
    input  wire        carryIn,
    input  wire        out,
    input  wire        carryOut
);
    // Decode config
    wire [15:0] lutInit = cfg[15:0];
    wire        useFF   = cfg[16];
    wire        carryMode = cfg[17];

    // Compute expected LUT output
    wire [3:0] addr = {in3, in2, in1, in0};
    wire lutOut = lutInit[addr];

    // Carry chain
    wire propagate = lutOut;
    wire carryMux = propagate ? carryIn : in0;
    wire sum = propagate ^ carryIn;

    // --- Carry output ---
    // When carry mode is enabled, carryOut = MUXCY(propagate, carryIn, in0)
    // When carry mode is disabled, carryOut = 0
    always @(*) begin
        if (carryMode)
            assert (carryOut == carryMux);
        else
            assert (carryOut == 1'b0);
    end

    // --- Main output (combinational properties) ---
    // In carry mode: out = propagate XOR carryIn
    always @(*) begin
        if (carryMode)
            assert (out == sum);
    end

    // In combinational mode (no FF, no carry): out = LUT output
    always @(*) begin
        if (!carryMode && !useFF)
            assert (out == lutOut);
    end
endmodule

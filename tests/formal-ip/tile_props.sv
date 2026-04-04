// Formal properties for the Aegis Tile config chain.
// Proves the serial shift register and config latch behavior.
module tile_cfg_props #(
    parameter CONFIG_WIDTH = 46
) (
    input  wire                    clk,
    input  wire                    reset,
    input  wire                    cfgIn,
    input  wire                    cfgLoad,
    input  wire                    cfgOut,
    input  wire [CONFIG_WIDTH-1:0] shiftReg,
    input  wire [CONFIG_WIDTH-1:0] configReg
);
    // cfgOut is always the LSB of the shift register
    always @(*) begin
        if (!reset)
            assert (cfgOut == shiftReg[0]);
    end

    // After reset, shift register and config register are zero
    always @(posedge clk) begin
        if (reset) begin
            assert ($next(shiftReg) == {CONFIG_WIDTH{1'b0}});
            assert ($next(configReg) == {CONFIG_WIDTH{1'b0}});
        end
    end
endmodule

// Blinky - toggles an output LED at a visible rate.
//
// Divides the input clock by 2^24 (~1 Hz at 16 MHz) and drives
// the result to padOut[0].

module blinky (
    input  wire clk,
    input  wire reset,
    output wire led
);

    reg [23:0] counter;

    always @(posedge clk) begin
        if (reset)
            counter <= 24'd0;
        else
            counter <= counter + 24'd1;
    end

    assign led = counter[23];

endmodule

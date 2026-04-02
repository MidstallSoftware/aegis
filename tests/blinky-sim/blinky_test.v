// Test blinky - short counter for fast simulation verification.
// Divides clock by 2^4 (16 cycles) instead of 2^24.

module blinky (
    input  wire clk,
    input  wire reset,
    output wire led
);

    reg [3:0] counter;

    always @(posedge clk) begin
        if (reset)
            counter <= 4'd0;
        else
            counter <= counter + 4'd1;
    end

    assign led = counter[3];

endmodule

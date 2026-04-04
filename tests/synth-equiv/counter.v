// Sequential counter test for synthesis equivalence.
module counter (
    input  wire clk,
    input  wire reset,
    output wire [3:0] count
);
    reg [3:0] cnt;
    always @(posedge clk) begin
        if (reset)
            cnt <= 4'd0;
        else
            cnt <= cnt + 4'd1;
    end
    assign count = cnt;
endmodule

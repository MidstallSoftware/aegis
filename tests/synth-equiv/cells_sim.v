// Simulation models for Aegis FPGA cells (no blackbox attribute).
// Used by SymbiYosys for equivalence checking.

module AEGIS_LUT4 (
    input  wire       in0,
    input  wire       in1,
    input  wire       in2,
    input  wire       in3,
    output wire       out
);
    parameter [15:0] INIT = 16'h0000;
    wire [3:0] addr = {in3, in2, in1, in0};
    assign out = INIT[addr];
endmodule

module AEGIS_DFF (
    input  wire clk,
    input  wire d,
    output reg  q
);
    always @(posedge clk)
        q <= d;
endmodule

module AEGIS_CARRY (
    input  wire p,
    input  wire g,
    input  wire ci,
    output wire co,
    output wire sum
);
    assign co  = p ? ci : g;
    assign sum = p ^ ci;
endmodule

module AEGIS_BRAM (
    input  wire                    clk,
    input  wire [6:0]  a_addr,
    input  wire [7:0]  a_wdata,
    input  wire                    a_we,
    output reg  [7:0]  a_rdata,
    input  wire [6:0]  b_addr,
    input  wire [7:0]  b_wdata,
    input  wire                    b_we,
    output reg  [7:0]  b_rdata
);
    parameter INIT = 0;
    reg [7:0] mem [0:127];
    always @(posedge clk) begin
        if (a_we) mem[a_addr] <= a_wdata;
        a_rdata <= mem[a_addr];
        if (b_we) mem[b_addr] <= b_wdata;
        b_rdata <= mem[b_addr];
    end
endmodule

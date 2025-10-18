// regfile.v
// Single-cycle regfile with write-through (combinational read sees same-cycle write)
`timescale 1ns/1ps
module regfile (
    input  wire        clk,
    input  wire        rst_n,        // active-low async reset
    input  wire        reg_write,    // write enable (from wb controller)
    input  wire [4:0]  rs1_idx,      // read port 1 index
    input  wire [4:0]  rs2_idx,      // read port 2 index
    input  wire [4:0]  rd_idx,       // write destination index
    input  wire [31:0] rd_wdata,     // write data
    output reg  [31:0] rs1_data,     // read data 1 (combinational style output)
    output reg  [31:0] rs2_data      // read data 2 (combinational style output)
);

    // register array
    reg [31:0] regs [0:31];
    integer i;

    // synchronous write, asynchronous reset
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // reset all registers to zero
            for (i = 0; i < 32; i = i + 1) begin
                regs[i] <= 32'b0;
            end
        end else begin
            // write on rising edge if enabled and not writing x0
            if (reg_write && (rd_idx != 5'b0)) begin
                regs[rd_idx] <= rd_wdata;
            end
            // guarantee x0 stays zero (extra protection)
            regs[0] <= 32'b0;
        end
    end

    // combinational read with write-through: show write data if write targets same index
    always @(*) begin
        // default read from array
        rs1_data = (rs1_idx == 5'b0) ? 32'b0 : regs[rs1_idx];
        rs2_data = (rs2_idx == 5'b0) ? 32'b0 : regs[rs2_idx];

        // write-through forwarding if a write is occurring this cycle
        if (reg_write && (rd_idx != 5'b0)) begin
            if (rd_idx == rs1_idx) rs1_data = rd_wdata;
            if (rd_idx == rs2_idx) rs2_data = rd_wdata;
        end
    end

endmodule

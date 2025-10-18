// wb_controller_single.v
// Single-cycle combinational writeback controller
`timescale 1ns/1ps
module wb_controller_single (
    input  wire        dec_reg_write,  // from decoder
    input  wire [1:0]  dec_wb_sel,     // 00=ALU,01=MEM,10=PC+4,11=LUI
    input  wire [4:0]  dec_rd,         // destination index
    input  wire [31:0] dec_imm_u,      // imm<<12 for LUI if needed

    // data sources (assumed available in same cycle)
    input  wire [31:0] alu_result,
    input  wire [31:0] mem_read_data,
    input  wire [31:0] pc_plus_4,

    // outputs to regfile (combinational)
    output reg         rf_we,
    output reg  [4:0]  rf_wd_idx,
    output reg  [31:0] rf_wd_data
);

    always @(*) begin
        // default
        rf_we = 1'b0;
        rf_wd_idx = 5'b0;
        rf_wd_data = 32'b0;

        if (dec_reg_write && (dec_rd != 5'd0)) begin
            rf_we = 1'b1;
            rf_wd_idx = dec_rd;
            case (dec_wb_sel)
                2'b00: rf_wd_data = alu_result;   // ALU result
                2'b01: rf_wd_data = mem_read_data; // memory data
                2'b10: rf_wd_data = pc_plus_4;    // PC+4 for JAL/JALR
                2'b11: rf_wd_data = dec_imm_u;    // LUI (imm<<12)
                default: rf_wd_data = alu_result;
            endcase
        end
    end

endmodule

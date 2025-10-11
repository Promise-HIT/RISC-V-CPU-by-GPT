// alu_core.v
// Pure combinational ALU core. Inputs:
//  - op1, op2: operands (32-bit)
//  - alu_ctrl: control code coming from alu_control module
// Outputs:
//  - result: 32-bit ALU result
//  - zero: result == 0
//  - slt/sltu: signed/unsigned comparison flags (rs1 < rs2)
`timescale 1ns/1ps
module alu_core (
    input  wire [31:0] op1,
    input  wire [31:0] op2,
    input  wire [3:0]  alu_ctrl,
    output reg  [31:0] result,
    output wire        zero,
    output wire        slt,   // signed less (op1 < op2 signed)
    output wire        sltu   // unsigned less (op1 < op2 unsigned)
);

    // localparam enum must match alu_control encodings
    localparam A_ADD  = 4'd0;
    localparam A_SUB  = 4'd1;
    localparam A_SLL  = 4'd2;
    localparam A_SLT  = 4'd3;
    localparam A_SLTU = 4'd4;
    localparam A_XOR  = 4'd5;
    localparam A_SRL  = 4'd6;
    localparam A_SRA  = 4'd7;
    localparam A_OR   = 4'd8;
    localparam A_AND  = 4'd9;
    localparam A_LUI  = 4'd10;

    // shift amount uses lower 5 bits
    wire [4:0] shamt = op2[4:0];

    // signed interpretations
    wire signed [31:0] sop1 = $signed(op1);
    wire signed [31:0] sop2 = $signed(op2);

    // compute unsigned less and signed less
    assign sltu = (op1 < op2);
    assign slt  = (sop1 < sop2);
    assign zero = (result == 32'b0);

    always @(*) begin
        case (alu_ctrl)
            A_ADD:  result = op1 + op2;
            A_SUB:  result = op1 - op2;
            A_SLL:  result = op1 << shamt;
            A_SLT:  result = (slt) ? 32'd1 : 32'd0;
            A_SLTU: result = (sltu) ? 32'd1 : 32'd0;
            A_XOR:  result = op1 ^ op2;
            A_SRL:  result = op1 >> shamt;
            A_SRA:  result = sop1 >>> shamt;
            A_OR:   result = op1 | op2;
            A_AND:  result = op1 & op2;
            A_LUI:  result = op2; // convention: op2 carries imm<<12 for LUI usage
            default: result = 32'd0;
        endcase
    end

endmodule

// alu_control.v
// Map (alu_op, funct3, funct7) -> alu_ctrl (one-hot like small enum)
`timescale 1ns/1ps
module alu_control (
    input  wire [2:0] alu_op,    // from decoder (category)
    input  wire [2:0] funct3,    // instruction funct3
    input  wire [6:0] funct7,    // instruction funct7 (useful for SUB/SRA detection)
    output reg  [3:0] alu_ctrl   // control code to ALU
);

    // alu_ctrl encoding
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

    always @(*) begin
        // default
        alu_ctrl = A_ADD;

        case (alu_op)
            3'b000: begin
                // ADD category: typically used for loads/stores/addi/auipc
                alu_ctrl = A_ADD;
            end
            3'b001: begin
                // SUB/compare category (branches typically use subtraction or compare)
                alu_ctrl = A_SUB;
            end
            3'b010: begin
                // R-type: use funct3/funct7 to differentiate
                case (funct3)
                    3'b000: alu_ctrl = (funct7[5]) ? A_SUB : A_ADD; // ADD / SUB (funct7[5]==1 => SUB)
                    3'b001: alu_ctrl = A_SLL;
                    3'b010: alu_ctrl = A_SLT;
                    3'b011: alu_ctrl = A_SLTU;
                    3'b100: alu_ctrl = A_XOR;
                    3'b101: alu_ctrl = (funct7[5]) ? A_SRA : A_SRL; // SRL / SRA
                    3'b110: alu_ctrl = A_OR;
                    3'b111: alu_ctrl = A_AND;
                    default: alu_ctrl = A_ADD;
                endcase
            end
            3'b011: begin
                // I-type ALU (addi, xori, ori, andi, slli/srli/srai, slti/sltiu)
                case (funct3)
                    3'b000: alu_ctrl = A_ADD;   // ADDI
                    3'b001: alu_ctrl = A_SLL;   // SLLI (funct7 distinguishes but we can treat as SLL)
                    3'b010: alu_ctrl = A_SLT;   // SLTI
                    3'b011: alu_ctrl = A_SLTU;  // SLTIU
                    3'b100: alu_ctrl = A_XOR;   // XORI
                    3'b101: alu_ctrl = (funct7[5]) ? A_SRA : A_SRL; // SRLI / SRAI (funct7 bit[5] indicates arithmetic)
                    3'b110: alu_ctrl = A_OR;    // ORI
                    3'b111: alu_ctrl = A_AND;   // ANDI
                    default: alu_ctrl = A_ADD;
                endcase
            end
            3'b100: begin
                // LUI category: treat as special ALU op (we will return imm<<12 if used)
                alu_ctrl = A_LUI;
            end
            default: alu_ctrl = A_ADD;
        endcase
    end

endmodule

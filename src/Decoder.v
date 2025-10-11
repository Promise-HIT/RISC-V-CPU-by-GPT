`timescale 1ns/1ps
// decoder.v
// Decoder / ID stage for single-cycle RV32I CPU (improved).
// - Outputs raw field slices, valid flags, and effective register indices (zeroed when invalid).
// - Also outputs immediate (imm) and control signals as before.
//
// Strategy:
//  - compute raw slices (assign) for convenience/debug
//  - in combinational case(opcode) set control signals and set rs1_v/rs2_v/rd_v
//  - compute effective indices: if valid -> raw slice, else -> 5'b0
//
// Note: This is purely combinational logic (no clock inside).
`timescale 1ns/1ps
module decoder (
    input  wire [31:0] inst,

    // raw slices (for debug / optional use)
    output wire [6:0]  opcode,
    output wire [2:0]  funct3,
    output wire [6:0]  funct7,
    output wire [4:0]  raw_rd,
    output wire [4:0]  raw_rs1,
    output wire [4:0]  raw_rs2,

    // effective register indices to use (zeroed if not valid in this format)
    output reg  [4:0]  rd_eff,
    output reg  [4:0]  rs1_eff,
    output reg  [4:0]  rs2_eff,

    // valid flags (indicate whether the raw field should be interpreted as reg index)
    output reg         rd_v,
    output reg         rs1_v,
    output reg         rs2_v,

    // immediate (32-bit, sign-extended / shifted as per format)
    output reg  [31:0] imm,

    // control signals
    output reg         reg_write,
    output reg  [1:0]  wb_sel,      // 00=ALU,01=MEM,10=PC+4,11=LUI/special
    output reg         alu_src,     // 1 -> use imm
    output reg  [2:0]  alu_op,      // category to ALU control
    output reg         mem_read,
    output reg         mem_write,
    output reg  [1:0]  mem_width,   // 00=byte,01=half,10=word
    output reg         mem_signed,
    output reg         branch,
    output reg  [2:0]  branch_type, // pass funct3 for branch unit
    output reg         jump,
    output reg         jalr,
    output reg         lui,
    output reg         auipc,
    output reg         illegal
);

    // --------------------------
    // raw field slicing (always valid as bit positions)
    // --------------------------
    assign opcode = inst[6:0];
    assign raw_rd  = inst[11:7];
    assign funct3  = inst[14:12];
    assign raw_rs1  = inst[19:15];
    assign raw_rs2  = inst[24:20];
    assign funct7  = inst[31:25];

    // --------------------------
    // combinational decode
    // --------------------------
    always @(*) begin
        // default values
        imm         = 32'h00000000;
        reg_write   = 1'b0;
        wb_sel      = 2'b00;
        alu_src     = 1'b0;
        alu_op      = 3'b000;
        mem_read    = 1'b0;
        mem_write   = 1'b0;
        mem_width   = 2'b10;
        mem_signed  = 1'b0;
        branch      = 1'b0;
        branch_type = funct3;
        jump        = 1'b0;
        jalr        = 1'b0;
        lui         = 1'b0;
        auipc       = 1'b0;
        illegal     = 1'b0;

        // by default mark fields invalid (clear valid flags)
        rd_v  = 1'b0;
        rs1_v = 1'b0;
        rs2_v = 1'b0;

        case (opcode)
            // R-type: rd, rs1, rs2 valid
            7'b0110011: begin
                rd_v  = 1'b1;
                rs1_v = 1'b1;
                rs2_v = 1'b1;

                reg_write = 1'b1;
                wb_sel    = 2'b00;
                alu_src   = 1'b0; // rs2
                alu_op    = 3'b010; // R-type
            end

            // I-type arithmetic (addi, xori, ...), also jalr uses I-type imm but is handled separately by opcode
            7'b0010011: begin
                rd_v  = 1'b1;
                rs1_v = 1'b1;
                rs2_v = 1'b0; // rs2 not used

                reg_write = 1'b1;
                wb_sel    = 2'b00;
                alu_src   = 1'b1; // imm
                alu_op    = 3'b011; // I-type ALU
                imm = {{20{inst[31]}}, inst[31:20]};
            end

            // LOAD: rd (write), rs1 used, rs2 invalid
            7'b0000011: begin
                rd_v  = 1'b1;
                rs1_v = 1'b1;
                rs2_v = 1'b0;

                reg_write = 1'b1;
                wb_sel    = 2'b01;
                alu_src   = 1'b1; // address = rs1 + imm
                alu_op    = 3'b000;
                mem_read  = 1'b1;
                imm = {{20{inst[31]}}, inst[31:20]};

                case (funct3)
                    3'b000: begin mem_width = 2'b00; mem_signed = 1'b1; end // LB
                    3'b001: begin mem_width = 2'b01; mem_signed = 1'b1; end // LH
                    3'b010: begin mem_width = 2'b10; mem_signed = 1'b0; end // LW
                    3'b100: begin mem_width = 2'b00; mem_signed = 1'b0; end // LBU
                    3'b101: begin mem_width = 2'b01; mem_signed = 1'b0; end // LHU
                    default: begin mem_width = 2'b10; mem_signed = 1'b0; end
                endcase
            end

            // STORE: rs1, rs2 used, rd invalid
            7'b0100011: begin
                rd_v  = 1'b0;
                rs1_v = 1'b1;
                rs2_v = 1'b1;

                mem_write = 1'b1;
                alu_src   = 1'b1; // address uses imm
                alu_op    = 3'b000;
                imm = {{20{inst[31]}}, inst[31:25], inst[11:7]};

                case (funct3)
                    3'b000: mem_width = 2'b00; // SB
                    3'b001: mem_width = 2'b01; // SH
                    3'b010: mem_width = 2'b10; // SW
                    default: mem_width = 2'b10;
                endcase
            end

            // BRANCH: rs1, rs2 used, rd invalid
            7'b1100011: begin
                rd_v  = 1'b0;
                rs1_v = 1'b1;
                rs2_v = 1'b1;

                branch      = 1'b1;
                branch_type = funct3;
                alu_op      = 3'b001; // compare category
                // B-type imm assembly
                imm = {{19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0};
            end

            // JAL: rd used, rs1/rs2 invalid
            7'b1101111: begin
                rd_v  = 1'b1;
                rs1_v = 1'b0;
                rs2_v = 1'b0;

                reg_write = 1'b1;
                wb_sel    = 2'b10; // pc+4
                jump      = 1'b1;
                imm = {{11{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0};
            end

            // JALR: rd and rs1 used, rs2 invalid
            7'b1100111: begin
                rd_v  = 1'b1;
                rs1_v = 1'b1;
                rs2_v = 1'b0;

                reg_write = 1'b1;
                wb_sel    = 2'b10;
                jalr      = 1'b1;
                imm = {{20{inst[31]}}, inst[31:20]};
            end

            // LUI: rd used; rs1/rs2 invalid
            7'b0110111: begin
                rd_v  = 1'b1;
                rs1_v = 1'b0;
                rs2_v = 1'b0;

                reg_write = 1'b1;
                wb_sel    = 2'b11; // LUI
                lui       = 1'b1;
                imm = {inst[31:12], 12'b0};
                alu_op = 3'b100;
            end

            // AUIPC: rd used, rs1/rs2 invalid (ALU must add pc and imm)
            7'b0010111: begin
                rd_v  = 1'b1;
                rs1_v = 1'b0;
                rs2_v = 1'b0;

                reg_write = 1'b1;
                wb_sel    = 2'b00; // ALU result (pc + imm)
                auipc     = 1'b1;
                alu_src   = 1'b1;
                alu_op    = 3'b000;
                imm = {inst[31:12],12'b0};
            end

            // SYSTEM / CSR - minimal: mark illegal for now
            7'b1110011: begin
                illegal = 1'b1;
            end

            default: begin
                illegal = 1'b1;
            end
        endcase
    end

    // --------------------------
    // effective index outputs (zeroed when invalid)
    // --------------------------
    always @(*) begin
        rd_eff  = rd_v  ? raw_rd  : 5'b0;
        rs1_eff = rs1_v ? raw_rs1 : 5'b0;
        rs2_eff = rs2_v ? raw_rs2 : 5'b0;
    end

endmodule

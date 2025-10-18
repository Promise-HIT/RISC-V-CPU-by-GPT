// cpu_top_single.v  (single-cycle wiring)  -- corrected
`timescale 1ns/1ps
module cpu_top #(
    parameter IMEM_ADDR_WIDTH = 10,
    parameter DMEM_ADDR_WIDTH = 10
) (
    input  wire        clk,
    input  wire        rst_n,
    output wire [31:0] dbg_pc
);

    // IF / PC
    wire [31:0] pc;
    wire [31:0] pc_next;
    wire [31:0] inst;
    wire [31:0] pc_plus_4;

    pc_reg u_pc_reg (
        .clk(clk),
        .rst_n(rst_n),
        .pc_next(pc_next),
        .pc(pc)
    );

    if_stage #(.IMEM_ADDR_WIDTH(IMEM_ADDR_WIDTH)) u_if_stage (
        .pc(pc),
        .inst(inst),
        .pc_plus_4(pc_plus_4)
    );

    assign dbg_pc = pc;

    // ID / Decoder
    wire [6:0]  opcode;
    wire [2:0]  funct3;
    wire [6:0]  funct7;
    wire [4:0]  raw_rd, raw_rs1, raw_rs2;
    wire [4:0]  rd_eff, rs1_eff, rs2_eff;
    wire        rd_v, rs1_v, rs2_v;
    wire [31:0] imm;
    wire        reg_write;
    wire [1:0]  wb_sel;
    wire        alu_src;
    wire [2:0]  alu_op;
    wire        mem_read, mem_write;
    wire [1:0]  mem_width;
    wire        mem_signed;
    wire        branch;
    wire [2:0]  branch_type;
    wire        jump, jalr, lui, auipc;
    wire        illegal;

    decoder u_decoder (
        .inst(inst),
        .opcode(opcode),
        .funct3(funct3),
        .funct7(funct7),
        .raw_rd(raw_rd),
        .raw_rs1(raw_rs1),
        .raw_rs2(raw_rs2),
        .rd_eff(rd_eff),
        .rs1_eff(rs1_eff),
        .rs2_eff(rs2_eff),
        .rd_v(rd_v),
        .rs1_v(rs1_v),
        .rs2_v(rs2_v),
        .imm(imm),
        .reg_write(reg_write),
        .wb_sel(wb_sel),
        .alu_src(alu_src),
        .alu_op(alu_op),
        .mem_read(mem_read),
        .mem_write(mem_write),
        .mem_width(mem_width),
        .mem_signed(mem_signed),
        .branch(branch),
        .branch_type(branch_type),
        .jump(jump),
        .jalr(jalr),
        .lui(lui),
        .auipc(auipc),
        .illegal(illegal)
    );

    // Register file (modified version with write-through)
    wire [31:0] rs1_data, rs2_data;
    wire        rf_we;
    wire [4:0]  rf_wd_idx;
    wire [31:0] rf_wd_data;

    regfile u_regfile (
        .clk(clk),
        .rst_n(rst_n),
        .reg_write(rf_we),
        .rs1_idx(rs1_eff),
        .rs2_idx(rs2_eff),
        .rd_idx(rf_wd_idx),
        .rd_wdata(rf_wd_data),
        .rs1_data(rs1_data),
        .rs2_data(rs2_data)
    );

    // ALU (use rs1_data / rs2_data, AUIPC handled in alu_op1)
    wire [31:0] alu_result;
    wire        zero_flag, slt_flag, sltu_flag;
    wire [31:0] alu_op1 = auipc ? pc : rs1_data;

    alu_top u_alu_top (
        .alu_op(alu_op),
        .funct3(funct3),
        .funct7(funct7),
        .rs1_data(alu_op1),
        .rs2_data(rs2_data),
        .imm(imm),
        .alu_src(alu_src),
        .alu_result(alu_result),
        .zero(zero_flag),
        .slt(slt_flag),
        .sltu(sltu_flag)
    );

    // MEM (merged DMEM + branch unit) -- CORRECTED instantiation
    wire [31:0] mem_read_data;
    wire [31:0] branch_target;
    wire        branch_taken;

    mem_branch_unit #(
        .DMEM_ADDR_WIDTH(DMEM_ADDR_WIDTH)   // correct named parameter override
    ) u_mem_branch (
        // clock / reset
        .clk(clk),
        .rst_n(rst_n),

        // branch inputs
        .pc(pc),
        .imm(imm),
        .branch(branch),
        .branch_type(branch_type),
        .zero(zero_flag),
        .slt(slt_flag),
        .sltu(sltu_flag),

        // mem interface (from EX)
        .addr(alu_result),
        .write_data(rs2_data),
        .mem_read(mem_read),
        .mem_write(mem_write),
        .mem_width(mem_width),
        .mem_signed(mem_signed),

        // outputs
        .branch_target(branch_target),
        .branch_taken(branch_taken),
        .read_data(mem_read_data)
    );

    // JALR target
    wire [31:0] jalr_target = (rs1_data + imm) & 32'hFFFF_FFFE;

    // pc_next: use branch_taken from mem_branch_unit
    assign pc_next = (jump ? (pc + imm) :
                     (jalr ? jalr_target :
                     ((branch && branch_taken) ? branch_target :
                      pc_plus_4)));

    // Writeback: single-cycle combinational controller (directly uses decoder/reg/alu/mem)
    wb_controller_single u_wb_ctrl (
        .dec_reg_write(reg_write),
        .dec_wb_sel(wb_sel),
        .dec_rd(rd_eff),
        .dec_imm_u(imm),          // for LUI: decoder already applied shift in imm
        .alu_result(alu_result),
        .mem_read_data(mem_read_data),
        .pc_plus_4(pc_plus_4),
        .rf_we(rf_we),
        .rf_wd_idx(rf_wd_idx),
        .rf_wd_data(rf_wd_data)
    );

endmodule

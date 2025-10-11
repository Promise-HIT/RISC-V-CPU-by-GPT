// cpu_top.v
// Top-level single-cycle RV32I CPU (uses provided submodules).
`timescale 1ns/1ps
module cpu_top #(
    parameter IMEM_ADDR_WIDTH = 10,
    parameter DMEM_ADDR_WIDTH = 10
) (
    input  wire        clk,
    input  wire        rst_n,

    // (Optional) external hooks for debug / memory init could be added here
    output wire [31:0] dbg_pc      // expose PC for debug
);

    // -------------------------
    // IF / PC
    // -------------------------
    wire [31:0] pc;
    wire [31:0] pc_next;
    wire        pc_src;    // select next PC from branch/jump/jalr
    wire [31:0] inst;
    wire [31:0] pc_plus_4;

    pc_reg u_pc_reg (
        .clk(clk),
        .rst_n(rst_n),
        .pc_src(pc_src),
        .pc_next(pc_next),
        .pc(pc)
    );

    // instruction memory / IF stage (combinational ROM or sync IMEM depending your impl)
    if_stage #(.IMEM_ADDR_WIDTH(IMEM_ADDR_WIDTH)) u_if_stage (
        .pc(pc),
        .inst(inst),
        .pc_plus_4(pc_plus_4)
    );

    assign dbg_pc = pc;

    // -------------------------
    // ID / Decoder
    // -------------------------
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

    // -------------------------
    // Register file (ID)
    // -------------------------
    wire [31:0] rs1_data, rs2_data;

    // Note: regfile read ports are combinational; write port will be driven by wb_controller outputs
    // We'll connect regfile write inputs to rf_we/rf_wd_idx/rf_wd_data coming from wb_controller.
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

    // -------------------------
    // ALU stage (EX)
    // - op1: normally rs1_data, but for AUIPC op1 should be PC
    // - op2: either imm (alu_src=1) or rs2_data
    // -------------------------
    wire [31:0] alu_result;
    wire        zero_flag, slt_flag, sltu_flag;

    // ALU op1 selection: use PC for AUIPC, else rs1_data
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

    // -------------------------
    // MEM + Branch unit
    // We use mem_branch_unit (which implements DMEM + branch logic from earlier)
    // Inputs:
    // - pc, imm, branch, branch_type, zero/slt/sltu
    // - addr (alu_result), write_data (rs2_data), mem_read, mem_write, mem_width, mem_signed
    // Outputs:
    // - branch_target, branch_taken, read_data (synchronous)
    // -------------------------
    wire [31:0] branch_target;
    wire        branch_taken;
    wire [31:0] mem_read_data; // registered read data (valid next cycle after mem_read)

    mem_branch_unit #(.IMEM_ADDR_WIDTH(DMEM_ADDR_WIDTH)) u_mem_branch (
        .clk(clk),
        .rst_n(rst_n),
        // Branch inputs
        .pc(pc),
        .imm(imm),
        .branch(branch),
        .branch_type(branch_type),
        .zero(zero_flag),
        .slt(slt_flag),
        .sltu(sltu_flag),
        // Memory interface
        .addr(alu_result),
        .write_data(rs2_data),
        .mem_read(mem_read),
        .mem_write(mem_write),
        .mem_width(mem_width),
        .mem_signed(mem_signed),
        // Outputs
        .branch_target(branch_target),
        .branch_taken(branch_taken),
        .read_data(mem_read_data)
    );

    // -------------------------
    // JALR target computation (special: (rs1 + imm) & ~1)
    // - compute combinationally using rs1_data + imm
    // -------------------------
    wire [31:0] jalr_target = (rs1_data + imm) & 32'hFFFF_FFFE;

    // -------------------------
    // PC update logic (priority)
    // priority: jump (JAL) > jalr > branch (branch_taken)
    // - For JAL: pc_next = pc + imm (decoder.imm is J-type imm)
    // - For jalr: pc_next = (rs1 + imm) & ~1
    // - Else if branch & branch_taken: branch_target (pc + imm)
    // -------------------------
    assign pc_src = jump | jalr | (branch & branch_taken);

    assign pc_next = jump ? (pc + imm) :
                     jalr ? jalr_target :
                     branch & branch_taken ? branch_target :
                     32'b0; // value ignored when pc_src==0 (pc will increment internally in pc_reg)

    // -------------------------
    // Writeback controller
    // - Handles sync DMEM read delay: loads are staged and written back next cycle
    // -------------------------
    wb_controller u_wb_ctrl (
        .clk(clk),
        .rst_n(rst_n),
        // control from decoder (per-instruction)
        .dec_reg_write(reg_write),
        .dec_wb_sel(wb_sel),
        .dec_rd(rd_eff),
        .dec_imm_u(imm), // decoder already provides imm<<12 for LUI when appropriate

        // data sources
        .alu_result(alu_result),
        .mem_read_data(mem_read_data),
        .pc_plus_4(pc_plus_4),

        // outputs to regfile
        .rf_we(rf_we),
        .rf_wd_idx(rf_wd_idx),
        .rf_wd_data(rf_wd_data)
    );

    // -------------------------
    // (Optional) tie-offs or debug outputs could be placed here
    // -------------------------

endmodule

// mem_branch_unit.v  -- merged: branch logic + DMEM (sync write, combinational read)
// - synchronous writes on posedge clk (blocking assignment to help simulation write-through)
// - combinational read (read_data computed from mem[word_index])
// - branch_target and branch_taken remain combinational (as original)
// Note: Parameter name kept as IMEM_ADDR_WIDTH for compatibility with your cpu_top instantiation.
`timescale 1ns/1ps
module mem_branch_unit #(
    parameter DMEM_ADDR_WIDTH = 10  // number of word-address bits -> DEPTH = 2^ADDR_WIDTH words
) (
    input  wire        clk,
    input  wire        rst_n,

    // Branch inputs
    input  wire [31:0] pc,
    input  wire [31:0] imm,
    input  wire        branch,
    input  wire [2:0]  branch_type,
    input  wire        zero,
    input  wire        slt,
    input  wire        sltu,

    // Memory interface (from EX)
    input  wire [31:0] addr,        // byte address
    input  wire [31:0] write_data,  // rs2
    input  wire        mem_read,    // load enable
    input  wire        mem_write,   // store enable
    input  wire [1:0]  mem_width,   // 00=byte,01=half,10=word
    input  wire        mem_signed,  // load sign extend

    // Outputs
    output wire [31:0] branch_target,
    output wire        branch_taken, // combinational
    output reg  [31:0] read_data     // combinational read_data (computed in always @(*))
);

    localparam DEPTH = (1 << DMEM_ADDR_WIDTH);

    // word-addressable memory
    reg [31:0] mem [0:DEPTH-1];
    integer i;

    // index and offsets
    wire [DMEM_ADDR_WIDTH-1:0] word_index = addr[DMEM_ADDR_WIDTH+1:2];
    wire [1:0] byte_offset = addr[1:0];

    // branch target (simple PC + imm)
    assign branch_target = pc + imm;

    // branch condition decoding (same as your original)
    wire cond_beq  = zero;
    wire cond_bne  = ~zero;
    wire cond_blt  = slt;
    wire cond_bge  = ~slt;
    wire cond_bltu = sltu;
    wire cond_bgeu = ~sltu;

    wire branch_condition = (branch) ? (
        (branch_type == 3'b000) ? cond_beq  :
        (branch_type == 3'b001) ? cond_bne  :
        (branch_type == 3'b100) ? cond_blt  :
        (branch_type == 3'b101) ? cond_bge  :
        (branch_type == 3'b110) ? cond_bltu :
        (branch_type == 3'b111) ? cond_bgeu :
        1'b0
    ) : 1'b0;

    assign branch_taken = branch_condition;

    // initialize memory (optional $readmemh)
    initial begin
        for (i = 0; i < DEPTH; i = i + 1) mem[i] = 32'h0000_0000;
        // try to load dmem.hex if present
        $readmemh("dmem.hex", mem);
    end

    // Temporary word for combinational extraction
    reg [31:0] word_r;

    // Synchronous WRITE (posedge). Using blocking assignment here to make the update
    // immediately visible inside the same simulation time-step for combinational read.
    // This is simulation-friendly; for synthesis target you may prefer non-blocking
    // and a memory primitive with appropriate read/write semantics.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // reset memory to zero on reset (optional, but matches original behavior)
            for (i = 0; i < DEPTH; i = i + 1) begin
                mem[i] = 32'h00000000;
            end
        end else begin
            if (mem_write) begin
                case (mem_width)
                    2'b10: begin
                        // SW (word)
                        mem[word_index] = write_data;
                    end
                    2'b01: begin
                        // SH (halfword)
                        // merge depending on byte_offset (only offsets 0 or 2 allowed for aligned halfwords)
                        case (byte_offset)
                            2'b00: mem[word_index] = {mem[word_index][31:16], write_data[15:0]};
                            2'b10: mem[word_index] = {write_data[15:0], mem[word_index][15:0]};
                            default: mem[word_index] = mem[word_index];
                        endcase
                    end
                    2'b00: begin
                        // SB (byte)
                        case (byte_offset)
                            2'b00: mem[word_index] = {mem[word_index][31:8],  write_data[7:0]};
                            2'b01: mem[word_index] = {mem[word_index][31:16], write_data[7:0], mem[word_index][7:0]};
                            2'b10: mem[word_index] = {mem[word_index][31:24], write_data[7:0], mem[word_index][15:0]};
                            2'b11: mem[word_index] = {write_data[7:0],  mem[word_index][23:0]};
                            default: mem[word_index] = mem[word_index];
                        endcase
                    end
                    default: mem[word_index] = mem[word_index];
                endcase
            end
        end
    end

    // Combinational read_data extraction (immediate combinational output)
    always @(*) begin
        // default
        read_data = 32'b0;
        word_r = mem[word_index];

        if (mem_read) begin
            case (mem_width)
                2'b10: begin
                    // LW
                    read_data = word_r;
                end
                2'b01: begin
                    // LH / LHU (halfword) - handle offsets 0 or 2 (but generalize)
                    case (byte_offset)
                        2'b00: read_data = mem_signed ? {{16{word_r[15]}}, word_r[15:0]} : {{16{1'b0}}, word_r[15:0]};
                        2'b10: read_data = mem_signed ? {{16{word_r[31]}}, word_r[31:16]}: {{16{1'b0}}, word_r[31:16]};
                        default: read_data = mem_signed ? {{16{word_r[15]}}, word_r[15:0]} : {{16{1'b0}}, word_r[15:0]};
                    endcase
                end
                2'b00: begin
                    // LB / LBU (byte)
                    case (byte_offset)
                        2'b00: read_data = mem_signed ? {{24{word_r[7]}},  word_r[7:0]}  : {{24{1'b0}}, word_r[7:0]};
                        2'b01: read_data = mem_signed ? {{24{word_r[15]}}, word_r[15:8]} : {{24{1'b0}}, word_r[15:8]};
                        2'b10: read_data = mem_signed ? {{24{word_r[23]}}, word_r[23:16]}: {{24{1'b0}}, word_r[23:16]};
                        2'b11: read_data = mem_signed ? {{24{word_r[31]}}, word_r[31:24]}: {{24{1'b0}}, word_r[31:24]};
                        default: read_data = 32'b0;
                    endcase
                end
                default: read_data = word_r;
            endcase
        end else begin
            // if no read, read_data may be left as zero or reflect memory content;
            // we keep it zero to avoid unintended writeback when mem_read==0
            read_data = 32'b0;
        end
    end

endmodule

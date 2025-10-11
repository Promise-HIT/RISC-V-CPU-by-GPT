// mem_branch_unit.v
// Combined Branch Unit + Data Memory for RV32I single-cycle datapath (synchronous DMEM).
// - Branch: combinational branch_taken and branch_target = pc + imm
// - Data Memory: synchronous read/write on posedge clk, read_data is registered
// - Supports byte/half/word accesses and sign/zero extension for loads
// - Parameterizable depth by word-address bits (ADDR_WIDTH)
//
// Notes:
//  - addr is a byte address; internal memory is word-addressed (word = 32-bit).
//  - read_data is valid in the clock cycle AFTER mem_read is asserted (synchronous read).
//  - For stores, partial writes (byte/half) are supported via read-modify-write.
//
// Author: ChatGPT (based on user's datapath design)
`timescale 1ns/1ps
module mem_branch_unit #(
    parameter IMEM_ADDR_WIDTH = 10  // number of word-address bits -> DEPTH = 2^ADDR_WIDTH words
) (
    input  wire        clk,
    input  wire        rst_n,

    // --- Branch inputs
    input  wire [31:0] pc,          // current pc (for branch target calculation)
    input  wire [31:0] imm,         // B-type immediate (already assembled in ID)
    input  wire        branch,      // branch instruction indicator (from decoder)
    input  wire [2:0]  branch_type, // funct3 for branch type (BEQ/BNE/BLT/...)
    input  wire        zero,        // ALU zero flag (op1 - op2 == 0)
    input  wire        slt,         // ALU signed less (op1 < op2 signed)
    input  wire        sltu,        // ALU unsigned less (op1 < op2 unsigned)

    // --- Memory interface (from EX stage / datapath)
    input  wire [31:0] addr,        // byte address (usually ALU result)
    input  wire [31:0] write_data,  // data to write (from rs2)
    input  wire        mem_read,    // load enable
    input  wire        mem_write,   // store enable
    input  wire [1:0]  mem_width,   // 00=byte,01=half,10=word
    input  wire        mem_signed,  // for loads: 1 => sign-extend, 0 => zero-extend

    // --- Outputs
    output wire [31:0] branch_target, // pc + imm (combinational)
    output reg         branch_taken,  // combinational result (registered for stable view if desired)
    output reg  [31:0] read_data      // synchronous read data (valid next cycle after mem_read)
);

    // Memory depth and index calculation:
    localparam DEPTH = (1 << IMEM_ADDR_WIDTH);

    // storage: word-addressable memory
    reg [31:0] mem [0:DEPTH-1];
    integer i;

    // convert byte address to word index (use ADDR_WIDTH parameter)
    wire [IMEM_ADDR_WIDTH-1:0] word_index;
    assign word_index = addr[IMEM_ADDR_WIDTH+1:2];

    // byte offset inside the word
    wire [1:0] byte_offset = addr[1:0];

    // combinational branch target
    assign branch_target = pc + imm;

    // combinational branch_taken logic (based on branch_type & ALU flags)
    // BEQ  funct3 = 3'b000
    // BNE         = 3'b001
    // BLT         = 3'b100
    // BGE         = 3'b101
    // BLTU        = 3'b110
    // BGEU        = 3'b111
    wire cond_beq  = zero;
    wire cond_bne  = ~zero;
    wire cond_blt  = slt;
    wire cond_bge  = ~slt;
    wire cond_bltu = sltu;
    wire cond_bgeu = ~sltu;

    wire branch_condition;
    assign branch_condition = (branch) ? (
        (branch_type == 3'b000) ? cond_beq  :
        (branch_type == 3'b001) ? cond_bne  :
        (branch_type == 3'b100) ? cond_blt  :
        (branch_type == 3'b101) ? cond_bge  :
        (branch_type == 3'b110) ? cond_bltu :
        (branch_type == 3'b111) ? cond_bgeu :
        1'b0
    ) : 1'b0;

    // update branch_taken as combinational->registered (gives stable view at posedge)
    always @(*) begin
        branch_taken = branch_condition;
    end

    // ---------- Memory initialization ----------
    initial begin
        for (i = 0; i < DEPTH; i = i + 1) begin
            mem[i] = 32'h0000_0000;
        end
        // optional: try to preload with file "dmem.hex" (one 32-bit word per line)
        // $readmemh("dmem.hex", mem);
    end

    // helper signals for read/write operations
    reg [31:0] word_r;          // read raw 32-bit word from mem
    reg [31:0] word_new;        // new word for write (after merging bytes)

    // synchronous memory read/write (posedge clk or async reset)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // reset read_data to zero on async reset
            read_data <= 32'b0;
        end else begin
            // WRITE: perform store if enabled (write happens first in this cycle)
            if (mem_write) begin
                // read current word to merge partial writes
                word_r = mem[word_index];
                case (mem_width)
                    2'b10: begin
                        // word write (aligned or not) - write full 32-bit
                        mem[word_index] <= write_data;
                    end
                    2'b01: begin
                        // half-word write (16-bit) - place at offset 0 or 2
                        case (byte_offset)
                            2'b00: word_new = {word_r[31:16], write_data[15:0]};
                            2'b10: word_new = {write_data[15:0], word_r[15:0]};
                            default: word_new = word_r; // unaligned half - ignore or handle
                        endcase
                        mem[word_index] <= word_new;
                    end
                    2'b00: begin
                        // byte write - place in appropriate byte lane
                        case (byte_offset)
                            2'b00: word_new = {word_r[31:8], write_data[7:0]};
                            2'b01: word_new = {word_r[31:16], write_data[7:0], word_r[7:0]};
                            2'b10: word_new = {word_r[31:24], write_data[7:0], word_r[15:0]};
                            2'b11: word_new = {write_data[7:0], word_r[23:0]};
                            default: word_new = word_r;
                        endcase
                        mem[word_index] <= word_new;
                    end
                    default: mem[word_index] <= mem[word_index];
                endcase
            end

            // READ: synchronous read -- data becomes available in read_data next cycle
            if (mem_read) begin
                word_r = mem[word_index];
                // extract according to width and sign flag
                case (mem_width)
                    2'b10: begin
                        // word
                        read_data <= word_r;
                    end
                    2'b01: begin
                        // half-word
                        case (byte_offset)
                            2'b00: begin
                                if (mem_signed)
                                    read_data <= {{16{word_r[15]}}, word_r[15:0]}; // sign-extend
                                else
                                    read_data <= {{16{1'b0}}, word_r[15:0]};        // zero-extend
                            end
                            2'b10: begin
                                if (mem_signed)
                                    read_data <= {{16{word_r[31]}}, word_r[31:16]};
                                else
                                    read_data <= {{16{1'b0}}, word_r[31:16]};
                            end
                            default: begin
                                // unaligned half-word - choose lower half by default
                                if (mem_signed)
                                    read_data <= {{16{word_r[15]}}, word_r[15:0]};
                                else
                                    read_data <= {{16{1'b0}}, word_r[15:0]};
                            end
                        endcase
                    end
                    2'b00: begin
                        // byte
                        case (byte_offset)
                            2'b00: begin
                                if (mem_signed)
                                    read_data <= {{24{word_r[7]}},  word_r[7:0]};
                                else
                                    read_data <= {{24{1'b0}},       word_r[7:0]};
                            end
                            2'b01: begin
                                if (mem_signed)
                                    read_data <= {{24{word_r[15]}}, word_r[15:8]};
                                else
                                    read_data <= {{24{1'b0}},       word_r[15:8]};
                            end
                            2'b10: begin
                                if (mem_signed)
                                    read_data <= {{24{word_r[23]}}, word_r[23:16]};
                                else
                                    read_data <= {{24{1'b0}},       word_r[23:16]};
                            end
                            2'b11: begin
                                if (mem_signed)
                                    read_data <= {{24{word_r[31]}}, word_r[31:24]};
                                else
                                    read_data <= {{24{1'b0}},       word_r[31:24]};
                            end
                            default: begin
                                read_data <= 32'b0;
                            end
                        endcase
                    end
                    default: read_data <= word_r;
                endcase
            end else begin
                // if not reading, keep previous read_data (or optionally zero)
                read_data <= read_data;
            end
        end
    end

endmodule

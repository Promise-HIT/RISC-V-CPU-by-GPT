// imem_if.v
// Simple combinational instruction memory (ROM) + IF stage for a single-cycle RV32I CPU.
// - imem: combinational read ROM (word-addressed). Initialized by imem.hex if present.
// - if_stage: instantiates imem and computes pc+4. Designed to be connected to your pc_reg.

`timescale 1ns/1ps

// ---------------------------
// imem: simple instruction ROM
// ---------------------------
module imem #(
    parameter ADDR_WIDTH = 10  // number of word-address bits -> DEPTH = 2^ADDR_WIDTH words
) (
    input  wire [31:0] addr,   // byte address; only word-aligned addresses used
    output wire [31:0] inst
);

    localparam DEPTH = (1 << ADDR_WIDTH);

    // memory array, word-addressable
    reg [31:0] mem [0:DEPTH-1];

    // convert byte address to word index; use low bits [1:0] as byte offset (ignored)
    wire [ADDR_WIDTH-1:0] word_index;
    assign word_index = addr[ADDR_WIDTH+1:2];

    // combinational read (suitable for simple simulation / educational single-cycle CPU)
    assign inst = mem[word_index];

    // initialize memory: default to addi x0,x0,0 (NOP) and then optionally override with imem.hex
    integer i;
    initial begin

        for (i = 0; i < DEPTH; i = i + 1) begin
            mem[i] = 32'h00000013; // addi x0, x0, 0 -> effectively NOP
        end

        // try to read initialization file if available (hex, one 32-bit word per line, lowest address first)
        // Example imem.hex line: 00000513
        // If no file present, memory stays filled with NOPs.
        $readmemh("imem.hex", mem);
    end

endmodule


// ---------------------------
// if_stage: instruction fetch stage
// ---------------------------
module if_stage #(
    parameter IMEM_ADDR_WIDTH = 10
) (
    input  wire [31:0] pc,           // comes from your pc_reg.pc
    output wire [31:0] inst,         // instruction read from IMEM
    output wire [31:0] pc_plus_4     // computed pc + 4 for use in later stages (e.g. jal writeback)
);

    // instantiate imem
    imem #(.ADDR_WIDTH(IMEM_ADDR_WIDTH)) imem0 (
        .addr(pc),
        .inst(inst)
    );

    // simple PC+4 adder (combinational)
    assign pc_plus_4 = pc + 32'd4;

endmodule

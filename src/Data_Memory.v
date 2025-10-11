// dmem.v
// Synchronous Data Memory for RV32I (word-addressable internal storage).
// - Synchronous write/read on posedge clk
// - read_data is registered and becomes valid one cycle after mem_read asserted
// - Supports byte/half/word accesses and sign/extend for loads
// - write performs read-modify-write for partial writes (byte/half)
// - Parameterizable depth via ADDR_WIDTH
`timescale 1ns/1ps
module dmem #(
    parameter ADDR_WIDTH = 10  // number of word-address bits -> DEPTH = 2^ADDR_WIDTH words
) (
    input  wire        clk,
    input  wire        rst_n,        // active-low async reset
    input  wire [31:0] addr,         // byte address
    input  wire [31:0] write_data,   // data to write (from rs2)
    input  wire        mem_read_en,  // load enable
    input  wire        mem_write_en, // store enable
    input  wire [1:0]  mem_size,     // 00=byte,01=half,10=word
    input  wire        mem_signed,   // for loads: 1 => sign-extend, 0 => zero-extend
    output reg  [31:0] read_data     // registered read data (valid next cycle)
);

    localparam DEPTH = (1 << ADDR_WIDTH);

    // internal memory array (word-addressable)
    reg [31:0] mem [0:DEPTH-1];
    integer i;

    // compute word index and byte offset within the word
    wire [ADDR_WIDTH-1:0] word_index;
    wire [1:0] byte_offset;
    assign word_index  = addr[ADDR_WIDTH+1:2]; // use bits [ADDR_WIDTH+1:2]
    assign byte_offset = addr[1:0];

    // temporary holders
    reg [31:0] word_r;
    reg [31:0] word_new;

    // initialize memory (optional file)
    initial begin
        for (i = 0; i < DEPTH; i = i + 1) begin
            mem[i] = 32'h00000000;
        end
        // optional init file (one 32-bit hex word per line)
        // $readmemh("dmem.hex", mem);
    end

    // Synchronous read/write behavior:
    // - On posedge clk:
    //     * if mem_write_en: perform write (partial supported via merge)
    //     * if mem_read_en: read mem[word_index] and produce read_data after extraction/extend
    // - Reset clears read_data (but memory content preserved or cleared depending on init)
    //
    // Note: If both mem_write_en and mem_read_en are asserted for same addr in same cycle,
    //       this implementation performs the write first then the read (so read_data sees new value).
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_data <= 32'b0;
        end else begin
            // default: read_data holds previous value (will be overwritten if mem_read_en)
            // Write first (so a simultaneous read will see updated data)
            if (mem_write_en) begin
                // read current word to merge partial writes
                word_r = mem[word_index];
                case (mem_size)
                    2'b10: begin
                        // word write
                        mem[word_index] <= write_data;
                    end
                    2'b01: begin
                        // half-word write: place 16-bit at offset 0 or 2
                        case (byte_offset)
                            2'b00: word_new = {word_r[31:16], write_data[15:0]}; // low half
                            2'b10: word_new = {write_data[15:0], word_r[15:0]};  // high half
                            default: word_new = word_r; // unaligned half - keep old
                        endcase
                        mem[word_index] <= word_new;
                    end
                    2'b00: begin
                        // byte write
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

            // Read (synchronous): data becomes available next cycle in read_data
            if (mem_read_en) begin
                word_r = mem[word_index];
                case (mem_size)
                    2'b10: begin
                        // word
                        read_data <= word_r;
                    end
                    2'b01: begin
                        // half-word
                        case (byte_offset)
                            2'b00: begin
                                if (mem_signed)
                                    read_data <= {{16{word_r[15]}}, word_r[15:0]}; // sign-extend low half
                                else
                                    read_data <= {{16{1'b0}}, word_r[15:0]};        // zero-extend
                            end
                            2'b10: begin
                                if (mem_signed)
                                    read_data <= {{16{word_r[31]}}, word_r[31:16]}; // sign-extend high half
                                else
                                    read_data <= {{16{1'b0}}, word_r[31:16]};
                            end
                            default: begin
                                // unaligned half: choose low half by default
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
                            default: read_data <= 32'b0;
                        endcase
                    end
                    default: read_data <= word_r;
                endcase
            end else begin
                // if not reading, keep previous read_data
                read_data <= read_data;
            end
        end
    end

endmodule

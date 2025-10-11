// wb_controller.v -- handles writeback including synchronous DMEM delay
module wb_controller (
    input  wire        clk,
    input  wire        rst_n,

    // control from decoder (combinational, per-instruction)
    input  wire        dec_reg_write,  // reg_write from decoder (intention)
    input  wire [1:0]  dec_wb_sel,     // decoder wb_sel
    input  wire [4:0]  dec_rd,         // rd_eff
    input  wire [31:0] dec_imm_u,      // imm<<12 for LUI (if needed)

    // data sources
    input  wire [31:0] alu_result,
    input  wire [31:0] mem_read_data,  // synchronous DMEM read_data (valid next cycle after mem_read)
    input  wire [31:0] pc_plus_4,

    // output to regfile (write port)
    output reg         rf_we,          // write enable to regfile
    output reg  [4:0]  rf_wd_idx,      // rd index to write to
    output reg  [31:0] rf_wd_data      // data to write to regfile
);

    // states: we only need one cycle of staging for loads
    reg        pending_load;   // indicates we are waiting to write back mem_read_data
    reg [4:0]  pending_rd;
    reg [1:0]  pending_wb_sel; // should be MEM == 01
    reg        pending_regwrite;
    reg [31:0] pending_imm_u;

    // default outputs
    always @(*) begin
        rf_we     = 1'b0;
        rf_wd_idx = 5'b0;
        rf_wd_data= 32'b0;
    end

    // Combinational decision for non-load writes: write immediately (this writes on next posedge)
    // BUT as regfile write is synchronous at posedge, we must assert rf_we and rf_wd_* in time for posedge.
    // We'll use sequential logic below to register write strobes.
    // For clarity, we will drive immediate writes in sequential block.

    // Sequential: manage pending load and perform writes on clock edges
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending_load <= 1'b0;
            pending_rd   <= 5'b0;
            pending_wb_sel <= 2'b00;
            pending_regwrite <= 1'b0;
            pending_imm_u <= 32'b0;
            // outputs default (combinational block above sets them)
            rf_we <= 1'b0;
            rf_wd_idx <= 5'b0;
            rf_wd_data <= 32'b0;
        end else begin
            // Clear write by default; we'll set if needed
            rf_we <= 1'b0;
            rf_wd_idx <= 5'b0;
            rf_wd_data <= 32'b0;

            // If there is a pending load (from previous cycle) — write mem_read_data into pending_rd
            if (pending_load) begin
                rf_we <= pending_regwrite;        // should be 1 for loads that write rd
                rf_wd_idx <= pending_rd;
                rf_wd_data <= mem_read_data;      // now mem_read_data is valid (sync DMEM)
                pending_load <= 1'b0;             // clear pending
            end else begin
                // No pending load waiting — handle current decoder outputs:
                if (dec_reg_write) begin
                    if (dec_wb_sel == 2'b01) begin
                        // This is a LOAD: cannot write this cycle because mem_read_data isn't ready yet
                        // Stage the rd index for next cycle write
                        pending_load <= 1'b1;
                        pending_rd   <= dec_rd;
                        pending_wb_sel <= dec_wb_sel;
                        pending_regwrite <= 1'b1;
                        pending_imm_u <= dec_imm_u;
                        // Do not assert rf_we this cycle
                    end else begin
                        // Non-load instruction: choose ALU/PC/LUI and write immediately
                        rf_we <= 1'b1;
                        rf_wd_idx <= dec_rd;
                        // select data (ALU/PC/LUI) - mem_read_data not used here
                        case (dec_wb_sel)
                            2'b00: rf_wd_data <= alu_result;     // ALU
                            2'b10: rf_wd_data <= pc_plus_4;     // PC+4 (JAL/JALR)
                            2'b11: rf_wd_data <= dec_imm_u;     // LUI (imm<<12)
                            default: rf_wd_data <= alu_result;
                        endcase
                    end
                end
            end
        end
    end

endmodule

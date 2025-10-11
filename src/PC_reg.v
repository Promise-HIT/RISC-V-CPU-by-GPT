module pc_reg (
    input  clk,
    input  rst_n,
    input  pc_src,
    input [31:0] pc_next,
    output reg [31:0] pc
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc <= 32'b0;
        end 
        else if (pc_src) begin
            pc <= pc_next;
        end 
        else begin
            pc <= pc + 32'd4;
        end
    end
endmodule
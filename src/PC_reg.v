module pc_reg (
    input  clk,
    input  rst_n,
    input [31:0] pc_next,    // 外部计算好的下一个PC值
    output reg [31:0] pc
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc <= 32'b0;      // 复位时从0地址开始
        end else begin
            pc <= pc_next;    // 直接使用外部计算的下一个PC值
        end
    end
endmodule
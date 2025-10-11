`timescale 1ns/1ps
module tb_cpu_top;

    // parameters must match cpu_top instantiation in your project
    parameter IMEM_ADDR_WIDTH = 6;
    parameter DMEM_ADDR_WIDTH = 6;

    // clock & reset
    reg clk;
    reg rst_n;

    // instantiate your top cpu (must match module name and params)
    cpu_top #(
        .IMEM_ADDR_WIDTH(IMEM_ADDR_WIDTH),
        .DMEM_ADDR_WIDTH(DMEM_ADDR_WIDTH)
    ) u_cpu (
        .clk(clk),
        .rst_n(rst_n),
        .dbg_pc() // optional debug port
    );

    // simple clock
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100 MHz-ish, period 10 time units
    end

    // reset pulse
    initial begin
        rst_n = 1'b0;
        #20;
        rst_n = 1'b1;
    end

    // initialize IMEM directly via hierarchical path
    // NOTE: adjust the hierarchical path if your if_stage/imem naming differs.
    integer i;
    initial begin
        // zero IMEM first

        for (i = 0; i < (1<<IMEM_ADDR_WIDTH); i = i + 1) begin
            u_cpu.u_if_stage.imem0.mem[i] = 32'h00000013; // NOP (addi x0,x0,0) as default
        end

        // Program (6 instructions)
        u_cpu.u_if_stage.imem0.mem[0] = 32'h00400093; // addi x1, x0, 4
        u_cpu.u_if_stage.imem0.mem[1] = 32'h00a00113; // addi x2, x0, 10
        u_cpu.u_if_stage.imem0.mem[2] = 32'h0020a023; // sw x2, 0(x1)
        u_cpu.u_if_stage.imem0.mem[3] = 32'h00000193; // addi x3, x0, 0
        u_cpu.u_if_stage.imem0.mem[4] = 32'h0000a183; // lw x3, 0(x1)
        u_cpu.u_if_stage.imem0.mem[5] = 32'h00118213; // addi x4, x3, 1

        // optional: you can pre-load data memory as well
        for (i = 0; i < (1<<DMEM_ADDR_WIDTH); i = i + 1) begin
            u_cpu.u_mem_branch.mem[i] = 32'h00000000;
        end

        // run for a while and then finish
        #1000;
        $display("Simulation finished.");
        $finish;
    end

    // monitor / print register & memory state every cycle (after posedge)
    always @(posedge clk) begin
        // print PC and a few registers for observation
        $display("Time=%0t PC=0x%08h", $time, u_cpu.u_pc_reg.pc);

        // print registers x1..x4 by accessing regfile internal array (names must match)
        $display(" x1=%0d x2=%0d x3=%0d x4=%0d",
            u_cpu.u_regfile.regs[1],
            u_cpu.u_regfile.regs[2],
            u_cpu.u_regfile.regs[3],
            u_cpu.u_regfile.regs[4]
        );

        // print memory word at index 1 (this corresponds to byte address 4)
        $display(" MEM[1]=0x%08h", u_cpu.u_mem_branch.mem[1]);
        $display("-------------------------------");
    end

endmodule

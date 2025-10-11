
# 🚀 RISC-V 单周期 CPU 设计 (RV32I)

本项目实现了一个 **可综合的单周期 RISC-V CPU（RV32I 子集）**，采用模块化结构，包含取指、译码、执行、访存、写回五个主要阶段。

---

## 📘 主要特性

- **支持指令集**：RV32I 基础整数指令（R / I / S / B / U / J 型）  
- **单周期执行**：每条指令在一个时钟周期内完成  
- **模块化设计**：各功能单元独立，便于仿真和扩展  
- **同步数据存储器** (`dmem`)，组合指令存储器 (`imem`)  
- **可仿真、可综合**，支持 `$readmemh("imem.hex")` 加载程序

---

## 🧩 模块概览

| 模块名 | 功能说明 |
|--------|-----------|
| `pc_reg` | 程序计数器寄存器 |
| `if_stage` + `imem` | 取指阶段，读取指令并输出 `pc+4` |
| `decoder` | 指令译码，生成控制信号与立即数 |
| `regfile` | 通用寄存器堆，支持双端口读写 |
| `alu_top` | 算术逻辑单元，支持比较、加减、逻辑、移位 |
| `mem_branch_unit` + `dmem` | 访存与分支判定模块 |
| `wb_controller` | 写回控制，决定寄存器写回数据来源 |

---

## ⚙️ 顶层接口示例

```verilog
module cpu_top (
    input  wire clk,
    input  wire rst_n,
    output wire [31:0] dbg_pc   // 调试输出当前 PC
);
````

---

## 🧪 仿真方式

1. 在 `tb_cpu_top.v` 中定义简单的测试程序：

   ```verilog
   u_cpu.u_if_stage.imem0.mem[0] = 32'h00400093; // addi x1,x0,4
   u_cpu.u_if_stage.imem0.mem[1] = 32'h00a00113; // addi x2,x0,10
   u_cpu.u_if_stage.imem0.mem[2] = 32'h0020a023; // sw x2,0(x1)
   ```
2. 运行仿真：

   ```bash
   vsim work.tb_cpu_top
   run 1000ns
   ```

3. 观察输出：

   ```
   PC=0x00000000 x1=4 x2=10 x3=0 ...
   ```

---

## 🧠 扩展方向

* 支持流水线结构（5 阶段）
* 增加转发（forwarding）与冒险检测（hazard detection）
* 引入 CSR、异常中断、缓存机制等

---

## 📁 项目结构

```
.
├── src/
│   ├── cpu_top.v
│   ├── pc_reg.v
│   ├── if_stage.v
│   ├── decoder.v
│   ├── alu_top.v
│   ├── mem_branch_unit.v
│   └── wb_controller.v
├── tb/
│   └── tb_cpu_top.v
└── imem.hex

```

-------

## 📝 作者说明

该项目由作者借助ChatGPT(GPT-5)设计需求完整撰写与模块化实现。




# Single-cycle RV32I CPU (module guide, dataflow, timing, optimizations)


# 目录

* 概览（设计目标与整体架构）
* 模块说明（按文件/模块逐一简述）

  * `imem`
  * `if_stage`
  * `decoder`
  * `alu_control`
  * `alu_core`
  * `alu_top`
  * `pc_reg`
  * `regfile`
  * `mem_branch_unit`
  * `wb_controller_single`
  * `cpu_top`（顶层集成）
* 数据流 & 单周期时序（逐周期/组合信号分解）
* 关键实现细节与易错点（检查清单）
* 验证 / 调试 / 仿真建议
* 优化与扩展策略（短期 / 中期 / 长期优先级）
* 快速术语表与信号说明

---

# 概览（设计目标与整体架构）

这是一个单周期（single-cycle）的 RV32I 实现：每条指令在一个时钟周期内完成（Fetch → Decode → Execute → Mem → Writeback）。关键特性包括：

* 指令ROM (`imem`) 组合读取；
* 单周期寄存器堆（写通 write-through，组合读）；
* 合并的 data-memory + branch unit（`mem_branch_unit`），同步写、组合读；
* 简单的 ALU 分层（控制生成 `alu_control` + 算术单元 `alu_core`）；
* 单一写回控制器 `wb_controller_single`；
* 顶层 `cpu_top` 将模块连接，计算 `pc_next`；

注意：单周期实现简单易理解，但时钟周期需足够长以包容整条指令的最长延迟（critical path）。

---

# 模块说明

## `imem`

* **功能**：指令只读存储（word-addressable），以 byte 地址输入（`addr`），输出 32-bit 指令 `inst`。
* **实现要点**：

  * 参数化 `ADDR_WIDTH` -> 深度 = `2^ADDR_WIDTH` words。
  * 将字节地址转为字地址：`word_index = addr[ADDR_WIDTH+1:2]`（丢弃低 2 位）。
  * 默认用 `addi x0,x0,0` 填充（NOP），并尝试 `$readmemh("imem.hex", mem)`。
* **适用/限制**：组合读取适合仿真/教学；FPGA 上通常改用 block RAM（同步读，1-cycle latency）。

## `if_stage`

* **功能**：封装 `imem` 并生成 `pc_plus_4`。
* **要点**：`pc` -> `inst`（来自 `imem`），并立即计算 `pc+4`（组合逻辑）。

## `decoder`

* **功能**：把 32-bit 指令拆解为 opcode/funct3/funct7/寄存器索引与立即数，并生成控制信号（`reg_write`, `alu_src`, `alu_op`, `mem_read` 等）。
* **设计思路**：

  * 默认先清零/置默认值，然后按 `opcode` case 分支设置有效字段 (`rd_v`, `rs1_v`, `rs2_v`) 与控制位。
  * 立即数在各类型（I/S/B/J/U）中按 RISC-V 格式展开并符号扩展或左移（U-type）。
  * `wb_sel` 用于写回来源选择（ALU/MEM/PC+4/LUI）。
* **注意点**：

  * immediates 的位拼接与符号位索引要严格对应 RISC-V 手册（已在代码实现，但复查 bit 顺序与扩展位很重要）。
  * `illegal` 用于 SYSTEM/CSR 简化处理。

## `alu_control`

* **功能**：从 decoder 的 `alu_op` + 指令的 `funct3/funct7` 生成 ALU 控制编码 (`alu_ctrl`)。
* **设计**：把类别（R-type, I-type, ADD-category, LUI）映射到具体 ALU 操作（ADD, SUB, SLL, ...）。

## `alu_core`

* **功能**：基于 `alu_ctrl` 对 `op1/op2` 执行算术/逻辑/shift，并输出 `result`、标志 `zero/slt/sltu`。
* **实现细节**：

  * `sra` 使用有符号移位（`>>>`）。
  * `slt` / `sltu` 分别基于 signed 与 unsigned 比较。
  * `LUI` 的 convention：op2 已经是 `imm << 12`（ID 层负责左移）。

## `alu_top`

* **功能**：ALU 控制器 + ALU 核心封装；负责选择 op2（`imm` 或 `rs2`）并提供 `alu_result` 与标志。
* **特别**：AUIPC 通过外部把 `op1=pc` 传入（在 `cpu_top` 中完成）。

## `pc_reg`

* **功能**：PC 寄存器（同步上升沿写，低电平复位清零）。
* **接口**：外部计算 `pc_next` 并在上升沿采样；`rst_n` 为异步低有效复位。

## `regfile`

* **功能**：32x32 寄存器堆；支持 2 读口、1 写口；写通（write-through）使得同周期读到写入数据。
* **实现要点**：

  * 写在时钟上（posedge），而读是组合逻辑（`always @(*)`）。
  * 写使能且目标 != x0 才写；同时额外保证 `regs[0] <= 0`。
  * 组合读时，如果本周期发生写且索引匹配则直接返回 `rd_wdata`（write-through）。
* **注意**：组合读 + 时序写的 write-through 实现对仿真方便，但合成时要注意工具如何映射寄存器堆（通常会推断双口RAM或寄存器集）。

## `mem_branch_unit`

* **功能**：合并数据存储（DMEM）和分支判定逻辑。
* **实现细节**：

  * 内部是 word-addressable `mem` 数组，可通过 `$readmemh("dmem.hex", mem)` 初始化。
  * **写**：在 `posedge clk` 同步写入（使用 **阻塞赋值** `mem[word_index] = ...` 以便仿真写通）；按 `mem_width` 做字/半/字节写合并。
  * **读**：组合逻辑中根据 `mem_width`/`byte_offset` 提取并做符号/零扩展（LB/LH/LW/LBU/LHU）。
  * **分支**：根据 ALU 提供的 `zero/slt/sltu` 与 `branch_type` 计算 `branch_taken`（组合）。
* **注意/问题点**：

  * 使用阻塞赋值和组合读使仿真里写后立刻可见（方便 write-through），但在综合为 BRAM 时行为不同（BRAM 通常为同步读）。
  * 对齐假设：半字/字写入假定字边界对齐；非对齐写/读被“泛化”处理或保留原字一部分。
  * 若要在 FPGA 上合成，需要将 DMEM 映射为 Block RAM 并适配其读/写时序（通常同步读、写时刻、管脚）。

## `wb_controller_single`

* **功能**：单周期写回控制；根据 `dec_reg_write` 与 `dec_wb_sel` 决定写回寄存器的数据来源并输出 `rf_we/rf_wd_idx/rf_wd_data`（组合逻辑）。
* **要点**：

  * 对 `dec_rd == 0`（x0）做保护，不写回。
  * LUI 的写回使用 `dec_imm_u`（decoder 已经把 imm 左移 12）。

## `cpu_top`

* **功能**：顶层互连，形成完整单周期 datapath。
* **连接要点**：

  * IF：`pc_reg` <- `pc_next`；`if_stage` 提供 `inst, pc_plus_4`。
  * ID：`decoder` 解析指令生成控制/立即数，`regfile` 提供操作数（并且有 write-through）。
  * EX：`alu_top` 执行（AUIPC 通过把 `alu_op1 = pc` 实现）。
  * MEM：`mem_branch_unit` 提供读数据、写入功能与分支判定。
  * PC 更新逻辑 (`pc_next`)：

    * 如果 `jump` (JAL) -> `pc + imm`
    * else if `jalr` -> `jalr_target = (rs1 + imm) & ~1`
    * else if `(branch && branch_taken)` -> `branch_target`
    * else -> `pc_plus_4`
  * WB：`wb_controller_single` 决定写回并驱动 `regfile` 写口。

---

# 数据流 & 单周期时序（逐步骤说明）

单周期执行的一条指令在同一时钟周期内经过所有阶段（没有中间寄存器），因此时序上是**组合级累积 + 写在时钟边沿**。典型顺序（逻辑顺序，物理上是组合链）：

1. **PC（寄存器）在上一个上升沿已被加载为 `pc`**（stable during cycle）
2. **IF**（组合）：

   * `pc` -> `imem` -> 输出 `inst`（组合）
   * 计算 `pc_plus_4 = pc + 4`（组合）
3. **ID（组合）**：

   * `decoder` 解析 `inst` → 立即数 & 控制信号（组合）
   * `regfile` 的组合读输出 `rs1_data`, `rs2_data`（若本周期将写且目标与读索引相同，write-through 会返回 `rd_wdata`）
4. **EX（组合）**：

   * 选择 `alu_op1`（`pc` 或 `rs1`），`op2`（`imm` 或 `rs2`），调用 `alu_control`→`alu_core` 得到 `alu_result`、`zero/slt/sltu`（全部组合）
5. **MEM（组合 + 同步写）**：

   * `mem_branch_unit` 根据 `alu_result` 作为地址进行组合读（`read_data`）或在时钟沿进行同步写（`mem_write`）。
   * 同时基于 `branch` + flags 计算 `branch_taken`（组合）与 `branch_target`（`pc + imm`，组合）。
6. **PC_next 决定（组合）**：

   * 使用 `jump/jalr/branch_taken` 与 `pc_plus_4` 计算下一个 PC 值（组合），并在下一上升沿由 `pc_reg` 写入 PC。
7. **WB（组合）**：

   * `wb_controller_single` 在同一周期组合计算 `rf_we/rf_wd_idx/rf_wd_data`（使用 `alu_result`, `mem_read_data`, `pc_plus_4` 等），并在下一个上升沿由 `regfile` 接受写（同步写）。

**时序要求（概念）**：时钟周期必须大于或等于：

```
t_pc_reg_q + t_imem_read + t_decoder + t_regfile_read + t_alu + t_mem_access(combinational read) + t_wb_logic + t_setup_regfile
```

（此外还要考虑 routing/clock skew/synthesis 后延迟）。这就是单周期实现的短板：周期很长，频率低。

---

# 关键实现细节与易错点（检查清单）

* **immediate 拼接与符号扩展**：确认 B/J 型等的拼接位顺序与符号扩展是否正确（decoder 中的位拼接已给出，复查 bit 序列）。
* **mem_branch_unit 写/读语义**：

  * 写使用阻塞赋值以保证仿真中“写立即可见”；综合到 BRAM 时可能行为不同（同步读 vs 异步读）。
  * 若要在 FPGA 上工作，应改为非阻塞 `<=` 并调整 read 为同步读或在读取后 pipeline 一个周期。
* **regfile write-through**：

  * 组合读 + 同周期写的实现为仿真友好，但合成产生的硬件可能不是完全等价（合成工具通常会推断双口 RAM）；测试要覆盖写和读同索引的情况。
* **对齐假设**：代码对半/字边界做了基本处理，但非对齐 load/store 可能存在不完整或未定义行为，需在设计文档中明确支持范围。
* **x0保护**：`regfile` 强制 `regs[0] <= 0`，并且 `wb_controller_single` 阻止写到 x0，双重保护是安全的。
* **SYSTEM/CALL/CSR 未实现**：`decoder` 对 opcode `1110011` 标记 `illegal`；异常/中断/CSR 路径需另行实现。
* **shift 与 sra 判断**：`funct7[5]` 被用来区分 `SUB`/`ADD` 和 `SRA`/`SRL`，确认 `funct7` 的位编号与指令编码一致。

---

# 验证 / 调试 / 仿真建议

* **必备测试用例**：

  * 加法/减法/逻辑/移位/比较的基本指令序列；
  * Load/Store（LB/LH/LW/LBU/LHU，SB/SH/SW）对齐与非对齐测试；
  * Branch 指令（BEQ/BNE/BLT/BGE/BLTU/BGEU）组合，确保 `zero/slt/sltu` 的行为正确；
  * JAL/JALR，LUI/AUIPC；
  * 写 x0 行为验证（应保持 0）。
* **仿真流程**：

  * 用 `imem.hex` 加载测试指令流，用 `dmem.hex` 初始化数据段。
  * 在 wave/view 中关注信号：`pc`, `inst`, `rs1_data`, `rs2_data`, `alu_result`, `mem_read_data`, `rf_we`, `rf_wd_idx`, `pc_next`, `branch_taken`。
  * 检查复位序列：在复位期间 `pc==0` 且 `regs==0`。
* **测试工具/环境建议**：

  * ModelSim / Questa / iverilog + gtkwave。`$readmemh` 文件路径在仿真目录中要正确。
* **断言/自检**：

  * 在仿真中加入 `$display` 输出关键事件（异常/非法指令/分支跳转/写回）以便回放测试 trace。
  * 可加入简单的 `assert`（`if (cond) $display("...")`）检测对齐/非法操作。

---

# 优化与扩展策略（优先级 + 思路）

> 目标：提高频率、功能完整性、可综合性与可维护性。

## 短期（优先）

1. **把数据和指令存储映射到 FPGA BRAM**：

   * 修改 `imem` 和 `mem_branch_unit` 以采用同步读写的 RAM 接口（读取延迟 1 周期）或在读端插入 pipeline 寄存器。
2. **替换阻塞写（`mem`）为非阻塞赋值（`<=`）并使读/写语义一致**（更合成友好）。
3. **把 `regfile` 的组合读改成合成友好的实现**（或确认综合后寄存器堆映射），并提供规范接口（双口 RAM）。
4. **完善异常/CSR 支持**（系统调用、环境/中断处理）。

## 中期

1. **实现五级流水线（IF/ID/EX/MEM/WB）**：

   * 插入阶段寄存器，解决时序瓶颈，显著提升时钟频率。
   * 增加**冒险检测单元（hazard unit）**与**转发单元（forwarding）**，并实现分支冒险处理（flush/stall）。
2. **实现分支预测（静态或简单动态）以减少分支惩罚**。
3. **为 MEM 引入 Cache 或流水化存储访问**（支持非阻塞 load/store 和等待/握手）。
4. **支持 M-extension（乘除）与 A/Atomic 内存指令**（需要多周期或硬件乘法器）。
5. **实现 CSR、例外、页表（更高扩展）**。

## 长期（高级）

1. **超标量/乱序执行**（非常复杂，研究级项目）。
2. **MMU、虚拟内存、操作系统支持**。
3. **性能优化**：动态分支预测器、双发射、流水线重命名等。

---

# 综合建议（合成/工程实践）

* **不要直接在合成目标上使用阻塞赋值写内存并依赖组合读的写通语义**。FPGA 上最好采用 vendor BRAM 原语或让综合器推断 block RAM，再根据其读/写模式调整设计（可能需要额外 pipeline 寄存器）。
* **分阶段推导**：先把设计做成可工作的仿真模型（当前实现），然后逐步改为合成友好结构（同步 RAM、分段 pipeline、非阻塞）。
* **代码风格**：在 synchronous blocks 使用非阻塞 (`<=`)；在组合块使用阻塞 (`=`)，以避免赋值竞态和仿真/综合差异。
* **添加注释/形式化测试**：为每个模块添加接口注释与预期时序，便于后续移植或加 pipeline。

---

# 快速术语表 / 信号说明

* `pc` / `pc_next`：程序计数器与下一 PC。
* `pc_plus_4`：`pc + 4`，常用于 JAL 写回。
* `inst`：32-bit 指令字。
* `rd/rs1/rs2`：指令中的目标/源寄存器字段。
* `imm`：立即数（decoder 产生已符号扩展或已左移 U-type）。
* `alu_op`：decoder 给出的 ALU 类别控制。
* `alu_ctrl`：ALU 的具体操作编码（来自 `alu_control`）。
* `mem_width`：访问宽度（00=byte,01=half,10=word）。
* `mem_signed`：load 的符号扩展使能。
* `branch_taken`：分支决定（组合逻辑）。
* `rf_we/rf_wd_idx/rf_wd_data`：写回控制信号，驱动寄存器堆。

---

# Debug 快速清单（仿真中出现问题先查这些）

1. 程序不前进：检查 `pc_next` 逻辑，确认 `pc_reg` 复位/使能。
2. 指令看起来不对：确认 `imem.hex` 加载路径与字节序（little/big endian）是否一致；检查 `addr` 的索引位位选是否正确（`addr[ADDR+1:2]`）。
3. 寄存器写回丢失：检查 `wb_controller_single` 的 `dec_rd == 0` 保护，确认 `rf_we` 是否被运算覆盖。
4. load/store 数据异常：检查 `byte_offset` 及半字/字合并逻辑，查看 dmem 初始化。
5. branch 行为错误：查看 `zero/slt/sltu` 计算与 `branch_type` 映射是否一致。

---

# 最后建议（短句）

* 目前实现非常适合学习和验证 ISA 各个子部分；若目标是 FPGA 实现或更高频率运行，下一步应把设计**阶段化（流水线）并改造存储到同步 RAM/BRAM**。
* 在改进前先写一组覆盖常见指令的测试用例，并创建标准 waveform/trace，这会极大加快调试速度。


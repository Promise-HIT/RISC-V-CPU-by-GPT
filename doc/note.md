# 单周期 RV32I CPU 设计文档（重构完整版）

## 设计目标与总体架构

**目标**
实现一个清晰、可综合（FPGA-friendly）、模块化的单周期 RV32I 教学 CPU，能执行 RV32I 基本整数指令（R/I/S/B/J/U 等），便于教学、调试并可在未来扩展为流水线实现。

**总体架构（单周期）**

* IF（取指）: `pc_reg` + `if_stage`(包含 `imem`)
* ID（译码）: `decoder` 输出控制向量、立即数、有效寄存器索引
* REG（寄存器读）: `regfile` 两端口组合读、单端口同步写
* EX（执行）: `alu_top`（含 `alu_control` + `alu_core`）负责算术/地址计算与比较标志
* MEM（访存 & branch）: `mem_branch_unit`（包含 `dmem` 与分支判定逻辑）
* WB（写回）: `wb_controller` + `wb_mux` 将 ALU/MEM/PC+4/LUI 等写回寄存器

**重构要点（PC相关）**
- **PC寄存器职责简化**：仅负责存储当前PC值，不参与任何计算逻辑
- **IF阶段职责明确**：负责取指令和计算顺序执行的PC+4地址  
- **顶层模块集中控制**：统一处理所有PC跳转决策，消除逻辑冲突
- **消除冗余**：移除重复的PC+4计算，修复原有的逻辑冲突问题

---

## 关键设计决策摘要

* **模块化重构**：将PC计算逻辑从PC寄存器中分离，实现真正的单一职责原则
* **集中控制**：所有PC跳转决策（JAL/JALR/分支/顺序执行）在顶层模块统一处理
* **同步 DMEM**：选择同步 BRAM 风格的 DMEM 以便综合到 FPGA；缺点是 load 需要在下一周期写回。
* **写回延迟处理**：`wb_controller` 对 load 指令做一周期延迟写回，以确保读到同步 DMEM 的返回。
* **ALU 职责**：ALU 不解码指令类别；decoder 给出 `alu_op`/`alu_src`/`imm`，ALU 执行运算（Load/Store 时会执行 `ADD` 来计算地址）。
* **分支判定**：ALU 提供 `zero/slt/sltu` 标志，`mem_branch_unit`（或单独 branch unit）根据 `funct3` 计算 `branch_taken`，`branch_target = pc + imm`。
* **可扩展性**：清晰的PC处理流程为流水线化、分支预测、异常处理等扩展奠定良好基础。

---

## 顶层模块：`cpu_top` 概览

**职责**：实例化各子模块、连接信号、计算 `pc_next`（优先级：JAL > JALR > branch taken），协调 `wb_controller` 与同步 `dmem` 的时序。

**重构后的PC处理逻辑**

```verilog
// ========================
// 🎯 关键重构：统一的PC_next计算逻辑
// ========================
assign pc_next = (jump | jalr | (branch & branch_taken)) ? 
                (jump  ? (pc + imm) :           // JAL指令
                 jalr  ? jalr_target :          // JALR指令  
                 branch_target) :               // 分支指令
                pc_plus_4;                      // 顺序执行

// 简化的PC寄存器实例化
pc_reg u_pc_reg (
    .clk(clk),
    .rst_n(rst_n),
    .pc_next(pc_next),    // 统一的下一个PC值
    .pc(pc)
);
```

**职责划分**
- `pc_reg`：地址保管员，只负责安全存储
- `if_stage`：指令获取员+顺序计算员，负责取指和计算PC+4
- `cpu_top`：决策指挥官，综合分析决定下个PC值来源

**关键连接（高层）**

* `pc_reg`: 更新 PC（使用外部计算的pc_next）
* `if_stage` (imem): `inst = imem[pc >> 2]`，`pc_plus_4 = pc + 4`
* `decoder`: `inst -> controls, imm, rd_eff, rs1_eff, rs2_eff`
* `regfile`: `rs1_data, rs2_data`（组合读）；写端受 `wb_controller` 驱动
* `alu_top`: `rs1/rs2/imm/alu_src/alu_op -> alu_result, zero, slt, sltu`
* `mem_branch_unit`: `addr=alu_result`, `write_data=rs2_data`, `mem_*` 控制 -> `read_data`(sync), `branch_taken`, `branch_target`
* `wb_controller`: 根据 `wb_sel` 和 `mem_read` 处理写回（延迟 load）并驱动 `regfile` 写端。

---

## 模块详细说明（接口与设计要点）

### `pc_reg`（PC 寄存器）- **重构版**

**接口（简化）**
```verilog
module pc_reg (
    input  clk,
    input  rst_n,
    input [31:0] pc_next,    // 外部计算好的下一个PC值
    output reg [31:0] pc     // 当前PC值
);
```

**重构要点**
- 移除内部PC+4计算逻辑
- 移除`pc_src`选择信号
- 纯时序逻辑，只做状态存储
- 复位时从0地址开始执行

**功能与时序**
* 异步低有效复位：`pc <= 0`
* `posedge clk`：`pc <= pc_next`（直接使用外部计算值）
* `pc` 为字节地址（与 `imem`/`dmem` 协调低两位取索引）

---

### `imem` / `if_stage`（取指与指令存储）

**imem 接口**
```verilog
module imem #(
    parameter ADDR_WIDTH = 10
) (
    input  wire [31:0] addr, // byte address
    output wire [31:0] inst
);
```

**if_stage 接口**
```verilog
module if_stage #(
    parameter IMEM_ADDR_WIDTH = 10
) (
    input  wire [31:0] pc,
    output wire [31:0] inst,
    output wire [31:0] pc_plus_4
);
```

**实现要点**

* 内部 `reg [31:0] mem[0:DEPTH-1]`，`word_index = addr[ADDR_WIDTH+1:2]`，`inst = mem[word_index]`（组合）。
* 初始填充 NOP（`addi x0,x0,0`）并尝试 `$readmemh("imem.hex", mem)`。
* 推荐在 `imem` 实例命名上保持一致（便于 TB 层次访问，如 `u_cpu.u_if_stage.imem0.mem[i]`）。

**注意**

* 组合返回便于教学仿真，但不能映射成真实 FPGA BlockRAM（FPGA BRAM 为同步）。对于教学单周期可接受。

---

### `decoder`（译码 / ID）

**端口（摘要）**
```verilog
module decoder (
    input  wire [31:0] inst,
    output wire [6:0] opcode,
    output wire [2:0] funct3,
    output wire [6:0] funct7,
    output wire [4:0] raw_rd, raw_rs1, raw_rs2,
    output reg  [4:0] rd_eff, rs1_eff, rs2_eff,
    output reg         rd_v, rs1_v, rs2_v,
    output reg  [31:0] imm,
    output reg         reg_write,
    output reg  [1:0]  wb_sel,
    output reg         alu_src,
    output reg  [2:0]  alu_op,
    output reg         mem_read,
    output reg         mem_write,
    output reg  [1:0]  mem_width,
    output reg         mem_signed,
    output reg         branch,
    output reg  [2:0]  branch_type,
    output reg         jump, jalr, lui, auipc, illegal
);
```

**功能**

* 将 `inst` 按 opcode 分类：R/I/S/B/J/U/TYPES。
* 生成立即数 `imm`（I/S/B/U/J 格式，B-type 左移 1，U-type 左移 12 等）。
* 输出控制信号：`reg_write`, `wb_sel`（00=ALU,01=MEM,10=PC+4,11=LUI）、`alu_src`, `alu_op`, `mem_*`, `branch/jump/jalr` 等。
* 输出 `rd_eff/rs*_eff`（当对应类型有效时为 raw 字段，否则 0）和 `*_v` 标志。

**要点**

* `alu_op` 是高层类别（例如 `3'b000` = ADD 类，`3'b001` = SUB/compare，`3'b010` = R-type，`3'b011` = I-type，`3'b100` = LUI）
* 分离 `decoder` 与 `alu_control` 有利于扩展与清晰性。

---

### `regfile`（寄存器堆）

**接口**
```verilog
module regfile (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        reg_write,
    input  wire [4:0]  rs1_idx,
    input  wire [4:0]  rs2_idx,
    input  wire [4:0]  rd_idx,
    input  wire [31:0] rd_wdata,
    output wire [31:0] rs1_data,
    output wire [31:0] rs2_data
);
```

**功能**

* 32 x 32-bit registers (`regs[0]`..`regs[31]`)；`x0`恒为 0（写忽略或强制为 0）。
* 组合读 `rs1_data`/`rs2_data`；同步写 `rd` 在 `posedge clk`（受 `reg_write` 使能），写入发生在时钟沿。

**实现要点**

* 写在 `posedge clk`，读为组合（常见实现）；在测试中可在 posedge 后读取寄存器数组输出。

---

### `alu_control`

**接口**
```verilog
module alu_control (
    input  wire [2:0] alu_op,
    input  wire [2:0] funct3,
    input  wire [6:0] funct7,
    output reg  [3:0] alu_ctrl
);
```

**功能**

* 将高层 `alu_op` 与指令位域 `funct3/funct7` 映射到 ALU 的微操作编码（`A_ADD`, `A_SUB`, `A_SLL`, ...）。
* 例如：`alu_op == 3'b000` -> A_ADD（用于 load/store/address/addi/auipc）；`3'b010` -> R-type（根据 funct3/funct7 决定 SUB/ADD/SRA/SRL 等）

**要点**

* 映射要覆盖 R/I 指令及特殊 LUI 类别（返回 `A_LUI`）。
* `funct7[5]` 常用于区分 SUB/SRA 等。

---

### `alu_core`

**接口**
```verilog
module alu_core (
    input  wire [31:0] op1,
    input  wire [31:0] op2,
    input  wire [3:0]  alu_ctrl,
    output reg  [31:0] result,
    output wire        zero,
    output wire        slt,
    output wire        sltu
);
```

**功能**

* 根据 `alu_ctrl` 执行算术/逻辑/移位操作（ADD/SUB/SLL/SLT/SLTU/XOR/SRL/SRA/OR/AND/LUI）。
* 提供比较标志：`zero = (result == 0)`、`slt` (signed less)、`sltu` (unsigned less)。

**要点**

* 移位取 `op2[4:0]` 为 `shamt`。`A_LUI` 约定 `op2` 带有 `imm << 12`。
* `slt` 使用 `$signed` 比较，`sltu` 使用无符号比较。

---

### `alu_top`

**接口**
```verilog
module alu_top (
    input  wire [2:0]  alu_op,
    input  wire [2:0]  funct3,
    input  wire [6:0]  funct7,
    input  wire [31:0] rs1_data,
    input  wire [31:0] rs2_data,
    input  wire [31:0] imm,
    input  wire        alu_src,
    output wire [31:0] alu_result,
    output wire        zero,
    output wire        slt,
    output wire        sltu
);
```

**功能**

* 将 `alu_src` 选择 `op2 = alu_src ? imm : rs2_data`。对 AUIPC 类型，顶层把 `op1` 替换为 `pc`。
* 实例化 `alu_control` -> `alu_ctrl`，实例化 `alu_core` 生成 `alu_result` 与比较标志。

**要点**

* ALU 只执行运算，不判断指令类型；decoder 控制 ALU 的模式。

---

### `mem_branch_unit` / `dmem`（分支判定 + 数据存储）

**接口（mem_branch_unit 概览）**
```verilog
module mem_branch_unit #(
    parameter IMEM_ADDR_WIDTH = 10
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] pc,
    input  wire [31:0] imm,
    input  wire        branch,
    input  wire [2:0]  branch_type,
    input  wire        zero,
    input  wire        slt,
    input  wire        sltu,
    input  wire [31:0] addr,
    input  wire [31:0] write_data,
    input  wire        mem_read,
    input  wire        mem_write,
    input  wire [1:0]  mem_width,
    input  wire        mem_signed,
    output wire [31:0] branch_target,
    output reg         branch_taken,
    output reg  [31:0] read_data
);
```

**dmem（内部）接口**
```verilog
module dmem #(
    parameter ADDR_WIDTH = 10
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] addr,
    input  wire [31:0] write_data,
    input  wire        mem_read_en,
    input  wire        mem_write_en,
    input  wire [1:0]  mem_size,
    input  wire        mem_signed,
    output reg  [31:0] read_data
);
```

**功能**

* `branch_target = pc + imm`（组合）。
* `branch_taken` 由 `branch_type`（funct3）与 ALU 的 `zero/slt/sltu` 计算（BEQ/BNE/BLT/BGE/BLTU/BGEU）。
* `dmem` 为**同步读写**：写在 `posedge clk` 执行，读在 `mem_read_en` 后的下一个 `posedge clk` 把 `read_data` 注册输出（更接近 FPGA BRAM）。
* 支持 `mem_width`（byte/half/word）与 `mem_signed`（load 时符号扩展），未对齐通过 `addr[1:0]` 处理（但建议上层保证对齐）。

**要点**

* 为了部分写（`sb`/`sh`），实现 read-modify-write（读当前 word 合并要写的字节/半字再写回）。
* 设计决策：同步 dmem 易于综合（FPGA），但导致 load 在下一周期才返回数据，顶层需处理写回延迟。

---

### `wb_controller`（写回控制器） / `wb_mux`

**wb_mux（组合）**
```verilog
module wb_mux (
    input  wire [1:0] wb_sel,
    input  wire [31:0] alu_result,
    input  wire [31:0] mem_read_data,
    input  wire [31:0] pc_plus_4,
    input  wire [31:0] imm_u_shifted,
    output reg  [31:0] wb_data
);
```

**wb_controller（时序）**
```verilog
module wb_controller (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        dec_reg_write,
    input  wire [1:0]  dec_wb_sel,
    input  wire [4:0]  dec_rd,
    input  wire [31:0] dec_imm_u,
    input  wire [31:0] alu_result,
    input  wire [31:0] mem_read_data,
    input  wire [31:0] pc_plus_4,
    output reg         rf_we,
    output reg  [4:0]  rf_wd_idx,
    output reg  [31:0] rf_wd_data
);
```

**功能**

* 对非 load 指令（`wb_sel != 01`）直接在当前周期安排写入寄存器（写在下一个 posedge 实际生效）。
* 对 load 指令（`wb_sel == 01 && dec_reg_write==1`）在 decoder 指令周期将 `dec_rd` 和相关控制寄存为 `pending`，在下一时钟周期使用 `mem_read_data` 写回寄存器，处理同步 dmem 的延迟。
* `wb_mux` 只做组合选择，`wb_controller` 负责时序（寄存/延迟）并驱动 `regfile` 的写端口。

**要点**

* 这种设计避免在同一周期尝试读取尚未由同步 dmem 返回的数据。
* 另一种策略为统一把所有写回延迟一拍（更简单但引入额外周期延迟）。

---

## 端到端数据流与信号走向（重构后时序）

**重构后的指令周期**

1. **IF阶段**：
   - `pc_reg`输出当前地址 → `if_stage`取指令并计算`pc_plus_4`
   
2. **ID阶段**：
   - `decoder`解析指令，产生控制信号

3. **EX/MEM阶段**：
   - ALU执行运算，内存访问，分支判断

4. **PC决策阶段**（顶层）：
   - 综合分析所有控制信号（jump/jalr/branch_taken）
   - 计算`pc_next`：`跳转目标 ? pc_plus_4`

5. **PC更新**：
   - 时钟上升沿，`pc_reg`更新为`pc_next`

**关键改进**
- 消除原来`pc_src=0`时的逻辑冲突
- PC计算逻辑集中，便于维护和调试
- 为流水线化打下良好基础

**完整数据流**
1. IF: `pc` -> `if_stage.imem` -> `inst`；`pc_plus_4 = pc + 4`
2. ID: `decoder(inst)` -> control signals + `imm` + register indices -> `rs1_eff/rs2_eff/rd_eff`
3. RF read: `regfile` 输出 `rs1_data`, `rs2_data`（组合）
4. EX: `alu_top` 接收 `rs1_data`, `op2 = alu_src ? imm : rs2_data` -> `alu_result`, flags
   * 对 `L/S`: `alu_op` 被 decoder 设为 ADD 类 -> `alu_result = rs1 + imm`（地址）
5. MEM: `mem_branch_unit`:
   * Branch: use `zero/slt/sltu` + `branch_type` -> `branch_taken` and branch target `pc + imm`
   * Data: `addr = alu_result`, `write_data = rs2_data`, `mem_write`/`mem_read` 控制 `dmem`
   * `dmem.read_data` 在 `mem_read` 后 **下一个 posedge clk** 有效（同步）
6. WB: `wb_controller`:
   * Non-load: select ALU/PC+4/LUI -> write `rd` this cycle (writing occurs at next posedge)
   * Load: stage `rd` and write in next cycle using `mem_read_data` (ensures `dmem` 输出有效)

**PC 更新**
* `pc_next` chosen by priority: `jump ? pc + imm : jalr ? ((rs1 + imm) & ~1) : branch_taken ? branch_target : pc_plus_4`

---

## 测试 / 仿真要点（重构验证）

**重构验证重点**
- 验证顺序执行：PC是否正确+4递增
- 验证跳转指令：JAL/JALR是否跳转到正确目标
- 验证分支指令：条件分支是否根据标志正确跳转
- 验证优先级：JAL > JALR > Branch > 顺序执行的优先级

**小测试程序（示例）**
```
addi x1, x0, 4       ; x1 = 4
addi x2, x0, 10      ; x2 = 10
sw   x2, 0(x1)       ; MEM[4] = 10
addi x3, x0, 0       ; x3 = 0
lw   x3, 0(x1)       ; x3 = MEM[4] -> 10 (but returns next cycle)
addi x4, x3, 1       ; x4 = x3 + 1 ; may read old x3 if no NOP/stall
```

**关键仿真现象解释**
* **Load 延迟**：因为 `dmem` 为同步读，`lw` 发出 `mem_read` 后 `read_data` 在下一 posedge 可用；如果下一条指令**立即**使用 `rd`（load-use），它会看到旧值，除非插入 NOP 或实现 forwarding/stall。
* **Store 写入能看到时机**：`sw` 在其周期的 posedge 写入内存，之后读回会看到更新（取决于时序和优先策略）。
* **如何让 `addi x4, x3,1` 看到 `lw` 的结果？**
  * 在 `lw` 与 `addi` 之间插入 NOP（教学常用）；或者
  * 将 DMEM 改为组合读（仅教学仿真，不适合综合）；或者
  * 改为流水线 + forwarding/load-use stall 机制。

**Testbench / 仿真注意**
* 在 TB 中通过层次访问 `imem`/`dmem` 内部 `mem` 时确保实例名称与层次匹配（例如 `u_cpu.u_if_stage.imem.mem[i]` 或 `u_cpu.u_if_stage.imem0.mem[i]`，取决于你实例命名）。
* `imem` 内部的 `$readmemh("imem.hex", mem)` 如果文件不存在会发出警告，但层次赋值依然可用以覆盖内容。
* 打印寄存器状态时，若要显示刚写入的数据，应在 `@(posedge clk)` 中打印（因为写在 posedge 发生）。

---

## 常见问题与调试建议

**重构后可能遇到的问题**
- **PC不更新**：检查`pc_next`计算逻辑，确认跳转条件是否正确
- **错误跳转**：验证`jump`/`jalr`/`branch_taken`信号的产生时机
- **顺序执行失败**：确认`pc_plus_4`计算是否正确连接到`pc_next`

**通用调试建议**
* **仿真报层次未找到 `imem` 或 `mem`**：检查 `if_stage` 中 `imem` 的实例名（`imem0` 或 `imem`），并在 TB 使用正确路径（例如 `u_cpu.u_if_stage.imem0.mem`）。
* **看不到 lw 的返回值 / x4 未按预期变化**：确认 `dmem` 是同步还是组合读；若同步，记住 `read_data` 在下一 posedge 才有效，插入 NOP 或改变设计策略。
* **寄存器写入边沿看不到值**：寄存器写在 posedge 执行，打印寄存器状态要在 posedge 之后读取或在 `#1` 延迟后打印。
* **imem.hex 未找到警告**：若用层次赋值初始化 IMEM，此警告可以忽略；或在工程运行目录放置 `imem.hex` 消除警告。
* **部分写（sb/sh）行为不正确**：先验证 `addr[1:0]` 偏移处理是否与预期（小端），并检查 read-modify-write merge 逻辑。

**调试建议**
- 在顶层添加PC决策的调试输出
- 监控关键控制信号：`jump`, `jalr`, `branch_taken`
- 验证`pc_next`在多路选择器各路径的值

---

## 扩展方向与建议

**重构带来的优势**
- **流水线化准备**：清晰的PC处理流程便于添加流水线寄存器
- **分支预测**：集中的PC决策逻辑便于集成分支预测器
- **异常处理**：统一的PC计算便于添加异常处理机制

**扩展方向**
* **流水线化（5-stage）**：IF / ID / EX / MEM / WB 拆分，需加入寄存器（IF/ID, ID/EX, EX/MEM, MEM/WB），并实现 forwarding 单元与 hazard detection 单元（处理 load-use hazard）。
* **Forwarding**：当 EX 需要上一条或两条指令的 ALU 结果时，从 EX/MEM 或 MEM/WB 转发到 EX 的操作数以避免插入停顿（除 load-use）。
* **Load-use stall**：在检测到 EX 需要依赖 MEM（load）的数据时暂停 IF/ID 并插入 bubble。
* **分支处理**：实现分支预测或延迟槽、或早期分支决策（在 EX/MEM 阶段），并在发现错误分支时 flush 指令。
* **异步 DMEM（仅仿真）**：将 `dmem` 的读改为组合 `assign read_data = mem[index];`，让 load 立即可用（适合教学仿真，但不可综合进 BlockRAM）。
* **CSR / SYSTEM 指令 / 中断**：添加 CSR 寄存器集与 trap/exception 处理，需重新设计控制流与异常入口处理（mtvec/mepc/mcause 等）。

---

## 参考：模块端口快速索引（更新版）

### `pc_reg` - **重构版**
```verilog
module pc_reg (
    input  clk,
    input  rst_n,
    input [31:0] pc_next,    // 统一的下一个PC值
    output reg [31:0] pc     // 当前PC值
);
```

### `if_stage` / `imem`
```verilog
module if_stage #(parameter IMEM_ADDR_WIDTH=10) (
    input wire [31:0] pc,
    output wire [31:0] inst,
    output wire [31:0] pc_plus_4
);

module imem #(parameter ADDR_WIDTH=10) (
    input wire [31:0] addr,
    output wire [31:0] inst
);
```

### `decoder`（摘要）
```verilog
module decoder (
    input wire [31:0] inst,
    output wire [6:0] opcode,
    output wire [2:0] funct3,
    output wire [6:0] funct7,
    output wire [4:0] raw_rd, raw_rs1, raw_rs2,
    output reg  [4:0] rd_eff, rs1_eff, rs2_eff,
    output reg        rd_v, rs1_v, rs2_v,
    output reg  [31:0] imm,
    output reg        reg_write,
    output reg  [1:0] wb_sel,
    output reg        alu_src,
    output reg  [2:0] alu_op,
    output reg        mem_read, mem_write,
    output reg  [1:0] mem_width,
    output reg        mem_signed,
    output reg        branch,
    output reg  [2:0] branch_type,
    output reg        jump, jalr, lui, auipc,
    output reg        illegal
);
```

### `regfile`
```verilog
module regfile (
    input  wire clk, input wire rst_n,
    input  wire reg_write,
    input  wire [4:0] rs1_idx, rs2_idx, rd_idx,
    input  wire [31:0] rd_wdata,
    output wire [31:0] rs1_data, rs2_data
);
```

### ALU相关模块
```verilog
module alu_control (input wire [2:0] alu_op, input wire [2:0] funct3, input wire [6:0] funct7, output reg [3:0] alu_ctrl);
module alu_core (input wire [31:0] op1, input wire [31:0] op2, input wire [3:0] alu_ctrl, output reg [31:0] result, output wire zero, slt, sltu);
module alu_top (input wire [2:0] alu_op, input wire [2:0] funct3, input wire [6:0] funct7, input wire [31:0] rs1_data, rs2_data, imm, input wire alu_src, output wire [31:0] alu_result, output wire zero, slt, sltu);
```

### `mem_branch_unit` / `dmem`（摘要）
```verilog
module mem_branch_unit #(parameter IMEM_ADDR_WIDTH=10) (
    input wire clk, rst_n,
    input wire [31:0] pc, imm,
    input wire branch, input wire [2:0] branch_type,
    input wire zero, slt, sltu,
    input wire [31:0] addr, write_data,
    input wire mem_read, mem_write,
    input wire [1:0] mem_width,
    input wire mem_signed,
    output wire [31:0] branch_target,
    output reg branch_taken,
    output reg [31:0] read_data
);

module dmem #(parameter ADDR_WIDTH=10) (
    input wire clk, rst_n,
    input wire [31:0] addr, write_data,
    input wire mem_read_en, mem_write_en,
    input wire [1:0] mem_size,
    input wire mem_signed,
    output reg [31:0] read_data
);
```

### `wb_controller` / `wb_mux`
```verilog
module wb_mux (input wire [1:0] wb_sel, input wire [31:0] alu_result, mem_read_data, pc_plus_4, imm_u_shifted, output reg [31:0] wb_data);

module wb_controller (input wire clk, rst_n, input wire dec_reg_write, input wire [1:0] dec_wb_sel, input wire [4:0] dec_rd,
    input wire [31:0] dec_imm_u, input wire [31:0] alu_result, mem_read_data, pc_plus_4,
    output reg rf_we, output reg [4:0] rf_wd_idx, output reg [31:0] rf_wd_data);
```

### 顶层PC计算逻辑 - **新增说明**
```verilog
// 在cpu_top中的关键逻辑
assign pc_next = (jump | jalr | (branch & branch_taken)) ? 
                (jump ? (pc + imm) : jalr ? jalr_target : branch_target) : 
                pc_plus_4;
```

---

## 附录：小型测试程序示例（汇编 + 目的）

```
# 测试1: 基础 load/store 与 writeback 延迟
addi x1, x0, 4     # x1 = 4
addi x2, x0, 10    # x2 = 10
sw   x2, 0(x1)     # MEM[4] = 10
addi x3, x0, 0     # x3 = 0 (clear)
lw   x3, 0(x1)     # x3 <- MEM[4] (load: read next cycle)
nop                # 插入 NOP 以等待 load 完成（或用流水线/forwarding 处理）
addi x4, x3, 1     # x4 = x3 + 1  (若 NOP 存在 x4 = 11)
```

## 总结

这次重构实现了：
1. ✅ **职责分离**：PC存储、指令获取、跳转决策各司其职
2. ✅ **逻辑清晰**：消除冗余计算和冲突逻辑
3. ✅ **易于维护**：PC相关逻辑集中，便于调试和扩展
4. ✅ **架构优化**：为后续流水线化奠定良好基础

重构后的设计更加符合现代CPU设计的模块化、流水线友好原则，解决了原有设计中PC寄存器内部逻辑与顶层控制逻辑的冲突问题。
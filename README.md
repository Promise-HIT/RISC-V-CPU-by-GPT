# Single-cycle RV32I CPU — Educational Reference Implementation

A compact, pedagogical single-cycle RV32I (RISC-V RV32I) CPU written in Verilog.
This repository implements a simple single-cycle datapath (Fetch → Decode → Execute → Memory → Writeback) intended for learning, simulation, and incremental improvement toward a synthesizable CPU.

---

## Table of contents

- [Single-cycle RV32I CPU — Educational Reference Implementation](#single-cycle-rv32i-cpu--educational-reference-implementation)
  - [Table of contents](#table-of-contents)
  - [Project overview](#project-overview)
  - [Features](#features)
  - [Repository structure](#repository-structure)
  - [Design notes \& modules](#design-notes--modules)
  - [Testing \& examples](#testing--examples)
  - [Known issues \& synthesis notes](#known-issues--synthesis-notes)
  - [Roadmap / suggested next steps](#roadmap--suggested-next-steps)
  - [License](#license)

---

## Project overview

This CPU implements the RV32I base ISA in a single-cycle style. It is optimized for clarity and education rather than top frequency. The design highlights practical tradeoffs encountered when moving from simulation-friendly Verilog to synthesizable FPGA designs.

Use it to:

* Learn RISC-V datapath/control interactions;
* Run instruction- and data-level tests with simple `imem.hex` / `dmem.hex`;
* Prototype extensions (pipeline, CSR, exceptions, caches).

---

## Features

* Full RV32I support for integer arithmetic, loads/stores (LB/LH/LW/LBU/LHU/SB/SH/SW), branches, JAL/JALR, LUI, AUIPC.
* Modular structure: `imem`, `if_stage`, `decoder`, `alu_control`, `alu_core`, `alu_top`, `pc_reg`, `regfile`, `mem_branch_unit`, `wb_controller_single`, `cpu_top`.
* Register file with write-through semantics (combinational read sees same-cycle write).
* Combined DMEM + branch unit for compactness.
* Easy-to-read code and test harnesses for simulation.

---

## Repository structure

```
.
├── rtl/
│   ├── imem.v
│   ├── if_stage.v
│   ├── decoder.v
│   ├── alu_control.v
│   ├── alu_core.v
│   ├── alu_top.v
│   ├── pc_reg.v
│   ├── regfile.v
│   ├── mem_branch_unit.v
│   ├── wb_controller_single.v
│   └── cpu_top.v
├── tb/
│   ├── tb_cpu.v            # simple testbench that instantiates cpu_top
│   ├── imem.hex            # example instruction memory image
│   └── dmem.hex            # example data memory image
├── doc/
│   └── note.md             # design note (module guide, dataflow, timing, optimizations)
├── sim/                    # example simulation scripts
├── README.md
└── LICENSE
```

---

<!-- ## Quick-start: simulate with Icarus Verilog (iverilog)

(Recommended for quick functional checks on Linux / macOS / WSL)

1. Install tools:

   * `iverilog` and `vvp` (Icarus Verilog)
   * `gtkwave` (optional, for waveform viewing)

2. Example commands:

```bash
# compile all RTL + testbench
iverilog -g2012 -o sim/cpu_tb.vvp rtl/*.v tb/tb_cpu.v

# run the simulation (console output)
vvp sim/cpu_tb.vvp

# produce waveform (if your testbench dumps to a .vcd)
# open GTKWAVE:
gtkwave sim/cpu_tb.vcd
```

3. Typical `tb_cpu.v` should:

* instantiate `cpu_top`,
* provide clock & reset,
* load `imem.hex` and `dmem.hex` via `$readmemh`,
* optionally dump VCD: `$dumpfile("sim/cpu_tb.vcd"); $dumpvars(0, tb_cpu);`.

---

## Optional: simulate with ModelSim / Questa

If you use ModelSim/Questa, typical flow:

```tcl
vlog rtl/*.v tb/tb_cpu.v
vsim -c work.tb_cpu -do "run -all; quit"
```

Adjust paths and top-level name to match the testbench.

--- -->

## Design notes & modules

Refer to `doc/note.md` for a full module-by-module explanation. Short recap:

* **imem** — instruction ROM, combinational read, default NOPs, supports `$readmemh`.
* **if_stage** — fetch stage wrapper (inst + pc+4).
* **decoder** — opcode/funct fields -> control signals, imm extraction.
* **alu_control** & **alu_core** — maps decoded ops to ALU behavior; outputs flags (`zero`, `slt`, `sltu`).
* **alu_top** — connects control to core, selects operand2 (imm vs rs2).
* **pc_reg** — PC register with async reset.
* **regfile** — 32x32 registers, combinational reads, synchronous write, write-through forwarding.
* **mem_branch_unit** — combined DMEM & branch decision; synchronous writes, combinational reads, supports byte/half/word accesses and sign-extension.
* **wb_controller_single** — selects writeback source into regfile.

---

## Testing & examples

* `tb/imem.hex` — put a minimal program (one instruction per line, hex, little-endian style according to your assembler or manual encoding).
* `tb/dmem.hex` — initial data for memory inspections.
* Create a testbench that:

  * Asserts reset for a few cycles,
  * Steps the clock,
  * Monitors `dbg_pc`, register file content, memory locations,
  * Optionally diffs expected memory/reg states.

Suggested tests:

* Arithmetic sequence to validate ALU ops.
* Loads/stores at different alignments (aligned & unaligned).
* Branches, JAL/JALR, LUI/AUIPC correctness.

---

## Known issues & synthesis notes

* **Simulation-friendly constructs**: `mem_branch_unit` uses blocking assignments and combinational reads to show "write-through" immediately. This is convenient in simulation but **not** BRAM-accurate. When targeting FPGA:

  * Map instruction/data memory to vendor BRAM primitives or infer block RAM;
  * Adjust to synchronous read semantics (1-cycle latency) or pipeline memory accesses.
* **Single-cycle timing**: entire instruction executes in one clock — long critical path and low maximum frequency. Use pipelining to improve performance.
* **CSR/SYSTEM**: system instructions and traps are not implemented (opcode `1110011` marked `illegal`).
* **Non-aligned accesses**: design handles common aligned cases; unaligned accesses may not be fully supported or require special handling.

---

## Roadmap / suggested next steps

* Make DMEM/IMEM BRAM-friendly (synchronous reads).
* Convert to a pipelined CPU (IF/ID/EX/MEM/WB) with hazard detection and forwarding.
* Implement CSR, exceptions, and interrupt support.
* Add a basic assembler/test generation script and a compliance test suite.
* Add a minimal runtime (bootloader) and run small C programs (via toolchain) to exercise ISA.

---

<!-- ## Contributing

Contributions and suggestions are welcome. Typical workflow:

1. Fork the repository.
2. Create a branch for your feature: `feature/your-feature`.
3. Add tests (simulation) that validate the change.
4. Submit a pull request with a clear description and test results.

Please follow these guidelines:

* Keep changes modular and well-documented.
* For synthesis-related changes, include target flow details (Vivado/Quartus/other).
* Add tests that fail on master and pass on your branch.

--- -->

## License

This project is released under the **MIT License**. 



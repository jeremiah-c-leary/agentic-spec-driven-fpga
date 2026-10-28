# RTL style guide

Binding rules for all RTL in `rtl/`. The gate script checks the ones marked (gated).

## Language and tools
- VHDL-2008. Must compile and elaborate with GHDL `--std=08` (gated).
- Must pass VSG 3.35 `--style jcl` with zero violations (gated). Run `vsg --fix` first, then fix the rest by hand.

## Process structure (two-process method)
- One combinational process and one clocked process per clock domain.
- Registers are held in records, split in two:
  - a **control record** (state, flags, counters) - synchronously reset;
  - a **data record** (data-path registers) - never reset.
- Combinational process: no variables. Start with default assignments
  (`ctrl_rin <= ctrl_r; data_rin <= data_r;` plus defaults for pulses), then
  override fields. Read only registers, never `*_rin`.
- Variables are allowed inside functions.
- Clocked process at the bottom of the file:
  ```vhdl
  if rising_edge(clk) then
    if (rst = '1') then
      ctrl_r <= ctrl_init;
    else
      ctrl_r <= ctrl_rin;
    end if;
    data_r <= data_rin;
  end if;
  ```
- No initial values on signal declarations.

## Project layout
- Directory structure is defined in `spec/project_layout.toml` and checked by
  the layout gate (gated).
- One entity per file; file named `<entity>.vhd` in lower case.
- Each subsystem's entities live in that subsystem's `rtl_dir`.
- The top-level directory contains only the structural top entity.
- Generic reusable blocks (e.g. synchronisers) go in `rtl/common`.

## Interfaces
- AXI4-Stream and AXI4-Lite ports use the records in `pkg/axis_pkg.vhd` and
  `pkg/axil_pkg.vhd`. Do not modify the packages.
- Component instantiation (jcl rule), not direct entity instantiation.

## Architecture
- Data paths are pipelines, not multiplexers, wherever the behaviour allows.
- Follow `spec/block_diagram.md` for partitioning and clock-domain crossings.
- CDC synchronisers are separate signals (not in a record), not reset, and
  carry `attribute ASYNC_REG ... "TRUE"`.
- Multi-bit values crossing clock domains must be quasi-static and qualified
  by a synchronised handshake. Never synchronise a multi-bit bus bit by bit.

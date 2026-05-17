# Space Invaders (8086 Assembly) — COAL Project

This repository contains a simplified **Space Invaders** clone written in **8086 assembly** for the **emu8086** environment, plus the accompanying project report (LaTeX/Overleaf source and exported PDFs).

## Project Structure

- `space_invaders_fixed.asm` — Main, recommended version of the game (DOS `.COM`, `org 100h`).
- `Space Invaders.asm` — Alternate/earlier version of the game source.
- `overleaf/main.tex` — Report source (LaTeX).
- `overleaf/images/` — Figures used by the report.
- `CEN323-COAL-SemesterProject-08052026-091328am.pdf`, `G00_00-000000-000_FinalProject.pdf` — Exported PDFs (report submissions/versions).

## Requirements

- **emu8086** (recommended) to assemble and run the `.asm` sources as a DOS `.COM` program.
- A DOS-compatible environment if you want to run the resulting `.COM` outside emu8086 (e.g., DOSBox), provided your toolchain supports assembling the source.

## Run the Game (emu8086)

1. Open `space_invaders_fixed.asm` in emu8086.
2. Assemble/compile, then run the program.

### Controls

- Move: `A` / `D` or Left / Right arrow keys
- Shoot: `Space`
- Restart: `R`
- Quit: `ESC`



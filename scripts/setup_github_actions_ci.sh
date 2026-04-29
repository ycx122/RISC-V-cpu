#!/usr/bin/env bash
set -euo pipefail

# Resolve repo root from this script location.
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workflow_dir="$repo_root/.github/workflows"
mkdir -p "$workflow_dir"

cat > "$workflow_dir/ci.yml" <<'YAML'
name: CI

on:
  pull_request:
  push:
    branches: ["main"]
  workflow_dispatch:

jobs:
  fast:
    runs-on: ubuntu-24.04
    timeout-minutes: 20
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Install dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y iverilog verilator gcc-riscv64-unknown-elf \
            binutils-riscv64-unknown-elf picolibc-riscv64-unknown-elf vim-common

      - name: make lint
        run: make lint

      - name: make smoke
        run: make smoke

      - name: make smoke-mi
        env:
          MI_SMOKE_TIMEOUT: "60s"
        run: make smoke-mi

  regression:
    if: github.event_name != 'pull_request'
    runs-on: ubuntu-24.04
    timeout-minutes: 60
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Install dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y iverilog verilator gcc-riscv64-unknown-elf \
            binutils-riscv64-unknown-elf picolibc-riscv64-unknown-elf vim-common

      - name: make test (includes isa regression)
        env:
          ISA_TIMEOUT: "20s"
          MI_SMOKE_TIMEOUT: "60s"
        run: make test
YAML

echo "[ok] Wrote $workflow_dir/ci.yml"

# Shared helpers for the sim/*.sh and scripts/lint.sh entry points.
#
# This file is meant to be `source`d, not executed directly:
#
#   script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
#   repo_root=$(cd "$script_dir/.." && pwd)
#   source "$repo_root/sim/scripts/common.sh"
#
#   rtl_files=()
#   load_filelist "$repo_root/sim/filelist/tb_common.f"
#   load_filelist "$repo_root/sim/filelist/rtl_core.f"
#   load_filelist "$repo_root/sim/filelist/rtl_soc.f"
#   load_filelist "$repo_root/sim/filelist/sim_stubs.f"
#
# `load_filelist <path>` appends the Verilog source paths listed in `<path>`
# to the caller-visible `rtl_files` array.  Paths inside the .f file are
# relative to the repo root; `#` introduces a line comment and blank lines
# are skipped.  The outer script is expected to pre-declare
# `rtl_files=()` and to have `repo_root` set.

load_filelist() {
    local filelist="$1"
    if [[ ! -f "$filelist" ]]; then
        echo "load_filelist: missing file list $filelist" >&2
        return 1
    fi

    local line stripped
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Strip comments and surrounding whitespace.
        stripped="${line%%#*}"
        # Remove leading/trailing spaces/tabs.
        stripped="${stripped#"${stripped%%[![:space:]]*}"}"
        stripped="${stripped%"${stripped##*[![:space:]]}"}"
        [[ -z "$stripped" ]] && continue
        rtl_files+=("$repo_root/$stripped")
    done < "$filelist"
}

# ---------------------------------------------------------------------------
# RISC-V toolchain discovery
# ---------------------------------------------------------------------------
#
# `find_riscv_tool <tool>` prints the absolute path to riscv64-unknown-elf-<tool>
# (e.g. gcc, objcopy, as, objdump). It returns non-zero and prints nothing if
# no toolchain is found.
#
# Lookup order (first hit wins):
#   1. $RISCV_PATH/bin/$RISCV_PREFIX<tool>   (explicit override)
#   2. $RISCV_PREFIX<tool> on $PATH          (e.g. apt's gcc-riscv64-unknown-elf 13.2)
#   3. Vendored 8.3.0 under sw/tinyriscv/tests/toolchain/   (offline fallback)
#
# `find_riscv_toolbin` is a convenience wrapper that returns the bin/ dir of
# the resolved toolchain, matching the legacy `toolbin=...` pattern used in
# the sim/*.sh scripts.
#
# Both helpers require `repo_root` to be set in the caller (same convention
# as `load_filelist`).  Offline fallback directory name is parsed from
# sw/toolchain/riscv_toolchain.mk (same as Make builds).

_find_riscv_vendored_bin_rel() {
    [[ -n "${RISCV_VENDORED_BIN_REL:-}" ]] && return 0
    local rel_dir="riscv64-unknown-elf-gcc-8.3.0-2020.04.0-x86_64-linux-ubuntu14"
    if [[ -n "${repo_root:-}" ]]; then
        local mk="$repo_root/sw/toolchain/riscv_toolchain.mk"
        if [[ -f "$mk" ]]; then
            rel_dir=$(sed -n 's/^[[:space:]]*RISCV_VENDORED_GCC_RELEASE_DIR[[:space:]]*[?:]*=[[:space:]]*//p' "$mk" | head -1 | tr -d ' \r')
            [[ -z "$rel_dir" ]] && rel_dir="riscv64-unknown-elf-gcc-8.3.0-2020.04.0-x86_64-linux-ubuntu14"
        fi
    fi
    RISCV_VENDORED_BIN_REL="sw/tinyriscv/tests/toolchain/${rel_dir}/bin"
}

find_riscv_tool() {
    local tool="$1"
    local prefix="${RISCV_PREFIX:-riscv64-unknown-elf-}"
    local cand

    if [[ -z "$tool" ]]; then
        echo "find_riscv_tool: missing tool name" >&2
        return 2
    fi

    if [[ -n "${RISCV_PATH:-}" ]]; then
        cand="$RISCV_PATH/bin/${prefix}${tool}"
        if [[ -x "$cand" ]]; then
            printf '%s\n' "$cand"
            return 0
        fi
    fi

    cand=$(command -v "${prefix}${tool}" 2>/dev/null || true)
    if [[ -n "$cand" ]]; then
        printf '%s\n' "$cand"
        return 0
    fi

    if [[ -z "${repo_root:-}" ]]; then
        echo "find_riscv_tool: repo_root is not set" >&2
        return 2
    fi
    _find_riscv_vendored_bin_rel
    cand="$repo_root/$RISCV_VENDORED_BIN_REL/${prefix}${tool}"
    if [[ -x "$cand" ]]; then
        printf '%s\n' "$cand"
        return 0
    fi

    return 1
}

find_riscv_toolbin() {
    local gcc_path
    gcc_path=$(find_riscv_tool gcc) || return 1
    printf '%s\n' "$(dirname "$gcc_path")"
}

# `find_riscv_march <base>` prints the appropriate -march string for the
# resolved toolchain. <base> defaults to "rv32im". Modern toolchains
# (binutils >= 2.38, GCC >= 12) need `_zicsr_zifencei` listed explicitly so
# .S files that use csrr / csrw / fence.i still assemble; older ones --
# including the vendored 8.3.0 -- reject the spelling.
#
# The probe runs once per shell and is cached in $_RISCV_MARCH_CACHE_<base>.
find_riscv_march() {
    local base="${1:-rv32im}"
    local cache_var="_RISCV_MARCH_CACHE_${base//[^A-Za-z0-9]/_}"
    if [[ -n "${!cache_var:-}" ]]; then
        printf '%s\n' "${!cache_var}"
        return 0
    fi

    local gcc_path
    gcc_path=$(find_riscv_tool gcc) || return 1

    local result="$base"
    if "$gcc_path" -march="${base}_zicsr_zifencei" -mabi=ilp32 \
            -x c -c -o /dev/null - </dev/null 2>/dev/null; then
        result="${base}_zicsr_zifencei"
    fi
    printf -v "$cache_var" '%s' "$result"
    export "$cache_var"
    printf '%s\n' "$result"
}

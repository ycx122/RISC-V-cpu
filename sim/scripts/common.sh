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

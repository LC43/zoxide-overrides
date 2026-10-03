#!/usr/bin/env bash
# Install zoxide-overrides into a shell rc file.
#
#   ./install.sh              add to ~/.bashrc (or ~/.zshrc for zsh)
#   ./install.sh --shell zsh add to ~/.zshrc
#   ./install.sh --rc ./my.rc write to that file instead
#   ./install.sh --uninstall remove the block again
#
# Idempotent: re-running reports "already installed" and changes nothing.

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
plugin=$script_dir/zoxide-overrides.sh

begin_marker='# >>> zoxide-overrides >>>'
end_marker='# <<< zoxide-overrides <<<'

shell=bash
rc=
uninstall=0

die() {
    printf 'install.sh: %s\n' "$1" >&2
    exit 1
}

usage() {
    sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --shell)
            [[ $# -ge 2 ]] || die "--shell needs a value"
            shell=$2
            shift 2
            ;;
        --rc)
            [[ $# -ge 2 ]] || die "--rc needs a value"
            rc=$2
            shift 2
            ;;
        --uninstall)
            uninstall=1
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            die "unknown argument: $1 (try --help)"
            ;;
    esac
done

[[ -r $plugin ]] || die "cannot read $plugin"

if [[ -z $rc ]]; then
    case $shell in
        bash) rc=${ZDOTDIR:-$HOME}/.bashrc ;;
        zsh) rc=${ZDOTDIR:-$HOME}/.zshrc ;;
        *) die "unsupported shell: $shell" ;;
    esac
fi

mkdir -p "$(dirname -- "$rc")"
touch "$rc"

if grep -qF "$begin_marker" "$rc"; then
    if [[ $uninstall -eq 1 ]]; then
        tmp=$rc.zotmp.$$
        awk -v b="$begin_marker" -v e="$end_marker" '
            $0 == b { skip = 1 }
            skip != 1  { print }
            $0 == e { skip = 0 }
        ' "$rc" >"$tmp"
        mv -f "$tmp" "$rc"
        printf 'removed zoxide-overrides from %s\n' "$rc"
        printf 'note: %s was not deleted (your overrides live there)\n' \
            "${_ZO_OVERRIDES_FILE:-$HOME/.config/zoxide/overrides}"
    else
        printf 'already installed in %s\n' "$rc"
    fi
    exit 0
fi

if [[ $uninstall -eq 1 ]]; then
    printf 'not installed in %s, nothing to do\n' "$rc"
    exit 0
fi

block=$(cat <<EOF
$begin_marker
# Pin \`z <name>\` to a directory, ignoring zoxide's ranking. See: zo -l
[[ -r $plugin ]] && source $plugin
$end_marker
EOF
)

printf '\n%s\n' "$block" >>"$rc"

printf 'installed to %s\n\n' "$rc"
printf 'zoxide must be initialised first, so check the order in that file:\n'
printf '  eval "$(zoxide init %s)"\n' "$shell"
printf '  [[ -r %s ]] && source %s\n\n' "$plugin" "$plugin"
printf 'the zoxide line has to come first. Then:\n'
printf '  source %s\n' "$rc"
printf '  zo mydir /path/to/dir\n'
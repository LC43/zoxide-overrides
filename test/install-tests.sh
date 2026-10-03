#!/usr/bin/env bash
# Tests for install.sh. Uses a throwaway rc file, never your real one.

set -uo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
installer=$script_dir/../install.sh

pass_count=0
fail_count=0

if [[ -t 1 ]]; then
    green=$'\033[32m' red=$'\033[31m' dim=$'\033[2m' off=$'\033[0m'
else
    green= red= dim= off=
fi

ok() {
    pass_count=$((pass_count + 1))
    printf '  %sPASS%s %s\n' "$green" "$off" "$1"
}

no() {
    fail_count=$((fail_count + 1))
    printf '  %sFAIL%s %s\n' "$red" "$off" "$1"
    [[ $# -ge 2 ]] && printf '       %s%s%s\n' "$dim" "$2" "$off"
}

is() {
    if [[ $2 == "$3" ]]; then ok "$1"; else no "$1" "want [$2] got [$3]"; fi
}

sandbox=$(mktemp -d)
# guard on BASHPID: only the main shell may clean up, never a $( ) subshell
main_pid=$BASHPID
trap '[[ $BASHPID == $main_pid ]] && rm -rf "$sandbox"' EXIT

rc=$sandbox/dotfiles.bash
printf '# existing config\nexport FOO=1\n' >"$rc"

printf '\n== install ==\n'

out=$("$installer" --rc "$rc" 2>&1)
[[ $out == *"installed to $rc"* ]] && ok "reports the rc file" || no "reports the rc file" "got [$out]"
grep -qF 'zoxide-overrides.sh' "$rc" && ok "writes the source line" || no "writes the source line"
grep -qF '# >>> zoxide-overrides >>>' "$rc" && ok "writes a begin marker" || no "writes a begin marker"
grep -qF '# <<< zoxide-overrides <<<' "$rc" && ok "writes an end marker" || no "writes an end marker"
grep -qF 'export FOO=1' "$rc" && ok "keeps existing config" || no "keeps existing config"
[[ $(grep -cF 'zoxide-overrides.sh' "$rc") -eq 1 ]] && ok "one block only" || no "one block only"

printf '\n== idempotence ==\n'

before=$(cat "$rc")
out=$("$installer" --rc "$rc" 2>&1)
is "second run changes nothing" "$before" "$(cat "$rc")"
[[ $out == *"already installed"* ]] && ok "says already installed" || no "says already installed" "got [$out]"

printf '\n== uninstall ==\n'

out=$("$installer" --rc "$rc" --uninstall 2>&1)
[[ $out == *"removed"* ]] && ok "reports removal" || no "reports removal" "got [$out]"
if grep -qF 'zoxide-overrides.sh' "$rc"; then no "block is gone"; else ok "block is gone"; fi
if grep -qF 'export FOO=1' "$rc"; then ok "existing config survived"; else no "existing config survived"; fi

out=$("$installer" --rc "$rc" --uninstall 2>&1)
[[ $out == *"nothing to do"* ]] && ok "uninstall is idempotent" || no "uninstall is idempotent" "got [$out]"

printf '\n== shell selection ==\n'

fakehome=$sandbox/home
mkdir -p "$fakehome"
out=$(HOME=$fakehome "$installer" 2>&1)
[[ -f $fakehome/.bashrc ]] && ok "defaults to ~/.bashrc" || no "defaults to ~/.bashrc" "got [$out]"

out=$(HOME=$fakehome "$installer" --shell zsh 2>&1)
[[ -f $fakehome/.zshrc ]] && ok "honours --shell zsh" || no "honours --shell zsh" "got [$out]"

out=$(HOME=$fakehome ZDOTDIR=$sandbox/zdot "$installer" --shell zsh 2>&1)
[[ -f $sandbox/zdot/.zshrc ]] && ok "honours ZDOTDIR" || no "honours ZDOTDIR" "got [$out]"

out=$(HOME=$fakehome "$installer" --shell tcsh 2>&1)
is "rejects unknown shells" "1" "$?"

out=$("$installer" --bogus 2>&1)
is "rejects unknown flags" "1" "$?"

out=$("$installer" --help 2>&1)
rc=$?
is "--help exits 0" "0" "$rc"
for flag in --shell --rc --uninstall; do
    [[ $out == *"$flag"* ]] && ok "--help documents $flag" \
        || no "--help documents $flag" "got [$out]"
done
[[ $out != *"[[ -r"* ]] && ok "--help prints prose, not the script body" \
    || no "--help prints prose, not the script body" "got [$out]"

is "-h is an alias for --help" "$("$installer" --help 2>&1)" "$("$installer" -h 2>&1)"

out=$("$installer" --shell 2>&1)
is "rejects a flag with no value" "1" "$?"

printf '\n== the written block actually loads ==\n'

rc2=$sandbox/rc-under-test.bash
loader=$sandbox/loader.bash
printf 'eval "$(zoxide init bash)"\n' >"$rc2"
"$installer" --rc "$rc2" >/dev/null

cat >"$loader" <<'LOAD'
eval "$(zoxide init bash)"
source "$1"
declare -F zo >/dev/null && echo has-zo || echo no-zo
declare -F __zoxide_z >/dev/null && echo z-intact || echo z-broken
LOAD
out=$(_ZO_OVERRIDES_FILE=$sandbox/.data bash "$loader" "$rc2" 2>&1 | tr '\n' ' ')
[[ $out == *"has-zo"* ]] && ok "defines zo after sourcing" || no "defines zo after sourcing" "got [$out]"
[[ $out == *"z-intact"* ]] && ok "wraps z without breaking it" || no "wraps z without breaking it" "got [$out]"

printf '\n%s passed, %s failed\n' "$pass_count" "$fail_count"
[[ $fail_count -eq 0 ]]
#!/usr/bin/env bash
# End-to-end tests for zoxide-overrides. Runs in a throwaway HOME with a
# throwaway overrides file, so it never touches your real config.
#
#   ./test/run-tests.sh
#
# Requires: zoxide. fzf is only needed for the interactive `zi` path.

set -uo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
plugin=$script_dir/../zoxide-overrides.sh

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
    if [[ $2 == "$3" ]]; then
        ok "$1"
    else
        no "$1" "want [$2] got [$3]"
    fi
}

command -v zoxide >/dev/null 2>&1 || {
    printf 'zoxide is not installed\n' >&2
    exit 1
}

# --- sandbox ---------------------------------------------------------------

sandbox=$(mktemp -d)
# guard on BASHPID: only the main shell may clean up, never a $( ) subshell
main_pid=$BASHPID
trap '[[ $BASHPID == $main_pid ]] && rm -rf "$sandbox"' EXIT

export HOME=$sandbox/home
export _ZO_OVERRIDES_FILE=$HOME/.config/zoxide/overrides

site=$sandbox/site
repo=$site/astro/repo
mkdir -p "$HOME" "$repo/src/components" "$repo/docs" "$site/other/deep"
touch "$repo/README.md"

eval "$(zoxide init bash)"
# shellcheck source=/dev/null
source "$plugin"

# zoxide records directories from its PROMPT_COMMAND hook, which never fires in a
# non-interactive test run, so seed the db by hand for the "zoxide still works"
# assertions below.
zoxide add "$repo/src" "$site/other" "$repo" >/dev/null

at_home() {
    cd "$HOME" || exit 1
}

zo_noop() { zo "$@" >/dev/null 2>&1; }

printf '\n== zo command ==\n'

out=$(zo demo "$repo")
is "zo creates an override" "demo -> $repo" "$out"
_zo_load_overrides # zo ran in a subshell; pick up its write
is "path stored absolute" "$repo" "${_ZO_OVERRIDES[demo]-}"
[[ -f $_ZO_OVERRIDES_FILE ]] && ok "data file written" || no "data file written"

out=$(zo -l)
[[ $out == *demo* && $out == *"$repo"* ]] && ok "zo -l lists it" || no "zo -l lists it" "got [$out]"

out=$(zo demo "$site/other")
is "zo updates an existing override" "demo -> $site/other" "$out"
_zo_load_overrides
is "update replaced the path" "$site/other" "${_ZO_OVERRIDES[demo]-}"

zo_noop demo "$repo"

out=$(zo nope "$sandbox/nope" 2>&1)
is "zo rejects a missing dir" "zo: not a directory: $sandbox/nope" "$out"

out=$(zo -d nosuch 2>&1)
is "zo -d on unknown name fails" "zo: no such override: nosuch" "$out"

zo onearg >/dev/null 2>&1
is "zo needs two args" "2" "$?"

out=$(zo -h 2>&1 | head -1)
is "zo -h prints usage" "usage:" "$out"

zo_noop "spaced name" "$site/other"

printf '\n== z / zi routing ==\n'

at_home
z demo
is "z <override>" "$repo" "$PWD"

at_home
zi demo 2>/dev/null
is "zi <override>" "$repo" "$PWD"

at_home
z demo src
is "z <override> <subdir>" "$repo/src" "$PWD"

at_home
z demo /src
is "leading slash on subpath" "$repo/src" "$PWD"

at_home
z demo src/
is "trailing slash on subpath" "$repo/src" "$PWD"

at_home
z demo nosuchdir 2>/dev/null
is "unknown subpath does not move" "$HOME" "$PWD"

at_home
z demo .. 2>/dev/null
is "'..' subpath is refused" "$HOME" "$PWD"

at_home
z demo . 2>/dev/null
is "'.' subpath is refused" "$HOME" "$PWD"

at_home
z demo nosuch/../src 2>/dev/null
is "'..' cannot be smuggled into a subpath" "$HOME" "$PWD"

at_home
z "$HOME" 2>/dev/null
is "absolute path arg still works" "$HOME" "$PWD"

at_home
z nomatch_zzzz 2>/dev/null
is "no-match still errors" "1" "$?"

at_home
z 2>/dev/null
is "bare z goes home" "$HOME" "$PWD"

printf '\n== overrides are exact-name only ==\n'

zo_noop dem "$site/other"
at_home
z demo
is "a name that is a prefix of an override still resolves it" "$repo" "$PWD"
at_home
z de 2>/dev/null
is "a partial name falls through to zoxide" "1" "$?"
zo_noop -d dem

printf '\n== non-overrides keep using zoxide ==\n'

at_home
z src 2>/dev/null
is "zoxide still resolves other names" "$repo/src" "$PWD"

at_home
z other 2>/dev/null
is "and other paths too" "$site/other" "$PWD"

printf '\n== missing override target falls back ==\n'

gone=$sandbox/gone
mkdir -p "$gone"
zo_noop temp "$gone"
rm -rf "$gone"
at_home
err=$(z temp 2>&1 >/dev/null)
[[ $err == *"no longer exists"* ]] && ok "warns about a deleted target" \
    || no "warns about a deleted target" "got [$err]"
is "did not move" "$HOME" "$PWD"
zo_noop -d temp

printf '\n== persistence and reload ==\n'

out=$(
    cd "$HOME" || exit 1
    bash -c '
        eval "$(zoxide init bash)"
        source "$1"
        z demo
        pwd
    ' _ "$plugin"
)
is "survives a new shell" "$repo" "$out"

# a `zo` in another shell must be visible here without re-sourcing
out=$(zo other_name "$site/other/deep")
at_home
z other_name
is "sees a write from another shell" "$site/other/deep" "$PWD"
zo_noop -d other_name

# hand-edited file, no zo involved
printf 'handedit\t%s\n' "$site/other" >>"$_ZO_OVERRIDES_FILE"
sleep 1
at_home
z handedit
is "sees a hand edit to the file" "$site/other" "$PWD"

printf '\n== data file format ==\n'

cp "$_ZO_OVERRIDES_FILE" "$sandbox/overrides.bak"
printf 'no-tab-here\n' >>"$_ZO_OVERRIDES_FILE"
printf '# a comment\t/nonexistent\n' >>"$_ZO_OVERRIDES_FILE"
_zo_load_overrides
is "malformed lines ignored" "$repo" "${_ZO_OVERRIDES[demo]-}"
[[ -z ${_ZO_OVERRIDES[comment]-} ]] && ok "comment lines ignored" || no "comment lines ignored"

printf 'dotted name\t%s\n' "$site/other" >>"$_ZO_OVERRIDES_FILE"
_zo_load_overrides
is "names with spaces load" "$site/other" "${_ZO_OVERRIDES[spaced name]-}"

zo_noop -d handedit
zo_noop -d "spaced name"
cp "$sandbox/overrides.bak" "$_ZO_OVERRIDES_FILE"
zo_noop -d handedit
zo_noop -d "spaced name"

printf '\n== completion: zo ==\n'

comp() {
    COMP_WORDS=("$@")
    COMP_CWORD=$(($# - 1))
    COMPREPLY=()
    _zo_complete
    printf '%s' "${COMPREPLY[*]-}"
}

is "zo<TAB> completes names" "demo" "$(comp zo '')"
is "zo dem<TAB> filters names" "demo" "$(comp zo dem)"
is "zo nope<TAB> offers nothing" "" "$(comp zo nope)"
is "zo -d <TAB> completes names" "demo" "$(comp zo -d '')"
is "zo -d dem<TAB> filters names" "demo" "$(comp zo -d dem)"
is "zo -<TAB> lists flags" "-d -h -l" "$(comp zo -)"
is "zo xxx -<TAB> offers nothing" "" "$(comp zo xxx -)"
is "zo <name> <TAB> completes dirs" "$site/other/deep" "$(comp zo demo "$site/other/")"
is "zo <name> $site/as<TAB>" "$site/astro" "$(comp zo demo "$site/as")"
is "zo <name> nonexistent<TAB>" "" "$(comp zo demo /nonexistentzzz)"
is "zo a b c<TAB> offers nothing" "" "$(comp zo a b c)"

printf '\n== completion: z ==\n'

zcomp() {
    COMP_WORDS=("$@")
    COMP_CWORD=$(($# - 1))
    COMPREPLY=()
    _zo_z_complete
    printf '%s' "${COMPREPLY[*]-}"
}

is "z <override> <TAB> lists children" "docs/ src/" "$(zcomp z demo '')"
is "z <override> s<TAB> filters children" "src/" "$(zcomp z demo s)"
is "z <override> src/<TAB> walks deeper" "src/components/" "$(zcomp z demo 'src/')"
is "z <override> nonexistent<TAB>" "" "$(zcomp z demo nonexistentzzz)"
is "z <override> ../<TAB> is blocked" "" "$(zcomp z demo ../)"
is "z <override> x/../<TAB> is blocked" "" "$(zcomp z demo x/../)"
is "z <query> <path><TAB> completes dirs" "$site/other" "$(zcomp z other "$site/oth")"

printf '\n== sourced too early ==\n'

early=$(
    bash -c 'source "$1" 2>/dev/null; declare -F z >/dev/null && echo wrapped || echo untouched' \
        _ "$plugin"
)
is "z is left alone without zoxide" "untouched" "$early"

printf '\n%s passed, %s failed\n' "$pass_count" "$fail_count"
[[ $fail_count -eq 0 ]]
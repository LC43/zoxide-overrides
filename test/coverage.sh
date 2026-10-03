#!/usr/bin/env bash
# Approximate line coverage for the shell sources, via bash xtrace.
#
#   ./test/coverage.sh
#
# Not gcov-grade. It reports which *lines* of each file executed at least once
# and calls everything else unexecuted. Excluded from the denominator, because
# xtrace never reports them: comments, blank lines, function definitions,
# case labels, structural closers, and continuation lines of multi-line commands
# (xtrace attributes those to the first physical line).
#
# Two details matter for accuracy:
#   * the trace goes to fd 9, not stderr, so lines run inside `$(...)` or under
#     `2>/dev/null` are still counted
#   * SHELLOPTS is exported so subprocesses inherit -x; otherwise every line the
#     suites run in a child shell would read as unexecuted
#
# Requires bash 4.4+ for ${BASH_SOURCE} in PS4.

set -uo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
targets=("$repo_dir/zoxide-overrides.sh" "$repo_dir/install.sh")
suites=(test/run-tests.sh test/install-tests.sh)

tmp=$(mktemp -d)
main_pid=$BASHPID
trap '[[ $BASHPID == $main_pid ]] && rm -rf "$tmp"' EXIT

cat >"$tmp/runner.sh" <<'RUNNER'
# fd 9 must be open before BASH_XTRACEFD names it, or bash rejects the value and
# silently falls back to stderr (where the suites redirect it away)
exec 9>>"$TRACE_FILE"
export BASH_XTRACEFD=9
export PS4='+${BASH_SOURCE[0]##*/}:${LINENO}: '
set -x
export SHELLOPTS
bash -x "$1"
RUNNER

for suite in "${suites[@]}"; do
    TRACE_FILE=$tmp/trace bash "$tmp/runner.sh" "$repo_dir/$suite" >/dev/null 2>&1
done

if [[ ! -s $tmp/trace ]]; then
    printf 'no trace captured — does this bash expand PS4? (%s)\n' \
        "${BASH_VERSION:-?}" >&2
    exit 1
fi

# Lines that can never appear in an xtrace, so counting them would understate
# coverage forever.
cat >"$tmp/statements.awk" <<'AWK'
BEGIN {
    SQ = sprintf("%c", 39)
    DQ = sprintf("%c", 34)
    # a case label: -l, --list, -d | --delete, 1), *, or a quoted label
    labelre = "^[[:space:]]*[-*0-9" SQ DQ "]"
    # a closing token, optionally followed by a redirect, plus a lone brace
    closere = "^[[:space:]]*(esac|done|fi|else|then|;;|\\)|\\})([[:space:]]|$)|^[[:space:]]*\\{[[:space:]]*$"
}

# drop double-quoted spans so single-quote counting ignores them
function strip_dq(s,   r, i, c, q) {
    r = ""
    q = ""
    for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (q != "") {
            if (c == q) q = ""
            continue
        }
        if (c == DQ) {
            q = c
            continue
        }
        r = r c
    }
    return r
}

# heredoc bodies are data, not statements
index($0, "<<") {
    d = $0
    sub(/^.*<<[-]?/, "", d)
    sub(/^[^A-Za-z0-9_]+/, "", d)
    sub(/[^A-Za-z0-9_].*$/, "", d)
    delim = d
    inhd = 1
    # `x=$(cat <<EOF ... EOF)` is traced at the terminator, not the opener
    if ($0 !~ /\$/) print NR > out
    next
}
inhd {
    line = $0
    sub(/^[[:space:]]+/, "", line)
    if (line == delim) inhd = 0
    next
}

/^[[:space:]]*$/  { next }
/^[[:space:]]*#/ { next }

# function definitions are declarations, not statements: xtrace reports the
# call site, never the definition
/^[[:space:]]*function[[:space:]]+[A-Za-z_][A-Za-z0-9_]*/ { next }
/^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\([[:space:]]*\)/ { next }

/^[[:space:]]*case[[:space:]].*[[:space:]]in[[:space:]]*$/ { next }
$0 ~ labelre  { next }
$0 ~ closere { next }
/\\[[:space:]]*$/ { next }

# a multi-line single-quoted string (an inline awk program, say): xtrace reports
# only the line where the command starts
{
    t = strip_dq($0)
    if (inq == 1) {
        if (gsub(SQ, "", t) % 2 == 1) inq = 0
        next
    }
    if (gsub(SQ, "", t) % 2 == 1) {
        inq = 1
        print NR > out
        next
    }
}

{ print NR > out }
AWK

report() {
    local target=$1 base statements covered total covered_total pct missed

    base=$(basename "$target")
    statements=$tmp/$base.statements
    covered=$tmp/$base.covered

    # lexical sort (not -n) so comm can compare the two files
    sed -n "s/^[+]*${base//./\\.}:\\([0-9]\\+\\):.*/\\1/p" "$tmp/trace" |
        sort -u >"$covered"

    awk -v out="$statements.raw" -f "$tmp/statements.awk" "$target"
    sort -u -o "$statements" "$statements.raw"

    total=$(wc -l <"$statements")
    covered_total=$(comm -12 "$statements" "$covered" | wc -l)
    pct=$(awk -v c="$covered_total" -v t="$total" \
        'BEGIN { printf "%.1f", (t ? c * 100 / t : 0) }')

    printf '\n%s\n' "$base"
    printf '  statements %5s\n' "$total"
    printf '  executed   %5s\n' "$covered_total"
    printf '  coverage   %5s%%\n' "$pct"

    missed=$(comm -23 "$statements" "$covered")
    if [[ -n $missed ]]; then
        printf '\n  unexecuted lines:\n'
        while read -r n; do
            printf '    %4s  %s\n' "$n" \
                "$(sed -n "${n}p" "$target" | sed 's/^[[:space:]]*//')"
        done <<<"$(sort -n <<<"$missed")"
    fi

    REPORT_TOTAL=$((REPORT_TOTAL + total))
    REPORT_HIT=$((REPORT_HIT + covered_total))
}

REPORT_TOTAL=0
REPORT_HIT=0
for target in "${targets[@]}"; do
    [[ -f $target ]] || continue
    report "$target"
done

pct=$(awk -v c="$REPORT_HIT" -v t="$REPORT_TOTAL" \
    'BEGIN { printf "%.1f", (t ? c * 100 / t : 0) }')
printf '\nall files\n'
printf '  statements %5s\n' "$REPORT_TOTAL"
printf '  executed   %5s\n' "$REPORT_HIT"
printf '  coverage   %5s%%\n' "$pct"
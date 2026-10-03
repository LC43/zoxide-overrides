#!/usr/bin/env bash
# Run every test suite.

set -uo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
status=0

for suite in test/run-tests.sh test/install-tests.sh; do
    printf '\n=== %s ===\n' "$suite"
    bash "$repo_dir/$suite" || status=1
done

printf '\n'
if [[ $status -eq 0 ]]; then
    printf 'all suites passed\n'
else
    printf 'FAILURES\n'
fi
exit $status
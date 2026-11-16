# zoxide-overrides

Pin `z <name>` to a directory so frecency can never send you somewhere else.

zoxide only matches a query against the **last component** of a path, so a
project like `/srv/www/goodomens.studio/astro/repo` is unreachable from
`z good` — only `/srv/www/goodomens.studio` can match. Overrides solve that
by short-circuiting the query entirely:

```sh
zo good /srv/www/goodomens.studio/astro/repo
z good      # -> /srv/www/goodomens.studio/astro/repo, every time
```

Anything without an override behaves exactly like stock zoxide.

## Install

```sh
git clone <this repo> ~/.zoxide-overrides
~/.zoxide-overrides/install.sh
source ~/.bashrc
```

The installer appends a marked block to `~/.bashrc` (or `~/.zshrc`). The zoxide
init line has to come **first** in that file:

```sh
eval "$(zoxide init bash)"                                       # first
[[ -r ~/.zoxide-overrides/zoxide-overrides.sh ]] && source ~/.zoxide-overrides/zoxide-overrides.sh
```

Installer options:

```sh
./install.sh --shell zsh          # use ~/.zshrc
./install.sh --rc ./dotfiles.bash  # write to some other rc file
./install.sh --uninstall           # remove the block (keeps your overrides)
```

Running it twice is a no-op. Uninstalling does not delete your overrides file.

## Usage

```sh
zo <name> <path>   # create or update
zo <name>          # pick <path> from a list, then edit the command line
zo -d <name>       # delete
zo -l              # list
zo -h              # help
```

Names are single words, matched exactly:

```sh
zo good /srv/www/goodomens.studio/astro/repo

z good        # the repo — the override wins
z goo         # zoxide: /srv/www/goodomens.studio (no override named "goo")
z repo        # zoxide: whichever repo ranks highest
```

### Picking a path

`zo <name>` with no path opens a picker instead of demanding one — an inline
drawer at the bottom of the screen, the same window `zi` opens, not a
full-screen page. It offers the pinned targets whose name starts with
`<name>`, then zoxide's own matches for the same word (`repo` and `epo` both
find `.../astro/repo`), with duplicates dropped.

What you pick is handed back as a complete command line, ready to edit:

```console
$ zo rep
zo rep /srv/www/goodomens.studio/astro/repo
```

Change the path as much as you like —
`zo rep /srv/www/goodomens.studio/astro/repo/src` — and press Enter to pin it.
Esc or Ctrl-C cancels and leaves the override untouched.

The picker needs `fzf` on your `PATH`; without it the candidates are printed to
stderr instead. When stdin is not a terminal there is nothing to edit, so the
completed line runs as-is — unless stdin supplies a replacement line, which is
how the test suite drives the editable prompt.

### Subpaths

An override name also accepts a relative subpath, so you can tab into the tree without repeating the whole path:

```sh
z good              # /srv/www/goodomens.studio/astro/repo
z good src          # /srv/www/goodomens.studio/astro/repo/src
z good /src         # same
```

If the subpath is not a directory inside the target, the whole thing falls
through to zoxide as a normal query — `z good nosuchdir` behaves as if `good`
had no override at all.

`..` is refused, so `z good ..` will not escape the target.

### Completion

`z` and `zi` get the override, and tab completion is filled in where zoxide
gives up:

| you type | you get |
| --- | --- |
| `z good<TAB>` | the target's children |
| `z good src/<TAB>` | children of `src/` |
| `z other /srv/<TAB>` | directories (zoxide does nothing here) |
| `zo <TAB>` | existing override names |
| `zo xxx /work<TAB>` | directories matching `/work` |
| `zo -d <TAB>` | existing override names |

## Storage

Overrides live in a plain tab-separated file, by default
`~/.config/zoxide/overrides`:

```
# name<TAB>path — managed by `zo`; edit with `zo <name> <path>`
good	/srv/www/goodomens.studio/astro/repo
```

It is re-read on every `z`, so you can edit it by hand, or run `zo` from another
terminal or a script, and the change is picked up immediately. Set
`_ZO_OVERRIDES_FILE` before sourcing to relocate it — the test suite does
exactly that.

## Tests

```sh
./test/all.sh
```

Runs in a throwaway `HOME`. `test/run-tests.sh` (83 assertions) covers the `zo`
command, the `zo <name>` picker (stubbed fzf, plus a pty for the interactive
line), `z`/`zi` routing, subpaths, persistence, cross-process reloads,
malformed input, both completion functions, and the zsh path (skipped when zsh
is absent). `test/install-tests.sh` (26 assertions) covers the installer:
marker block, idempotence, uninstall, `--help`, `ZDOTDIR`, and that the block it
writes actually loads. Requires `zoxide`; `fzf` is stubbed wherever a picker
would otherwise open, and the pty test is skipped when `script(1)` cannot
allocate one.

Individual suites: `./test/run-tests.sh`, `./test/install-tests.sh`.

### Coverage

```sh
./test/coverage.sh
```

```
zoxide-overrides.sh  138/141 statements  97.9%
install.sh            33/33  statements  100.0%
```

Line coverage measured by re-running both suites under `set -x` with a
file-annotated `PS4` and the trace on fd 9. It is a homegrown approximation, not
gcov: comments, function definitions, case labels and structural closers are
excluded from the denominator because xtrace never reports them, and a line
only ever executed inside a construct xtrace attributes elsewhere can read as
unexecuted. Read it as "which lines are provably reached", not as a guarantee.

The three uncovered lines are all zsh-only: `typeset -gA _ZO_OVERRIDES=()`, the
array declaration, and the `vared` arm of the editable prompt. Neither is
reachable under bash, so covering them needs a zsh in CI.

## Notes and limits

- Frecency still updates: zoxide's own `PROMPT_COMMAND` hook records whatever
  directory you land in. The override only changes the *query*.
- Overrides shadow zoxide entirely for that name. There is no "override but
  prefer something else" mode.
- Completion is bash-only. The `zo` command and `z`/`zi` wrappers work in zsh
  too, but `compdef` is not wired up.
- The picker (`zo <name>`) needs `fzf` and a terminal; the editable line is
  readline under bash and `vared` under zsh.
- The plugin does not wrap `cd`; only `z` and `zi` are intercepted.

## License

MIT
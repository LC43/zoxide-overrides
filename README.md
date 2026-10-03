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

### Subpaths

An override name also accepts a relative subpath, so you can tab into the tree
without repeating the whole path:

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

Runs in a throwaway `HOME`. `test/run-tests.sh` (53 assertions) covers the `zo`
command, `z`/`zi` routing, subpaths, persistence, cross-process reloads,
malformed input, and both completion functions. `test/install-tests.sh`
(20 assertions) covers the installer: marker block, idempotence, uninstall,
`ZDOTDIR`, and that the block it writes actually loads. Requires `zoxide`;
`fzf` only for the interactive `zi` assertion.

Individual suites: `./test/run-tests.sh`, `./test/install-tests.sh`.

## Notes and limits

- Frecency still updates: zoxide's own `PROMPT_COMMAND` hook records whatever
  directory you land in. The override only changes the *query*.
- Overrides shadow zoxide entirely for that name. There is no "override but
  prefer something else" mode.
- Completion is bash-only. The `zo` command and `z`/`zi` wrappers work in zsh
  too, but `compdef` is not wired up.
- The plugin does not wrap `cd`; only `z` and `zi` are intercepted.

## License

MIT
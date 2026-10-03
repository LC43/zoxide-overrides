#!/usr/bin/env bash
# zoxide-overrides — pin `z <name>` to a directory, ignoring zoxide's ranking.
#
# Source this AFTER `eval "$(zoxide init <shell>)"`:
#
#     zo good /srv/www/goodomens.studio/astro/repo   # create/update
#     zo -d good                                          # delete
#     zo -l                                               # list
#
# `z good` and `zi good` then go straight to the pinned directory. Anything
# without an override falls through to stock zoxide, untouched.
#
# Overrides live in a plain tab-separated file (default
# ~/.config/zoxide/overrides) that you can read, diff and hand-edit.

# Where the name -> path map is stored. Override before sourcing to relocate.
: "${_ZO_OVERRIDES_FILE:=$HOME/.config/zoxide/overrides}"

if [[ -n ${ZSH_VERSION:-} ]]; then
    typeset -gA _ZO_OVERRIDES=()
else
    declare -gA _ZO_OVERRIDES=()
fi

_zo_load_overrides() {
    _ZO_OVERRIDES=()
    [[ -r $_ZO_OVERRIDES_FILE ]] || return 0
    local name path
    while IFS=$'\t' read -r name path || [[ -n $name ]]; do
        [[ -z ${name//[[:space:]]/} || $name == \#* ]] && continue
        [[ -n $path ]] && _ZO_OVERRIDES["$name"]="$path"
    done <"$_ZO_OVERRIDES_FILE"
}

_zo_save_overrides() {
    local dir tmp key
    dir=${_ZO_OVERRIDES_FILE%/*}
    [[ $dir == "$_ZO_OVERRIDES_FILE" ]] && dir=.
    mkdir -p "$dir"
    tmp=$_ZO_OVERRIDES_FILE.$$
    {
        printf '# name<TAB>path — managed by `zo`; edit with `zo <name> <path>`\n'
        for key in "${!_ZO_OVERRIDES[@]}"; do
            printf '%s\t%s\n' "$key" "${_ZO_OVERRIDES[$key]}"
        done
    } >"$tmp"
    mv -f "$tmp" "$_ZO_OVERRIDES_FILE"
}

# Echo the pinned path for $1.
#   0 -> printed a target
#   1 -> no such override
#   2 -> override exists but its directory is gone (caller falls back to zoxide)
_zo_target() {
    local name=${1-} path
    [[ -n $name && -v _ZO_OVERRIDES[$name] ]] || return 1
    path=${_ZO_OVERRIDES[$name]}
    if [[ ! -d $path ]]; then
        printf 'zo: override %s -> %s no longer exists, falling back to zoxide\n' \
            "$name" "$path" >&2
        return 2
    fi
    printf '%s\n' "$path"
}

_zo_usage() {
    cat <<'EOF'
usage:
  zo <name> <path>   make `z <name>` jump to <path>, ignoring zoxide ranking
  zo -d <name>       remove an override
  zo -l              list overrides
  zo -h              this help
EOF
}

_zo_print_overrides() {
    if [[ ${#_ZO_OVERRIDES[@]} -eq 0 ]]; then
        printf 'no overrides (file: %s)\n' "$_ZO_OVERRIDES_FILE"
        return
    fi
    local key
    for key in "${!_ZO_OVERRIDES[@]}"; do
        if [[ -d ${_ZO_OVERRIDES[$key]} ]]; then
            printf '  %-24s %s\n' "$key" "${_ZO_OVERRIDES[$key]}"
        else
            printf '  %-24s %s   [missing]\n' "$key" "${_ZO_OVERRIDES[$key]}"
        fi
    done | sort
}

_zo_complete_names() {
    local cur=$1 key
    COMPREPLY=()
    for key in "${!_ZO_OVERRIDES[@]}"; do
        [[ $key == "$cur"* ]] && COMPREPLY+=("$key")
    done
}

# `zo` takes <name> <path>, so completion depends on the argument position:
#   zo <TAB>          -> existing override names
#   zo xxx /work<TAB> -> directories matching /work
#   zo -d <TAB>       -> existing override names (not flags)
function _zo_complete() {
    local cur=${COMP_WORDS[COMP_CWORD]-}
    local prev=${COMP_WORDS[COMP_CWORD - 1]-}
    _zo_load_overrides

    if [[ ${COMP_CWORD:-0} -eq 1 && $cur == -* ]]; then
        COMPREPLY=(-d -h -l)
        return 0
    fi

    case ${COMP_CWORD:-0} in
        1)
            _zo_complete_names "$cur"
            ;;
        2)
            if [[ $prev == -d || $prev == --delete ]]; then
                _zo_complete_names "$cur"
            else
                COMPREPLY=($(compgen -A directory -- "$cur"))
            fi
            ;;
        *)
            COMPREPLY=()
            ;;
    esac
}

function zo() {
    _zo_load_overrides
    case ${1-} in
        -h | --help)
            _zo_usage
            ;;
        -l | --list)
            _zo_print_overrides
            ;;
        -d | --delete)
            [[ $# -eq 2 ]] || {
                _zo_usage >&2
                return 2
            }
            if [[ ! -v _ZO_OVERRIDES[$2] ]]; then
                printf 'zo: no such override: %s\n' "$2" >&2
                return 1
            fi
            unset '_ZO_OVERRIDES[$2]'
            _zo_save_overrides
            printf 'removed override: %s\n' "$2"
            ;;
        -*)
            _zo_usage >&2
            return 2
            ;;
        *)
            [[ $# -eq 2 ]] || {
                _zo_usage >&2
                return 2
            }
            local dir
            dir=$(builtin cd -- "$2" 2>/dev/null && __zoxide_pwd) || {
                printf 'zo: not a directory: %s\n' "$2" >&2
                return 1
            }
            _ZO_OVERRIDES[$1]=$dir
            _zo_save_overrides
            printf '%s -> %s\n' "$1" "$dir"
            ;;
    esac
}

# Wrap zoxide's commands so an override wins over its ranking. Frecency still
# updates, because zoxide's own PROMPT_COMMAND hook records whatever directory
# you end up in — the override only short-circuits the query.
if ! declare -F __zoxide_z >/dev/null 2>&1; then
    printf 'zo: source zoxide-overrides.sh AFTER `eval "$(zoxide init <shell>)"`\n' >&2
else
    # `z <override> [subpath]` -> cd to $target[/subpath]. If the subpath is not
    # a directory inside the target, fall through to a normal zoxide query.
    _zo_z_resolve() {
        local target rest
        # Re-read every time: the file is tiny, and this is the only way to see
        # a `zo` run in a subshell/script, another terminal, or a hand edit.
        _zo_load_overrides
        [[ $# -ge 1 && -v _ZO_OVERRIDES[$1] ]] || return 1
        target=$(_zo_target "$1") || return 1
        if [[ $# -eq 1 ]]; then
            __zoxide_cd "$target"
            return
        fi
        rest=${*:2}
        rest=${rest#/}
        case $rest in
            '' | . | ..) ;;
            *)
                [[ -d $target/$rest ]] && __zoxide_cd "$target/$rest"
                ;;
        esac
    }

    function z() {
        _zo_z_resolve "$@" && return 0
        __zoxide_z "$@"
    }

    function zi() {
        _zo_z_resolve "$@" && return 0
        __zoxide_zi "$@"
    }
fi

# ---------------------------------------------------------------------------
# Completion (bash). Sourced in zsh too, but registered only for bash.
# ---------------------------------------------------------------------------
if [[ -n ${BASH_VERSION:-} ]]; then
    # `zo` completion
    complete -F _zo_complete -o filenames -- zo

    # `z` completion. Stock zoxide handles `z <word><TAB>` (directory
    # completion) and `z <words><SPACE><TAB>` (fzf picker), but a partial path
    # in a later argument gets nothing. Add that, plus tree walking inside an
    # override so `z good <TAB>` lists the target's children.
    function _zo_z_complete() {
        local cur=${COMP_WORDS[COMP_CWORD]-}
        local first=${COMP_WORDS[1]-}
        _zo_load_overrides

        # `z <override> <subpath><TAB>`
        if [[ ${COMP_CWORD:-0} -ge 2 && -v _ZO_OVERRIDES[$first] ]]; then
            # stay inside the target: no escaping via ../
            [[ $cur == *..* ]] && return 0
            local target=${_ZO_OVERRIDES[$first]} entry
            local -a matches=()
            for entry in "$target"/"$cur"*; do
                [[ -d $entry ]] && matches+=("${entry#"$target"/}/")
            done
            COMPREPLY=(${matches[@]+"${matches[@]}"})
            return 0
        fi

        # `z <query> <partial/path><TAB>`
        if [[ ${COMP_CWORD:-0} -ge 2 && $cur == */* ]]; then
            COMPREPLY=($(compgen -A directory -- "$cur"))
            return 0
        fi

        # everything else: zoxide's own behaviour
        if declare -F __zoxide_z_complete >/dev/null 2>&1; then
            __zoxide_z_complete
        else
            COMPREPLY=($(compgen -A directory -- "$cur"))
        fi
    }

    if declare -F __zoxide_z_complete >/dev/null 2>&1 ||
        [[ -n ${TERM:-} && ${TERM} != dumb ]]; then
        complete -F _zo_z_complete -o filenames -- z
    fi
fi

_zo_load_overrides
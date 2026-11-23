if [[ $# != 1 || $1 != build || ! -f flake.nix || ! -f nix/dank-todoman-dev-build.sh ]]; then
    exec "$nativeNix" "$@"
fi

set -eo pipefail

refuse_result() {
    printf 'dankTodoman: refusing to replace %s\n' "$1" >&2
    exit 1
}

is_store_link() {
    local target LC_ALL=C
    IFS= read -r -d '' target < <("$coreutils/readlink" -z -- "$1") || return 1
    [[ $target == "$storeDir/"* && ${target#"$storeDir/"} =~ ^[0123456789abcdfghijklmnpqrsvwxyz]{32}-[a-zA-Z0-9+._?=-]+$ ]]
}

if [[ -L result ]]; then
    is_store_link result || refuse_result 'result (not a Nix store symlink)'
elif [[ -e result && ( ! -d result || ! -r result || ! -x result ) ]]; then
    refuse_result 'result (not a readable ordinary directory)'
fi

output=$("$nativeNix" build --no-link --print-out-paths --log-format raw --quiet --option warn-dirty false)
if [[ $output != "$storeDir/"* || $output == *$'\n'* || ! -d $output || -L $output ]]; then
    printf 'dankTodoman: expected one build output directory\n' >&2
    exit 1
fi

manifest=.dank-todoman-manifest
export LC_ALL=C
unset GLOBIGNORE GLOBSORT
shopt -s nullglob dotglob

write_manifest() {
    local entry name mode digest
    printf 'dank-todoman-result-v1\0' || return 1
    for entry; do
        name=${entry##*/}
        [[ $name != "$manifest" ]] || continue
        [[ ! -L $entry && -f $entry ]] || return 1
        mode=$("$coreutils/stat" -c '%a' -- "$entry") || return 1
        digest=$("$coreutils/sha256sum" < "$entry") || return 1
        printf '%s\0%s\0%s\0' "$name" "$mode" "${digest%% *}" || return 1
    done
}

validate_previous() {
    local saved actual
    if [[ -L $previous ]]; then
        is_store_link "$previous"
        return
    fi
    [[ -d $previous && -r $previous && -x $previous ]] || return 1
    previous_entries=("$previous"/*)
    ((${#previous_entries[@]})) || return 0
    [[ -w $previous && ! -L $previous/$manifest && -f $previous/$manifest ]] || return 1
    saved=$("$coreutils/sha256sum" < "$previous/$manifest") || return 1
    actual=$(write_manifest "${previous_entries[@]}" | "$coreutils/sha256sum") || return 1
    [[ $saved == "$actual" ]]
}

move_without_replacing() {
    "$coreutils/mv" -T --no-copy --update=none-fail -- "$1" "$2"
}

restore_previous() {
    if [[ -d $previous && ! -L $previous ]]; then
        move_without_replacing "$previous" result
    else
        "$coreutils/ln" -PT -- "$previous" result && "$coreutils/rm" -- "$previous"
    fi
}

cleanup() {
    local status=$?
    if [[ -L $previous || -e $previous ]]; then
        if ((published)) || ! restore_previous; then
            printf 'dankTodoman: previous result preserved at %s\n' "$previous" >&2
            ((status != 0)) || status=1
        fi
    fi
    "$coreutils/rm" -rf --one-file-system -- "$payload" || :
    "$coreutils/rmdir" -- "$staging" 2>/dev/null || :
    exit "$status"
}

staging=$("$coreutils/mktemp" -d -- "$PWD/result.tmp.XXXXXX")
payload=$staging/payload
previous=$staging/previous
previous_entries=()
published=0
trap cleanup EXIT

"$coreutils/cp" -R --preserve=mode -- "$output" "$payload"
"$coreutils/chmod" -R u+w -- "$payload"
if [[ -L $payload/$manifest || -e $payload/$manifest ]] ||
    ! write_manifest "$payload"/* > "$payload/$manifest"; then
    printf 'dankTodoman: expected a flat build output without a reserved manifest entry\n' >&2
    exit 1
fi

if [[ -L result || -e result ]]; then
    move_without_replacing result "$previous"
    validate_previous || refuse_result 'result (not an unchanged generated directory or Nix store symlink)'
fi

move_without_replacing "$payload" result
published=1

if [[ -L $previous ]]; then
    "$coreutils/rm" -- "$previous"
elif [[ -d $previous ]]; then
    if ((${#previous_entries[@]})); then
        "$coreutils/rm" -- "${previous_entries[@]}"
    fi
    "$coreutils/rmdir" -- "$previous"
fi

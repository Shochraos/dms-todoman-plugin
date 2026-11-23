if [[ $# != 1 || $1 != build || ! -f flake.nix || ! -f nix/dank-todoman-dev-build.sh ]]; then
    exec "$nativeNix" "$@"
fi

set -e

refuse_result() {
    printf 'dankTodoman: refusing to replace %s\n' "$1" >&2
    exit 1
}

check_result() {
    if [[ -L result ]]; then
        target=$("$coreutils/readlink" -- result)
        storeEntry=${target#"$storeDir/"}
        if [[ $target != "$storeDir/"* || ! $storeEntry =~ ^[0123456789abcdfghijklmnpqrsvwxyz]{32}-[^/]+$ ]]; then
            refuse_result 'result (not a Nix store symlink)'
        fi
    elif [[ -e result && ( ! -d result || ! -r result || ! -x result ) ]]; then
        refuse_result 'result (not a readable ordinary directory)'
    fi
}

check_result
output=$("$nativeNix" build --no-link --print-out-paths --log-format raw --quiet --option warn-dirty false)
if [[ $output != "$storeDir/"* || $output == *$'\n'* || ! -d $output ]]; then
    printf 'dankTodoman: expected one build output directory\n' >&2
    exit 1
fi

staging=$("$coreutils/mktemp" -d ./result.tmp.XXXXXX)
trap '"$coreutils/rm" -rf --one-file-system -- "$staging"' EXIT
"$coreutils/cp" -R --preserve=mode -- "$output" "$staging/payload"
"$coreutils/chmod" -R u+w -- "$staging/payload"

check_result
if [[ ! -L result && -d result ]]; then
    shopt -s nullglob dotglob
    for entry in result/*; do
        if [[ -L $entry || ! -f $entry || ! -f "$output/${entry##*/}" ]]; then
            refuse_result "unexpected output entry $entry"
        fi
    done
fi
if [[ -L result || -d result ]]; then
    "$coreutils/mv" -T --no-copy -- result "$staging/previous"
fi
if "$coreutils/mv" -T --no-copy -- "$staging/payload" result; then
    exit 0
else
    status=$?
    if [[ -L $staging/previous || -d $staging/previous ]]; then
        "$coreutils/mv" -T --no-copy -- "$staging/previous" result || trap - EXIT
    fi
    exit "$status"
fi

#!/bin/sh
set -f

backend="${1:-}"

is_python_name() {
    case "${1##*/}" in
        python|python3|python3.*) return 0 ;;
        *) return 1 ;;
    esac
}

resolve_path() {
    if command -v readlink >/dev/null 2>&1; then
        resolved=$(readlink -f "$1" 2>/dev/null) && [ -n "$resolved" ] && { printf '%s' "$resolved"; return 0; }
    fi
    if command -v realpath >/dev/null 2>&1; then
        resolved=$(realpath "$1" 2>/dev/null) && [ -n "$resolved" ] && { printf '%s' "$resolved"; return 0; }
    fi
    printf '%s' "$1"
}

shebang_python() {
    [ -r "$1" ] || return 1
    IFS= read -r first_line < "$1" 2>/dev/null || return 1
    first_line="${first_line%"$(printf '\r')"}"
    case "$first_line" in
        '#!'*) rest="${first_line#\#!}" ;;
        *) return 1 ;;
    esac
    while :; do
        case "$rest" in
            ' '*|'	'*) rest="${rest#?}" ;;
            *) break ;;
        esac
    done
    [ -n "$rest" ] || return 1
    if [ -x "$rest" ] && is_python_name "$rest"; then
        printf '%s' "$rest"
        return 0
    fi
    set -- $rest
    interp="${1:-}"
    [ -n "$interp" ] || return 1
    if [ "${interp##*/}" = "env" ]; then
        shift
        while [ $# -gt 0 ]; do
            case "$1" in
                -*|*=*) shift ;;
                *) break ;;
            esac
        done
        cmd="${1:-}"
        [ -n "$cmd" ] && is_python_name "$cmd" || return 1
        resolved_cmd=$(command -v "$cmd" 2>/dev/null || true)
        [ -n "$resolved_cmd" ] && [ -x "$resolved_cmd" ] || return 1
        printf '%s' "$resolved_cmd"
        return 0
    fi
    if [ -x "$interp" ] && is_python_name "$interp"; then
        printf '%s' "$interp"
        return 0
    fi
    return 1
}

find_wrapped_in_script() {
    [ -r "$1" ] || return 1
    IFS= read -r first_line < "$1" 2>/dev/null || return 1
    case "$first_line" in
        '#!'*) ;;
        *) return 1 ;;
    esac
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            *exec*'.todo-wrapped'*)
                candidate="${line%%.todo-wrapped*}.todo-wrapped"
                case "$candidate" in
                    *\"/*) candidate="/${candidate##*\"/}" ;;
                    *\'/*) candidate="/${candidate##*\'/}" ;;
                    *' '/*) candidate="/${candidate##*' '/}" ;;
                esac
                if [ -r "$candidate" ]; then
                    printf '%s' "$candidate"
                    return 0
                fi
                ;;
        esac
    done < "$1"
    return 1
}

todo_bin=$(command -v todo 2>/dev/null || true)
if [ -n "$todo_bin" ]; then
    resolved_todo=$(resolve_path "$todo_bin")
    wrapped=""
    case "$resolved_todo" in
        */*) sibling="${resolved_todo%/*}/.todo-wrapped" ;;
        *) sibling=".todo-wrapped" ;;
    esac
    if [ -r "$sibling" ]; then
        wrapped="$sibling"
    else
        wrapped=$(find_wrapped_in_script "$resolved_todo" || true)
    fi
    if [ -n "$wrapped" ]; then
        python_bin=$(shebang_python "$wrapped" || true)
        if [ -n "$python_bin" ]; then
            TODOMAN_AUTO_PYTHON=1 TODOMAN_WRAPPED_SCRIPT="$wrapped" TODOMAN_WRAPPER_SCRIPT="$resolved_todo" exec "$python_bin" "$backend"
        fi
    fi
    python_bin=$(shebang_python "$resolved_todo" || true)
    if [ -n "$python_bin" ]; then
        unset TODOMAN_WRAPPED_SCRIPT
        TODOMAN_AUTO_PYTHON=1 TODOMAN_WRAPPER_SCRIPT="$resolved_todo" exec "$python_bin" "$backend"
    fi
fi

python_bin=$(command -v python3 2>/dev/null || true)
if [ -n "$python_bin" ]; then
    unset TODOMAN_WRAPPED_SCRIPT TODOMAN_WRAPPER_SCRIPT
    TODOMAN_AUTO_PYTHON=1 exec "$python_bin" "$backend"
fi

if [ -z "$todo_bin" ]; then
    printf '%s\n' '{"ok": false, "code": "dependency", "message": "Todoman executable '\''todo'\'' was not found and no Python 3 interpreter is available. Install Todoman or set the Python interpreter in plugin settings.", "mutated": false, "task": null}'
else
    printf '%s\n' '{"ok": false, "code": "dependency", "message": "No Python 3 interpreter was found. Set the Python interpreter in plugin settings.", "mutated": false, "task": null}'
fi
exit 0

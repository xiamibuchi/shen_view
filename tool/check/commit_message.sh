#!/bin/sh
set -eu

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

is_zero() {
    [ -n "$1" ] && [ -z "$(printf '%s' "$1" | tr -d '0')" ]
}

check_subject() {
    subject=$1
    bom=$(printf '\357\273\277')
    cr=$(printf '\r')
    subject=${subject#"$bom"}
    subject=${subject%"$cr"}
    if printf '%s\n' "$subject" | LC_ALL=C grep -Eq '^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([^()[:space:]]+\))?!?: [^[:space:]](.*[^[:space:]])?$'; then
        return 0
    fi
    printf '%s: invalid commit subject: %s\n' "$2" "$subject" >&2
    printf '%s\n' 'Expected: type(scope): description; scope is optional; ! is allowed before the colon.' >&2
    printf '%s\n' 'Types: feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert.' >&2
    return 1
}

resolve_commit() {
    git rev-parse --verify --end-of-options "$1^{commit}"
}

case "${1:-}" in
    --message-file)
        [ "$#" -eq 2 ] || fail 'Usage: commit_message.sh --message-file PATH'
        [ -f "$2" ] || fail "Message file not found: $2"
        merge_head=$(git rev-parse --git-path MERGE_HEAD)
        if [ -f "$merge_head" ]; then
            printf '%s\n' 'Merge commit: subject check skipped.'
            exit 0
        fi
        subject=
        IFS= read -r subject < "$2" || :
        check_subject "$subject" "$2"
        exit $?
        ;;
    --range)
        [ "$#" -eq 3 ] || fail 'Usage: commit_message.sh --range BASE HEAD'
        base=$2
        head=$3
        ;;
    --event)
        [ "$#" -eq 1 ] || fail 'Usage: commit_message.sh --event'
        case "${COMMIT_EVENT_NAME:-}" in
            pull_request)
                base=${COMMIT_PR_BASE:?Missing PR base}
                head=${COMMIT_PR_HEAD:?Missing PR head}
                ;;
            push)
                base=${COMMIT_BEFORE:?Missing push base}
                head=${COMMIT_AFTER:?Missing push head}
                if is_zero "$head"; then
                    printf '%s\n' 'Branch deleted: no new commits.'
                    exit 0
                fi
                ;;
            workflow_dispatch)
                head=$(resolve_commit HEAD)
                base=$(resolve_commit "$head^" 2>/dev/null) || base=0000000000000000000000000000000000000000
                ;;
            *) fail 'Unsupported commit-check event.' ;;
        esac
        for hash in "$base" "$head"; do
            case "$hash" in *[!0-9a-fA-F]*) fail 'Event refs must be commit hashes.' ;; esac
            case "${#hash}" in 40|64) ;; *) fail 'Event refs must be commit hashes.' ;; esac
        done
        if [ "${COMMIT_EVENT_NAME}" = push ] && is_zero "$base" && [ "${COMMIT_REF:-}" != "refs/heads/${COMMIT_DEFAULT_BRANCH:-main}" ]; then
            base=$(git merge-base "$head" "refs/remotes/origin/${COMMIT_DEFAULT_BRANCH:-main}")
        fi
        if ! is_zero "$base" && ! resolve_commit "$base" >/dev/null 2>&1; then
            git fetch --no-tags origin "$base"
        fi
        ;;
    *) fail 'Usage: commit_message.sh --message-file PATH | --range BASE HEAD | --event' ;;
esac

[ -n "$base" ] || fail 'Base ref must not be empty.'
head=$(resolve_commit "$head")
if is_zero "$base"; then
    range=$head
else
    base=$(resolve_commit "$base")
    range=$base..$head
fi
commits=$(git rev-list --reverse --no-merges "$range" --)
invalid=0
count=0
for commit in $commits; do
    message=$(git show -s --format=%B "$commit" --)
    subject=$(printf '%s\n' "$message" | sed -n '1p')
    if ! check_subject "$subject" "$commit"; then
        invalid=$((invalid + 1))
    fi
    count=$((count + 1))
done
[ "$invalid" -eq 0 ] || fail "FAIL: $invalid invalid commit subject(s)."
printf 'PASS: %s non-merge commit subject(s).\n' "$count"

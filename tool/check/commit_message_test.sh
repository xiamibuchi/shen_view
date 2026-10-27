#!/bin/sh
set -eu
root=$(CDPATH= cd "$(dirname "$0")/../.." && pwd -P)
mkdir -p "$root/artifacts"
work=$(mktemp -d "$root/artifacts/commit-tests.XXXXXX")
case "$work" in "$root"/artifacts/commit-tests.*) ;; *) exit 1 ;; esac
[ ! -L "$work" ] || exit 1
trap 'cd "$root"; rm -rf -- "$work"' 0
unicode=$(printf '\346\265\213')
repo="$work/repo space $unicode"
mkdir -p "$repo/.githooks" "$repo/tool/check"
cp "$root/.githooks/commit-msg" "$repo/.githooks/commit-msg"
cp "$root/tool/check/commit_message.sh" "$repo/tool/check/commit_message.sh"
chmod +x "$repo/.githooks/commit-msg"
git -C "$repo" init -q -b main
git -C "$repo" config user.name 'Commit Test'
git -C "$repo" config user.email 'commit-test@example.invalid'
git -C "$repo" config commit.gpgsign false
git -C "$repo" config core.hooksPath .githooks
cd "$repo"
checker="$repo/tool/check/commit_message.sh"
count=0

assert_check() {
    expected=$1
    shift
    if sh "$checker" "$@" > "$work/output" 2>&1; then actual=0; else actual=$?; fi
    if [ "$actual" -ne "$expected" ]; then
        cat "$work/output" >&2
        printf 'Expected exit %s, got %s: %s\n' "$expected" "$actual" "$*" >&2
        exit 1
    fi
    count=$((count + 1))
}

check_message() {
    expected=$1
    printf '%s' "$2" > "$work/message file"
    assert_check "$expected" --message-file "$work/message file"
}

for type in feat fix docs style refactor perf test build ci chore revert; do
    check_message 0 "$type: description"
done
check_message 0 'fix(viewer): a'
check_message 0 "fix(viewer): $unicode"
check_message 0 'feat!: remove old API'
check_message 0 'feat(api)!: remove old API'
check_message 0 'fix(native/decode): preserve pixels'
check_message 0 "fix($unicode): preserve pixels"
check_message 0 'docs: title

Body and BREAKING CHANGE footers are allowed.'
printf '\357\273\277fix: UTF-8 BOM\r\n\r\nbody\r\n' > "$work/message file"
assert_check 0 --message-file "$work/message file"
for message in '' 'init' 'update images' 'Feat: uppercase' 'feature: unknown' 'fix:missing space' 'fix:  extra space' 'fix:' 'fix: ' 'fix: trailing ' 'fix(): empty scope' 'fix(a b): scope with spaces' 'fix(a(b)): nested scope' 'fix(foo):' 'fixup! fix: change' 'squash! fix: change' 'Merge branch topic' 'Revert "change"'; do
    check_message 1 "$message"
done
check_message 1 "$(printf 'fix:\tno normal space')"
assert_check 1 --message-file "$work/missing file"
assert_check 1 --range

git commit --allow-empty -qm 'chore: initial fixture'
initial=$(git rev-parse HEAD)
if git commit --allow-empty -qm 'invalid hook message' > "$work/output" 2>&1; then
    printf '%s\n' 'Hook accepted an invalid commit.' >&2
    exit 1
fi
[ "$(git rev-parse HEAD)" = "$initial" ] || exit 1
count=$((count + 2))
git commit --allow-empty -qm "fix(core): $unicode"
good=$(git rev-parse HEAD)
assert_check 0 --range "$initial" "$good"
assert_check 0 --range "$good" "$good"
tree=$(git rev-parse 'HEAD^{tree}')
invalid=$(git commit-tree "$tree" -p "$good" -m 'invalid CI message')
assert_check 1 --range "$good" "$invalid"
invalid_merge=$(git commit-tree "$tree" -p "$good" -p "$invalid" -m 'Merge branch invalid')
assert_check 1 --range "$good" "$invalid_merge"
legacy=$(git commit-tree "$tree" -m init)
new=$(git commit-tree "$tree" -p "$legacy" -m 'test: new commit')
assert_check 0 --range "$legacy" "$new"
assert_check 1 --range 0000000000000000000000000000000000000000 "$new"

git checkout -qb topic
git commit --allow-empty -qm 'feat: topic'
git checkout -q main
git merge --no-ff -qm 'Merge branch topic' topic
merge=$(git rev-parse HEAD)
assert_check 0 --range "$good" "$merge"

export COMMIT_EVENT_NAME=push COMMIT_BEFORE="$good" COMMIT_AFTER="$merge"
export COMMIT_REF=refs/heads/main COMMIT_DEFAULT_BRANCH=main
assert_check 0 --event
COMMIT_AFTER=$invalid
export COMMIT_AFTER
assert_check 1 --event
COMMIT_AFTER=0000000000000000000000000000000000000000
export COMMIT_AFTER
assert_check 0 --event
COMMIT_BEFORE=0000000000000000000000000000000000000000
COMMIT_AFTER=$new
COMMIT_REF=refs/heads/new-topic
export COMMIT_BEFORE COMMIT_AFTER COMMIT_REF
git update-ref refs/remotes/origin/main "$legacy"
assert_check 0 --event
COMMIT_EVENT_NAME=pull_request
COMMIT_PR_BASE=$good
COMMIT_PR_HEAD=$invalid
export COMMIT_EVENT_NAME COMMIT_PR_BASE COMMIT_PR_HEAD
assert_check 1 --event
COMMIT_PR_HEAD=$merge
export COMMIT_PR_HEAD
assert_check 0 --event
COMMIT_PR_HEAD='--not-a-hash'
export COMMIT_PR_HEAD
assert_check 1 --event
COMMIT_EVENT_NAME=workflow_dispatch
export COMMIT_EVENT_NAME
assert_check 0 --event
printf 'PASS: %s commit validator and hook checks.\n' "$count"

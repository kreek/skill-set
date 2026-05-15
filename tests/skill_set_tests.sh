#!/usr/bin/env bash
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT_DIR/bin/skill-set"
TEST_COUNT=0

pass() {
  TEST_COUNT=$((TEST_COUNT + 1))
  printf 'ok %s - %s\n' "$TEST_COUNT" "$1"
}
fail() {
  printf 'not ok - %s\n%s\n' "$1" "$2" >&2
  exit 1
}
assert_eq() {
  name="$1" expected="$2" actual="$3"
  [ "$expected" = "$actual" ] || fail "$name" "expected: [$expected]\nactual:   [$actual]"
}
assert_file_absent() { [ ! -e "$1" ] && [ ! -L "$1" ] || fail "$2" "expected absent: $1"; }
assert_file_present() { [ -e "$1" ] || fail "$2" "expected present: $1"; }
assert_link_target() {
  target="$1" expected="$2" name="$3"
  [ -L "$target" ] || fail "$name" "expected symlink: $target"
  actual="$(readlink "$target")"
  [ "$actual" = "$expected" ] || fail "$name" "expected: [$expected]\nactual:   [$actual]"
}

make_tmp() { mktemp -d "${TMPDIR:-/tmp}/skill-set-test.XXXXXX"; }
setup_case() {
  TMP_ROOT="$(make_tmp)"
  export HOME="$TMP_ROOT/home"
  export SKILL_SETS="$TMP_ROOT/skill-set"
  export TARGET_DIR="$TMP_ROOT/target"
  export STATE_FILE="$TMP_ROOT/state"
  unset LOCK_DIR
  export PATH="$TMP_ROOT/bin:$PATH"
  mkdir -p "$HOME" "$SKILL_SETS" "$TARGET_DIR" "$TMP_ROOT/bin"
}
make_skill() {
  set_name="$1" skill="$2"
  mkdir -p "$SKILL_SETS/$set_name/$skill"
  printf '# %s\n' "$skill" >"$SKILL_SETS/$set_name/$skill/SKILL.md"
}
run_cli() { "$BIN" "$@"; }
run_alias() { "$TMP_ROOT/bin/sklset" "$@"; }
run_cli_with_default_root() { SKILL_SETS="" "$BIN" "$@"; }
run_cli_fail() {
  set +e
  output="$($BIN "$@" 2>&1)"
  status=$?
  set -e
  [ "$status" -ne 0 ] || fail "command should fail" "command succeeded: $BIN $*"
  printf '%s' "$output"
}

setup_case
make_skill default pi-craft
make_skill work sre-playbook
mkdir -p "$SKILL_SETS/.sources" "$SKILL_SETS/people-mgmt" "$SKILL_SETS/bad name"
assert_eq "list filters reserved and hidden sets" "people-mgmt
work" "$(run_cli list)"
assert_file_absent "$TARGET_DIR/.agents/skills/pi-craft" "list must not link default skills"
pass "list filters reserved, hidden, and invalid sets without mutating targets"

setup_case
mkdir -p "$HOME/skill-set/default/pi-craft" "$HOME/skill-set/work/sre-playbook"
printf '# pi-craft\n' >"$HOME/skill-set/default/pi-craft/SKILL.md"
printf '# sre-playbook\n' >"$HOME/skill-set/work/sre-playbook/SKILL.md"
assert_eq "unset SKILL_SETS defaults to home skill-set" "work" "$(run_cli_with_default_root list)"
pass "default skill root is ~/skill-set"

setup_case
ln -s "$BIN" "$TMP_ROOT/bin/sklset"
make_skill default pi-craft
make_skill work sre-playbook
assert_eq "current is none before load" "(none)" "$(run_cli current)"
assert_file_absent "$TARGET_DIR/.agents/skills/pi-craft" "current must not link default skills"
assert_eq "load reports active set" "loaded: work" "$(run_cli work)"
assert_eq "current reports loaded set" "work" "$(run_cli current)"
for dir in .agents .claude .codex; do
  assert_link_target "$TARGET_DIR/$dir/skills/pi-craft" "$SKILL_SETS/default/pi-craft" "default skill linked to $dir"
  assert_link_target "$TARGET_DIR/$dir/skills/sre-playbook" "$SKILL_SETS/work/sre-playbook" "active skill linked to $dir"
done
assert_eq "loading same set is no-op" "already loaded: work" "$(run_alias work)"
pass "load projects default and active skills to agent targets"

setup_case
mkdir -p "$TMP_ROOT/external-abp/proof"
printf '# proof\n' >"$TMP_ROOT/external-abp/proof/SKILL.md"
mkdir -p "$SKILL_SETS/abp"
ln -s "$TMP_ROOT/external-abp/proof" "$SKILL_SETS/abp/proof"
assert_eq "load reports symlinked set" "loaded: abp" "$(run_cli load abp)"
for dir in .agents .claude .codex; do
  assert_link_target "$TARGET_DIR/$dir/skills/proof" "$SKILL_SETS/abp/proof" "symlinked skill linked through skill-set path $dir"
done
pass "load accepts skill directories symlinked from external projects"

setup_case
make_skill default pi-craft
make_skill work sre-playbook
make_skill people-mgmt promotion-packets
run_cli load work >/dev/null
assert_eq "swap reports previous active set" "loaded: people-mgmt (was: work)" "$(run_cli load people-mgmt)"
for dir in .agents .claude .codex; do
  assert_link_target "$TARGET_DIR/$dir/skills/pi-craft" "$SKILL_SETS/default/pi-craft" "default survives swap in $dir"
  assert_file_absent "$TARGET_DIR/$dir/skills/sre-playbook" "previous active set removed from $dir"
  assert_link_target "$TARGET_DIR/$dir/skills/promotion-packets" "$SKILL_SETS/people-mgmt/promotion-packets" "new active set linked to $dir"
done
pass "load swaps active set and preserves default"

setup_case
make_skill default pi-craft
make_skill work sre-playbook
run_cli load work >/dev/null
assert_eq "unload reports previous active set" "unloaded: work" "$(run_cli unload)"
assert_eq "current after unload" "(none)" "$(run_cli current)"
for dir in .agents .claude .codex; do
  assert_link_target "$TARGET_DIR/$dir/skills/pi-craft" "$SKILL_SETS/default/pi-craft" "default remains after unload in $dir"
  assert_file_absent "$TARGET_DIR/$dir/skills/sre-playbook" "active set removed by unload from $dir"
done
pass "unload removes only active set"

setup_case
make_skill default pi-craft
make_skill work sre-playbook
run_cli load work >/dev/null
error_output="$(run_cli_fail load no-such-thing)"
assert_eq "missing set error" "skill-set: no such skill set: no-such-thing (try: skill-set list)" "$error_output"
assert_eq "failed load keeps state" "work" "$(run_cli current)"
traversal_output="$(run_cli_fail ../outside)"
assert_eq "path traversal set names are rejected" "skill-set: invalid skill set name: ../outside" "$traversal_output"
assert_eq "rejected name keeps state" "work" "$(run_cli current)"
bad_chars_output="$(run_cli_fail 'bad name')"
assert_eq "unsafe set name characters are rejected" "skill-set: invalid skill set name: bad name" "$bad_chars_output"
assert_eq "unsafe name keeps state" "work" "$(run_cli current)"
pass "failed load keeps prior state intact and rejects unsafe set names"

setup_case
make_skill default pi-craft
mkdir -p "$SKILL_SETS/work/bad name"
printf '# bad\n' >"$SKILL_SETS/work/bad name/SKILL.md"
bad_skill_output="$(run_cli_fail load work)"
assert_eq "unsafe skill name rejected" "skill-set: invalid skill name in work: bad name" "$bad_skill_output"
assert_file_absent "$TARGET_DIR/.agents/skills/bad name" "unsafe skill name does not link"
pass "skill directory names are validated before linking"

setup_case
make_skill default shared
make_skill work shared
conflict_output="$(run_cli_fail load work)"
assert_eq "default and active duplicate skill conflicts" "skill-set: skill exists in both default and work: shared" "$conflict_output"
assert_eq "duplicate conflict does not write state" "(none)" "$(run_cli current)"
assert_file_absent "$TARGET_DIR/.agents/skills/shared" "duplicate conflict does not sync default"
pass "default and active set duplicate skill names are rejected"

setup_case
make_skill default pi-craft
make_skill work sre-playbook
mkdir -p "$TARGET_DIR/.agents/skills/sre-playbook"
conflict_output="$(run_cli_fail load work)"
assert_eq "real target directory conflict" "skill-set: target exists and is not a managed symlink: $TARGET_DIR/.agents/skills/sre-playbook" "$conflict_output"
assert_eq "target conflict does not write state" "(none)" "$(run_cli current)"
pass "target conflicts fail without replacing real directories"

setup_case
make_skill default pi-craft
make_skill dev workflow
make_skill ruby rspec
run_cli load dev >/dev/null
printf '../outside\n' >"$STATE_FILE"
state_output="$(run_cli_fail load ruby)"
assert_eq "invalid state entry rejected" "skill-set: invalid state entry: ../outside" "$state_output"
assert_link_target "$TARGET_DIR/.agents/skills/workflow" "$SKILL_SETS/dev/workflow" "invalid state does not mutate existing links"
assert_file_absent "$TARGET_DIR/.agents/skills/rspec" "invalid state does not link proposed set"
pass "state file entries are validated before stack mutation"

setup_case
make_skill default pi-craft
make_skill dev workflow
make_skill ruby rspec
printf 'missing\n' >"$STATE_FILE"
missing_state_output="$(run_cli_fail current)"
assert_eq "missing state set rejected" "skill-set: state references missing skill set: missing" "$missing_state_output"
pass "state file entries must reference existing sets"

setup_case
make_skill default pi-craft
make_skill dev review
make_skill ruby review
run_cli load dev >/dev/null
assert_eq "swap with dropped-set shared skill reports load" "loaded: ruby (was: dev)" "$(run_cli load ruby)"
assert_eq "shared skill swap updates state" "ruby" "$(run_cli current)"
for dir in .agents .claude .codex; do
  assert_link_target "$TARGET_DIR/$dir/skills/review" "$SKILL_SETS/ruby/review" "shared skill relinked during swap $dir"
done
pass "load can replace a dropped set with a new set sharing a skill name"

setup_case
make_skill default pi-craft
make_skill dev review
make_skill devsafe review
make_skill ruby review
run_cli load dev >/dev/null
rm "$TARGET_DIR/.agents/skills/review"
ln -s "$SKILL_SETS/devsafe/review" "$TARGET_DIR/.agents/skills/review"
prefix_conflict="$(run_cli_fail load ruby)"
assert_eq "prefix-like unmanaged symlink rejected" "skill-set: target exists and is not a managed symlink: $TARGET_DIR/.agents/skills/review" "$prefix_conflict"
assert_link_target "$TARGET_DIR/.agents/skills/review" "$SKILL_SETS/devsafe/review" "prefix-like symlink is not treated as managed"
pass "managed symlink ownership is checked against exact active skill sources"

setup_case
make_skill default pi-craft
make_skill dev workflow
make_skill ruby rspec
run_cli load dev >/dev/null
mkdir -p "$TARGET_DIR/.claude/skills/rspec"
conflict_output="$(run_cli_fail load ruby)"
assert_eq "swap conflict in later target reports path" "skill-set: target exists and is not a managed symlink: $TARGET_DIR/.claude/skills/rspec" "$conflict_output"
assert_eq "swap conflict preserves state" "dev" "$(run_cli current)"
for dir in .agents .claude .codex; do
  assert_link_target "$TARGET_DIR/$dir/skills/workflow" "$SKILL_SETS/dev/workflow" "swap conflict preserves prior stack $dir"
done
assert_file_absent "$TARGET_DIR/.agents/skills/rspec" "swap conflict does not partially link earlier target"
assert_file_absent "$TARGET_DIR/.codex/skills/rspec" "swap conflict does not partially link later target"
pass "load preflights target conflicts before mutating current stack"

setup_case
make_skill default pi-craft
doctor_output="$(run_cli doctor)"
case "$doctor_output" in
  *"SKILL_SETS  : $SKILL_SETS  ok"*"default     : present (1 skills)"*"$TARGET_DIR/.agents/skills"*"(0 skills)"*"$TARGET_DIR/.claude/skills"*"(0 skills)"*"$TARGET_DIR/.codex/skills"*"(0 skills)"*) ;;
  *) fail "doctor shows config and managed target paths" "$doctor_output" ;;
esac
pass "doctor shows config and managed target paths"

setup_case
make_skill default pi-craft
sync_one="$(run_cli sync)"
sync_two="$(run_cli sync)"
assert_eq "sync output" "synced: default" "$sync_one"
assert_eq "sync is idempotent" "synced: default" "$sync_two"
assert_link_target "$TARGET_DIR/.agents/skills/pi-craft" "$SKILL_SETS/default/pi-craft" "sync links default"
assert_file_absent "$STATE_FILE.lock" "sync removes operation lock"
pass "sync links default idempotently"

setup_case
make_skill default pi-craft
make_skill work sre-playbook
mkdir "$STATE_FILE.lock"
locked_output="$(run_cli_fail load work)"
assert_eq "operation lock rejects concurrent mutation" "skill-set: another skill-set operation is running: $STATE_FILE.lock" "$locked_output"
assert_file_absent "$TARGET_DIR/.agents/skills/pi-craft" "locked load does not sync default"
assert_file_absent "$TARGET_DIR/.agents/skills/sre-playbook" "locked load does not link active skill"
pass "mutating commands refuse concurrent operation locks"

setup_case
make_skill work sre-playbook
assert_eq "sync reports absent default" "synced: no default set" "$(run_cli sync)"
assert_file_absent "$TARGET_DIR/.agents/skills/sre-playbook" "sync without default must not link switchable skills"
pass "sync reports when no default set exists"

setup_case
make_skill default pi-craft
make_skill dev workflow
make_skill product-management specify
source "$ROOT_DIR/completions/skill-set.bash"
complete -p sklset >/dev/null || fail "alias completion is registered" "missing completion for sklset"
COMP_WORDS=(skill-set "")
COMP_CWORD=1
_skill_set_completion
assert_eq "top-level completion includes commands and sets" "--help add current dev doctor list load product-management remove sync unload" "$(printf '%s\n' "${COMPREPLY[@]}" | sort | tr '\n' ' ' | sed 's/ $//')"
COMP_WORDS=(skill-set load "")
COMP_CWORD=2
_skill_set_completion
assert_eq "load completion includes set names only" "dev product-management" "$(printf '%s\n' "${COMPREPLY[@]}" | sort | tr '\n' ' ' | sed 's/ $//')"
COMP_WORDS=(skill-set load dev "")
COMP_CWORD=3
_skill_set_completion
assert_eq "load completion excludes already-typed sets" "product-management" "$(printf '%s\n' "${COMPREPLY[@]}" | sort | tr '\n' ' ' | sed 's/ $//')"
COMP_WORDS=(skill-set current "")
COMP_CWORD=2
_skill_set_completion
assert_eq "commands with no args suppress file completion" "" "${COMPREPLY[*]-}"
run_cli load dev >/dev/null
COMP_WORDS=(skill-set add "")
COMP_CWORD=2
_skill_set_completion
assert_eq "add completion excludes sets already in stack" "product-management" "$(printf '%s\n' "${COMPREPLY[@]}" | sort | tr '\n' ' ' | sed 's/ $//')"
COMP_WORDS=(skill-set remove "")
COMP_CWORD=2
_skill_set_completion
assert_eq "remove completion shows only sets in stack" "dev" "$(printf '%s\n' "${COMPREPLY[@]}" | sort | tr '\n' ' ' | sed 's/ $//')"
pass "bash completion suggests commands and skill sets"

setup_case
make_skill default pi-craft
make_skill dev workflow
make_skill ruby rspec
make_skill python pytest
assert_eq "load multi reports combined stack" "loaded: dev ruby" "$(run_cli load dev ruby)"
assert_eq "current prints stack one per line" "dev
ruby" "$(run_cli current)"
for dir in .agents .claude .codex; do
  assert_link_target "$TARGET_DIR/$dir/skills/pi-craft" "$SKILL_SETS/default/pi-craft" "default linked under multi-load $dir"
  assert_link_target "$TARGET_DIR/$dir/skills/workflow" "$SKILL_SETS/dev/workflow" "dev linked under multi-load $dir"
  assert_link_target "$TARGET_DIR/$dir/skills/rspec" "$SKILL_SETS/ruby/rspec" "ruby linked under multi-load $dir"
done
assert_eq "re-loading same stack reports already loaded" "already loaded: dev ruby" "$(run_cli load dev ruby)"
assert_eq "load swap reports prior stack" "loaded: dev python (was: dev ruby)" "$(run_cli load dev python)"
for dir in .agents .claude .codex; do
  assert_link_target "$TARGET_DIR/$dir/skills/workflow" "$SKILL_SETS/dev/workflow" "dev still linked after swap $dir"
  assert_file_absent "$TARGET_DIR/$dir/skills/rspec" "ruby removed after swap $dir"
  assert_link_target "$TARGET_DIR/$dir/skills/pytest" "$SKILL_SETS/python/pytest" "python linked after swap $dir"
done
pass "load handles multi-set stack and swaps in order"

setup_case
make_skill default pi-craft
make_skill dev proof
make_skill ruby proof
conflict_output="$(run_cli_fail load dev ruby)"
assert_eq "cross-set conflict surfaces both names" "skill-set: skill exists in both dev and ruby: proof" "$conflict_output"
assert_eq "cross-set conflict leaves state empty" "(none)" "$(run_cli current)"
assert_file_absent "$TARGET_DIR/.agents/skills/pi-craft" "cross-set conflict does not sync default"
assert_file_absent "$TARGET_DIR/.agents/skills/proof" "cross-set conflict does not link"
pass "cross-set conflicts are caught before any linking"

setup_case
make_skill default pi-craft
make_skill dev workflow
dup_output="$(run_cli_fail load dev dev)"
assert_eq "duplicate input rejected" "skill-set: skill set listed more than once: dev" "$dup_output"
pass "load rejects duplicate set names in input"

setup_case
make_skill default pi-craft
make_skill dev workflow
make_skill ruby rspec
run_cli load dev >/dev/null
assert_eq "add reports added" "added: ruby" "$(run_cli add ruby)"
assert_eq "add shows in stack" "dev
ruby" "$(run_cli current)"
assert_eq "add no-op when already in stack" "already in stack: ruby" "$(run_cli add ruby)"
for dir in .agents .claude .codex; do
  assert_link_target "$TARGET_DIR/$dir/skills/workflow" "$SKILL_SETS/dev/workflow" "dev still present after add $dir"
  assert_link_target "$TARGET_DIR/$dir/skills/rspec" "$SKILL_SETS/ruby/rspec" "ruby linked after add $dir"
done
pass "add pushes onto the stack and is idempotent"

setup_case
make_skill default pi-craft
make_skill dev proof
make_skill ruby proof
run_cli load dev >/dev/null
add_conflict="$(run_cli_fail add ruby)"
assert_eq "add rejects on conflict" "skill-set: skill exists in both dev and ruby: proof" "$add_conflict"
assert_eq "add conflict preserves stack" "dev" "$(run_cli current)"
assert_link_target "$TARGET_DIR/.agents/skills/proof" "$SKILL_SETS/dev/proof" "add conflict preserves dev's proof link"
pass "add detects conflicts against existing stack"

setup_case
make_skill default pi-craft
make_skill dev workflow
make_skill ruby rspec
run_cli load dev >/dev/null
mkdir -p "$TARGET_DIR/.claude/skills/rspec"
add_conflict="$(run_cli_fail add ruby)"
assert_eq "add path conflict reports later target" "skill-set: target exists and is not a managed symlink: $TARGET_DIR/.claude/skills/rspec" "$add_conflict"
assert_eq "add path conflict preserves stack" "dev" "$(run_cli current)"
assert_file_absent "$TARGET_DIR/.agents/skills/rspec" "add path conflict does not partially link earlier target"
assert_file_absent "$TARGET_DIR/.codex/skills/rspec" "add path conflict does not partially link later target"
for dir in .agents .claude .codex; do
  assert_link_target "$TARGET_DIR/$dir/skills/workflow" "$SKILL_SETS/dev/workflow" "add path conflict preserves existing stack $dir"
done
pass "add preflights target conflicts before linking new set"

setup_case
make_skill default pi-craft
make_skill dev workflow
make_skill ruby rspec
make_skill python pytest
run_cli load dev ruby python >/dev/null
assert_eq "remove middle reports name" "removed: ruby" "$(run_cli remove ruby)"
assert_eq "remove preserves ordering" "dev
python" "$(run_cli current)"
for dir in .agents .claude .codex; do
  assert_link_target "$TARGET_DIR/$dir/skills/workflow" "$SKILL_SETS/dev/workflow" "dev kept after remove $dir"
  assert_file_absent "$TARGET_DIR/$dir/skills/rspec" "ruby unlinked after remove $dir"
  assert_link_target "$TARGET_DIR/$dir/skills/pytest" "$SKILL_SETS/python/pytest" "python kept after remove $dir"
done
not_in_stack="$(run_cli_fail remove ruby)"
assert_eq "remove errors when set not in stack" "skill-set: not in stack: ruby" "$not_in_stack"
pass "remove takes a set out of the middle of the stack"

setup_case
make_skill default pi-craft
make_skill dev workflow
make_skill ruby rspec
run_cli load dev ruby >/dev/null
case "$(run_cli doctor)" in
  *"current     : dev ruby"*) ;;
  *) fail "doctor shows multi-set stack" "$(run_cli doctor)" ;;
esac
pass "doctor displays the active stack on one line"

setup_case
make_skill default pi-craft
make_skill dev workflow
make_skill ruby rspec
run_cli load dev ruby >/dev/null
assert_eq "unload reports full stack" "unloaded: dev ruby" "$(run_cli unload)"
assert_eq "current after multi unload" "(none)" "$(run_cli current)"
for dir in .agents .claude .codex; do
  assert_file_absent "$TARGET_DIR/$dir/skills/workflow" "dev removed after unload $dir"
  assert_file_absent "$TARGET_DIR/$dir/skills/rspec" "ruby removed after unload $dir"
  assert_link_target "$TARGET_DIR/$dir/skills/pi-craft" "$SKILL_SETS/default/pi-craft" "default preserved after unload $dir"
done
pass "unload clears the entire stack at once"

setup_case
make_skill default a-default
make_skill default z-default
mkdir -p "$TARGET_DIR/.claude/skills/z-default"
default_conflict="$(run_cli_fail sync)"
assert_eq "default sync preflight reports conflict" "skill-set: target exists and is not a managed symlink: $TARGET_DIR/.claude/skills/z-default" "$default_conflict"
assert_file_absent "$TARGET_DIR/.agents/skills/a-default" "default sync conflict does not partially link earlier skill"
assert_file_absent "$TARGET_DIR/.codex/skills/a-default" "default sync conflict does not partially link later target"
pass "sync preflights default conflicts before linking"

setup_case
make_skill default pi-craft
make_skill dev workflow
mkdir -p "$STATE_FILE"
load_state_failure="$(run_cli_fail load dev)"
assert_eq "load state write failure reports error" "skill-set: cannot write state file: $STATE_FILE" "$load_state_failure"
assert_file_absent "$TARGET_DIR/.agents/skills/workflow" "failed load state write rolls back active skill"
assert_link_target "$TARGET_DIR/.agents/skills/pi-craft" "$SKILL_SETS/default/pi-craft" "failed load keeps synced default skill"
pass "load rolls back links when state write fails"

setup_case
make_skill default pi-craft
make_skill dev workflow
make_skill ruby rspec
run_cli load dev >/dev/null
mkdir -p "$TMP_ROOT/locks"
export LOCK_DIR="$TMP_ROOT/locks/add.lock"
chmod a-w "$(dirname "$STATE_FILE")"
add_state_failure="$(run_cli_fail add ruby)"
assert_eq "add state write failure reports error" "skill-set: cannot create temporary state file" "$add_state_failure"
assert_file_absent "$TARGET_DIR/.agents/skills/rspec" "failed add state write rolls back new skill"
assert_link_target "$TARGET_DIR/.agents/skills/workflow" "$SKILL_SETS/dev/workflow" "failed add preserves existing active skill"
pass "add rolls back links when state write fails"

setup_case
make_skill default pi-craft
make_skill dev workflow
run_cli load dev >/dev/null
mkdir -p "$TMP_ROOT/locks"
export LOCK_DIR="$TMP_ROOT/locks/remove.lock"
chmod a-w "$(dirname "$STATE_FILE")"
remove_state_failure="$(run_cli_fail remove dev)"
assert_eq "remove state write failure reports error" "skill-set: cannot remove state file: $STATE_FILE" "$remove_state_failure"
assert_link_target "$TARGET_DIR/.agents/skills/workflow" "$SKILL_SETS/dev/workflow" "failed remove relinks active skill"
pass "remove rolls back unlinks when state write fails"

setup_case
make_skill default pi-craft
make_skill dev workflow
make_skill ruby rspec
run_cli load dev ruby >/dev/null
mkdir -p "$TMP_ROOT/locks"
export LOCK_DIR="$TMP_ROOT/locks/unload.lock"
chmod a-w "$(dirname "$STATE_FILE")"
unload_state_failure="$(run_cli_fail unload)"
assert_eq "unload state write failure reports error" "skill-set: cannot remove state file: $STATE_FILE" "$unload_state_failure"
assert_link_target "$TARGET_DIR/.agents/skills/workflow" "$SKILL_SETS/dev/workflow" "failed unload relinks first active skill"
assert_link_target "$TARGET_DIR/.agents/skills/rspec" "$SKILL_SETS/ruby/rspec" "failed unload relinks second active skill"
pass "unload rolls back unlinks when state write fails"

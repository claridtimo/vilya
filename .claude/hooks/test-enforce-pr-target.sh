#!/usr/bin/env bash
#
# Regression battery for enforce-pr-target.sh — run after ANY edit to the hook:
#   .claude/hooks/test-enforce-pr-target.sh
# Exercises every bypass/false-deny class found across the #61/#63 review rounds, plus the
# degraded (no-python3) path via a stripped PATH. Exits non-zero on any failure.
# (Test-only dependency on python3 for safe JSON construction; the DEGRADED section still
# tests the hook itself without python3 on PATH.)

set -u
HOOK="$(cd "$(dirname "$0")" && pwd)/enforce-pr-target.sh"
pass=0; fail=0

run_case() {  # expect(DENY|ALLOW) command [pathenv]
  local expect="$1" cmd="$2" pathenv="${3:-$PATH}"
  local input verdict out
  input=$(python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.argv[1]}}))' "$cmd")
  out=$(printf '%s' "$input" | env PATH="$pathenv" bash "$HOOK")
  _judge "$expect" "$out" "$cmd"
}

run_case_raw() {  # expect(DENY|ALLOW) raw-json-input label [pathenv]
  local expect="$1" input="$2" label="$3" pathenv="${4:-$PATH}"
  local out
  out=$(printf '%s' "$input" | env PATH="$pathenv" bash "$HOOK")
  _judge "$expect" "$out" "$label"
}

_judge() {
  local expect="$1" out="$2" label="$3" verdict
  if printf '%s' "$out" | grep -q '"permissionDecision":"deny"'; then verdict=DENY; else verdict=ALLOW; fi
  if [ "$verdict" = "$expect" ]; then
    pass=$((pass+1)); echo "ok   $expect  $label"
  else
    fail=$((fail+1)); echo "FAIL want=$expect got=$verdict  $label"
  fi
}

echo "=== DENY: untargeted creates, incl. every historical bypass class ==="
run_case DENY 'gh pr create --title foo --body bar'
run_case DENY 'gh pr create>out --title foo'                       # glued redirect (round 9)
run_case DENY 'gh pr create</dev/null'                             # glued stdin redirect
run_case DENY 'gh pr create 2>&1'                                  # redirect combo, still untargeted
run_case DENY 'gh pr create --title foo # -R claridtimo/x'         # target only in a comment
run_case DENY 'git push && gh pr create -t x'
run_case DENY 'git push&&gh pr create -t x'                        # glued operator (v6)
run_case DENY 'url=$(gh pr create -t x)'                           # command substitution (v9)
run_case DENY 'echo `gh pr create -t x`'                           # backtick substitution (v9)
run_case DENY 'gh pr create --title "use -R claridtimo/bang-game"' # target text inside a title (v3)
run_case DENY 'gh pr create -R greyhavens/bang-game -t x'
run_case DENY 'gh pr create -R claridtimo/x -R greyhavens/y'       # last -R wins (v8)
run_case DENY '/usr/bin/gh pr create -t x'                         # gh by path (v7)
run_case DENY $'git status\ngh pr create -t x'                     # multi-line (v6)
run_case DENY 'gh pr create -R claridtimo/x && gh pr create -t y'  # second clause untargeted

echo "=== ALLOW: targeted creates + unrelated commands ==="
run_case ALLOW 'gh pr create -R claridtimo/bang-game -t x -b y'
run_case ALLOW 'gh pr create --repo claridtimo/bang-game -t x'
run_case ALLOW 'gh pr create --repo=claridtimo/bang-game -t x'
run_case ALLOW 'gh pr create -Rclaridtimo/bang-game -t x'          # glued short form
run_case ALLOW "gh pr create -R claridtimo/x --body 'a && b; gh pr create'"  # ops inside quoted body (v3)
run_case ALLOW "gh pr create -R claridtimo/x --title \"don't break\""        # apostrophe (v5)
run_case ALLOW 'gh pr create -R claridtimo/x > /tmp/out'           # redirect after target
run_case ALLOW 'gh pr create > /tmp/out -R claridtimo/x'           # redirect before target
run_case ALLOW 'gh pr create 2>&1 -R claridtimo/x'                 # &-in-redirect (was a v9 false-deny)
run_case ALLOW 'gh pr create>log -R claridtimo/x'                  # glued redirect, still targeted
run_case ALLOW 'gh pr list'
run_case ALLOW 'gh pr view 63 -R claridtimo/bang-game'
run_case ALLOW 'gh pr merge 63 -R claridtimo/bang-game --merge'
run_case ALLOW 'git commit -m "gh pr create later"'                # words in a -m value
run_case ALLOW 'echo done'                                         # prefilter early-exit (no gh)
run_case ALLOW './gradlew deploy && echo high create'              # prefilter passes, no gh token
run_case ALLOW 'gh pr create --title=has#hash -R claridtimo/x'     # mid-word # is NOT a comment
run_case ALLOW 'gh repo create claridtimo/new-repo'                # repo create is not pr create

echo "=== Substitution extraction (round 11): inner commands judged, outer kept contiguous ==="
run_case DENY 'gh pr create -R claridtimo/x -t "notes: $(gh pr create -t oops)"'   # dq-hidden create
run_case DENY 'gh pr create -R claridtimo/x -t "notes: `gh pr create -t oops`"'    # dq-hidden backtick
run_case DENY 'gh pr create -R claridtimo/x -b "$(echo $(gh pr create -t deep))"'  # nested substitution
run_case ALLOW 'gh pr create --title "cost $(compute) done" -R claridtimo/x'  # dq subst mid-command
run_case ALLOW 'gh pr create --title $(gen-title) -R claridtimo/x'   # unquoted subst mid-command
run_case ALLOW 'gh pr create -R claridtimo/x --title "(parens) are fine"'    # plain parens in dq
run_case DENY 'gh pr create --recover -Rclaridtimo/x.txt'            # --recover value is opaque, not a -R

echo "=== Shell wrappers (round 15): bash -c / eval strings are commands too ==="
run_case DENY  'bash -c "gh pr create -t x"'
run_case DENY  "bash -lc 'gh pr create -t x'"                        # combined flag cluster
run_case DENY  "sh -c 'gh pr create -t x'"
run_case DENY  "/bin/bash -c 'gh pr create -t x'"                    # shell by path
run_case DENY  'eval "gh pr create -t x"'
run_case DENY  'eval gh pr create -t x'                              # eval with unquoted args
run_case DENY  "nohup bash -c 'gh pr create -t x' &"
run_case ALLOW "bash -c 'gh pr create -R claridtimo/x -t y'"         # targeted inside the wrapper
run_case ALLOW 'eval "gh pr view 63 -R claridtimo/x" && echo create' # wrapper runs no create
run_case ALLOW "bash -c 'echo ghost created'"                        # words, not tokens

echo "=== Wrappers only at command position (round 19) ==="
run_case ALLOW 'grep eval -c "gh pr create test" file.txt'           # eval as a grep ARG
run_case ALLOW 'echo "gh pr create -t x" | grep bash'                # bash as a grep ARG
run_case ALLOW 'git log --grep eval -- "gh pr create notes.md"'      # wrapper words in args
run_case DENY  'sudo bash -c "gh pr create -t x"'                    # prefix keeps command position
run_case DENY  'timeout 5 bash -c "gh pr create -t x"'               # numeric prefix arg
run_case DENY  'xargs bash -c "gh pr create -t x"'
run_case DENY  'find . -name "*.md" -exec bash -c "gh pr create -t x" \;'  # -exec re-arms
run_case DENY  'VAR=1 env bash -lc "gh pr create -t x"'
run_case DENY  'sudo -u root bash -c "gh pr create -t x"'            # option VALUE before the shell (round 20)
run_case DENY  'xargs -I {} bash -c "gh pr create -t x"'             # unglued option value
run_case DENY  'env -i bash -c "gh pr create -t x"'                  # no-value option directly before shell
run_case DENY  'sudo -u root gh pr create -t x'                      # generic detection through prefixes
run_case ALLOW 'sudo -u root bash -c "gh pr create -R claridtimo/x"' # targeted inside sudo-wrapped shell
run_case ALLOW 'sudo -u root gh pr create -R claridtimo/x'

echo "=== echo/printf clauses print, not execute (round 16) ==="
run_case ALLOW 'echo bash -c "gh pr create -t x"'                    # echoed text, never run
run_case ALLOW 'echo gh pr create'                                   # literal words to stdout
run_case ALLOW 'printf "%s\n" gh pr create'                          # printf variant
run_case DENY  'echo done && gh pr create -t x'                      # later clause still judged

echo "=== Piped echo payloads (round 17): echo | bash executes the text ==="
run_case DENY  'echo "gh pr create -t x" | bash'
run_case DENY  'printf "gh pr create -t x" | sh'
run_case DENY  'echo gh pr create -t x | bash'                       # unquoted payload
run_case ALLOW 'echo "gh pr create -R claridtimo/x" | bash'          # targeted payload
run_case ALLOW 'echo "gh pr create -t x" | grep create'              # pipe into a non-shell
run_case ALLOW 'echo "gh pr create -t x" || bash'                    # OR, not a pipe: bash gets no stdin script
run_case ALLOW 'echo done | bash'
run_case ALLOW 'echo "gh pr create -t x" ; bash'                     # printed then interactive shell

echo "=== Line continuations (round 16): JSON-escaped whitespace in the degraded greps ==="
run_case DENY  $'gh pr \\\ncreate -t x'                              # continued bare create (precise)

echo "=== Case-insensitive owner match (round 13): GitHub owners are case-insensitive ==="
run_case ALLOW 'gh pr create -R Claridtimo/bang-game -t x'           # capitalized owner, targeted
run_case ALLOW 'gh pr create --repo=CLARIDTIMO/bang-game -t x'       # any-case owner (precise path)
run_case DENY  'gh pr create -R Greyhavens/bang-game -t x'           # case variance is not a pass

echo "=== FALLBACK route (round 13): python3 present but tokenization fails ==="
# An unbalanced quote makes shlex raise → the precise path prints FALLBACK → the degraded grep
# decides. Distinct from the no-python3 route (PATH-stripped below): this exercises the
# ValueError branch inside the python script itself.
run_case DENY  'gh pr create -t "unbalanced'
run_case ALLOW 'gh pr create -R claridtimo/x -t "unbalanced'

echo "=== Dangling value flags must not swallow a clause boundary (round 18) ==="
run_case DENY 'gh pr create -t && true -R claridtimo/x'    # -t at boundary; later clause has the -R
run_case DENY 'gh pr create --title ; true -R claridtimo/x'
run_case DENY 'gh pr create -R && true'                    # dangling -R itself is no target

echo "=== Payload-scoping: claridtimo in cwd/paths must NOT count as a target ==="
CWD_JSON='{"cwd":"/home/dev/claridtimo/bang-game","transcript_path":"/home/dev/claridtimo/t.jsonl","tool_input":{"command":"gh pr create -t x"}}'
run_case_raw DENY "$CWD_JSON" 'bare create + claridtimo-bearing cwd (precise)'
DESC_JSON='{"tool_input":{"command":"gh pr create -t x","description":"Open PR with -R claridtimo/bang-game"},"cwd":"/x"}'
DESC_JSON2='{"tool_input":{"command":"gh pr view 63 -R claridtimo/x","description":"docs mention gh pr create"},"cwd":"/x"}'
run_case_raw DENY  "$DESC_JSON"  'bare create + target only in description (precise)'

echo "=== Degraded path (no python3 on PATH) ==="
FAKEBIN="$(mktemp -d)"
trap 'rm -rf "$FAKEBIN"' EXIT
for t in bash cat grep printf env sh; do ln -sf "$(command -v $t)" "$FAKEBIN/$t"; done
run_case DENY  'gh pr create -t x'                    "$FAKEBIN"
run_case ALLOW 'gh pr create -R claridtimo/x -t y'    "$FAKEBIN"
run_case ALLOW 'gh pr create --repo=claridtimo/x'     "$FAKEBIN"
run_case ALLOW 'gh pr create -Rclaridtimo/x'          "$FAKEBIN"
run_case ALLOW 'echo done'                            "$FAKEBIN"
run_case ALLOW 'gh pr view 63 -R claridtimo/x'        "$FAKEBIN"
run_case ALLOW 'gh pr create -R Claridtimo/x -t y'    "$FAKEBIN"     # capitalized owner (degraded)
run_case DENY  $'gh pr \\\ncreate -t x'               "$FAKEBIN"     # continued bare create (round 16)
run_case ALLOW $'gh pr \\\ncreate -R claridtimo/x'    "$FAKEBIN"     # continued targeted create
run_case ALLOW $'gh pr create -t x -R \\\nclaridtimo/x' "$FAKEBIN"   # continuation inside flag adjacency
run_case_raw DENY "$CWD_JSON" 'bare create + claridtimo-bearing cwd (degraded, round 10)' "$FAKEBIN"
run_case_raw DENY  "$DESC_JSON"  'bare create + target only in description (degraded, round 18)' "$FAKEBIN"
run_case_raw ALLOW "$DESC_JSON2" 'targeted view + create phrase in description (degraded, round 18)' "$FAKEBIN"

echo "=== Degraded path: ACCEPTED under-blocks, pinned (round 12) ==="
# The tokenizer-free fallback deliberately allows these two shapes: scoping flags to clauses
# with sed/grep was the v2 approach and false-denied real targeted creates (quoted PR bodies
# containing shell text). The precise path DENIES both — asserted alongside so the asymmetry is
# pinned and a future "fix" that flips either direction fails here.
run_case DENY  'gh pr view -R claridtimo/x && gh pr create -t y'                 # precise: real deny
run_case ALLOW 'gh pr view -R claridtimo/x && gh pr create -t y'     "$FAKEBIN"  # degraded: accepted
run_case ALLOW 'gh pr create --title "see -R claridtimo/x docs"'     "$FAKEBIN"  # degraded: accepted

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]

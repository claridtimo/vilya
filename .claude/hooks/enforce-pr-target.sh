#!/usr/bin/env bash
#
# PreToolUse(Bash) hook — hard backstop against opening PRs on the upstream fork parent.
#
# This repo (and the sibling fork clones) is a FORK of greyhavens/*. `gh pr create` with no
# -R/--repo defaults its base repo to the fork PARENT, so a bare invocation opens a PR against
# greyhavens by mistake (it has, more than once). The CLAUDE.md guidance + `gh repo set-default`
# are soft — this hook is the enforced version: it DENIES any `gh pr create` not explicitly aimed
# at a claridtimo/* repo, and feeds the reason back so the model just re-runs correctly.
#
# WHY it parses argv instead of grepping raw text: earlier revisions matched the raw command
# string, which mis-read a `-R claridtimo/…` substring inside a --title/--body (false allow) and
# split on shell operators inside a quoted value (false deny). In THIS repo those aren't
# pathological — we routinely write PRs whose titles/bodies contain gh examples, shell snippets,
# and ordinary apostrophes ("don't"). So the precise path tokenizes the command the way a shell
# actually would, with Python's `shlex` (the reference POSIX shell lexer — it handles nested quote
# types, e.g. an apostrophe inside a double-quoted title, which a bash/xargs tokenizer cannot do
# portably). Only a real `-R`/`--repo` flag token — never text inside a quoted value — counts as a
# target, and clause boundaries are only real operator tokens.
#
# Dependency posture: a PreToolUse hook that ERRORS is treated as non-blocking, so a hard
# dependency would silently REMOVE the guard on a box that lacks it. The precise path uses python3
# (stdlib only: json + shlex), guarded by `command -v`. If python3 is absent OR the command can't
# be parsed, the script DEGRADES to a conservative text check that never false-denies a targeted PR
# and still catches the common bare omission. It never exits non-zero; blocking is via the JSON
# "deny", not the exit code.

INPUT=$(cat)

# Cheap prefilter before anything else: a deny can only ever fire on a clause containing the
# tokens `gh` … `pr` … `create`, and no shell QUOTING can produce those tokens without the letters
# "gh" and "create" appearing verbatim in the raw input (JSON never escapes letters). So for the
# overwhelmingly common unrelated Bash call, skip the python3 spawn (and the greps) entirely.
# A deliberately backslash-escaped `crea\te` slips past this — deliberate evasion is out of the
# threat model (the hook guards against ACCIDENTAL omission), same class as shell aliases.
case "$INPUT" in *gh*) : ;; *) exit 0 ;; esac
case "$INPUT" in *create*) : ;; *) exit 0 ;; esac

emit_deny() {
  cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"PRs must target the claridtimo fork, never upstream greyhavens. This `gh pr create` has no explicit claridtimo target (as a real -R/--repo FLAG, not text inside a --title/--body), so gh would default its base repo to the upstream fork parent. Re-run with the flag aimed at claridtimo, e.g.:\n  gh pr create -R claridtimo/<repo> --base <branch> --head <feature-branch> ...\nA target on a different &&-chained command, or one that only appears inside a quoted title/body, does NOT count."}}
JSON
}

# ---- Precise path: python3 (stdlib json + shlex) --------------------------------------------
# Emits exactly one word on stdout: DENY, ALLOW, or FALLBACK. Any crash / missing python / weird
# exit prints nothing, and we fall through to the degraded check below. Never trusts a partial parse.
if command -v python3 >/dev/null 2>&1; then
  # Input goes via env var (HOOK_INPUT), leaving stdin free for the heredoc'd script itself.
  verdict=$(HOOK_INPUT="$INPUT" python3 - <<'PY' 2>/dev/null
import json, re, shlex, sys, os
try:
    cmd = json.loads(os.environ.get("HOOK_INPUT", "")).get("tool_input", {}).get("command", "")
except Exception:
    print("FALLBACK"); sys.exit(0)
if not cmd:
    print("FALLBACK"); sys.exit(0)
def scan_subst(s, i, opener):
    # Scan a command-substitution / subshell body starting at s[i] (the char AFTER the opener).
    # opener "(" ends at its nesting-matched ")" (honoring quotes and backslashes, the way bash
    # re-parses the inside of $() as a fresh context); opener backtick ends at the next unescaped
    # backtick (backticks don't nest unescaped). Unterminated bodies consume to end-of-string —
    # that input is malformed shell that bash would refuse to run, so any verdict is safe.
    # Returns (content, index_after_closer).
    q2 = None
    depth = 1
    buf = []
    j, n = i, len(s)
    while j < n:
        c = s[j]
        if q2 is not None:
            buf.append(c)
            if c == q2:
                q2 = None
            elif c == "\\" and q2 == '"' and j + 1 < n:
                buf.append(s[j + 1]); j += 2; continue
            j += 1; continue
        if c == "\\" and j + 1 < n:
            buf.append(c); buf.append(s[j + 1]); j += 2; continue
        if c in ("'", '"'):
            q2 = c; buf.append(c); j += 1; continue
        if opener == "(":
            if c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
                if depth == 0:
                    return "".join(buf), j + 1
        elif c == chr(96):
            return "".join(buf), j + 1
        buf.append(c); j += 1
    return "".join(buf), n

def to_separators(s, depth=0):
    # shlex.split() is a quote-aware WORD splitter, not a shell control-operator parser: it only
    # treats & | ; and newlines as separators when whitespace already surrounds them. Real bash
    # splits on them regardless (`echo a&&echo b` is two commands). So a quote-aware pre-pass
    # rewrites every shell metacharacter the way a shell lexer would:
    #   - unquoted control operators (& | ; newline) become " ; " — a clause boundary;
    #   - unquoted redirections (< >, and an & glued to one: 2>&1, &>f) become " " — a TOKEN
    #     boundary but NOT a clause boundary, since a redirect doesn't end the command
    #     (`gh pr create>out` must still be seen as a create, and a `-R` AFTER `2>&1` is still
    #     part of the same clause);
    #   - an unquoted # at word start drops the rest of the line (a comment; a mid-word # stays
    #     literal, matching shell) — a `-R claridtimo/…` living only in a comment can't count;
    #   - command substitutions and subshells — $(…), `…`, bare (…) — are EXTRACTED: the body is
    #     removed from the enclosing command (which stays contiguous, so a substitution used as a
    #     flag value can't split a targeted create away from its -R) and appended as its own
    #     " ; "-separated clause, recursively pre-passed, so an inner `gh pr create` is judged on
    #     its own. This applies inside DOUBLE quotes too — bash executes $()/backticks there
    #     (only single quotes are inert), so a create hidden in a --title "… $(gh pr create …)"
    #     is still caught (11th review round).
    # Other quoted metacharacters (a --body/title) are preserved; a backslash-escaped one is
    # preserved for shlex to handle. Remaining blind spots, all deliberate-evasion class (out of
    # threat model — the guard is against ACCIDENTAL omission): shell aliases, backslash-escaped
    # letters (`crea\te`), ${var@P}-style expansion tricks. Heredoc BODIES are not
    # quote-delimited, so a bare `gh pr create` EXAMPLE inside a heredoc'd --body-file can
    # false-DENY — the safe direction; re-run with the example inside a quoted --body or a file.
    if depth > 10:
        raise ValueError("substitution nesting too deep")   # → caller falls back (conservative)
    out = []
    extracted = []
    q = None
    i, n = 0, len(s)
    while i < n:
        c = s[i]
        if q is not None:                       # inside a quote
            if q == '"':
                # bash still runs $() and backticks inside double quotes — extract them
                if c == "$" and i + 1 < n and s[i + 1] == "(":
                    body, i = scan_subst(s, i + 2, "(")
                    extracted.append(body); continue
                if c == chr(96):
                    body, i = scan_subst(s, i + 1, chr(96))
                    extracted.append(body); continue
                if c == "\\" and i + 1 < n:
                    if s[i + 1] == "\n":        # line continuation: bash removes both chars
                        i += 2; continue
                    out.append(c); out.append(s[i + 1]); i += 2; continue
            out.append(c)
            if c == q:
                q = None
            i += 1; continue
        if c in ("'", '"'):
            q = c; out.append(c); i += 1; continue
        if c == "\\" and i + 1 < n:              # unquoted backslash escapes the next char
            if s[i + 1] == "\n":                 # line continuation: bash removes both chars,
                i += 2; continue                  # joining the surrounding text (16th round)
            out.append(c); out.append(s[i + 1]); i += 2; continue
        if c == "#" and (i == 0 or s[i - 1] in " \t&|;()<>\n\r" or s[i - 1] == chr(96)):
            while i < n and s[i] != "\n":        # comment: shell ignores to end of line
                i += 1
            continue
        # The " __subst__ " placeholder keeps the token count intact: a substitution used as a
        # flag VALUE (--title $(gen) -R …) must still occupy the value slot, or the value flag
        # would consume the following -R as its value and false-deny a targeted create.
        if c == "$" and i + 1 < n and s[i + 1] == "(":
            body, i = scan_subst(s, i + 2, "(")
            extracted.append(body); out.append(" __subst__ "); continue
        if c == "(":                             # bare subshell / grouping
            body, i = scan_subst(s, i + 1, "(")
            extracted.append(body); out.append(" __subst__ "); continue
        if c == chr(96):
            body, i = scan_subst(s, i + 1, chr(96))
            extracted.append(body); out.append(" __subst__ "); continue
        if c in "<>":
            out.append(" ")                      # redirection: token boundary, not clause boundary
            i += 1; continue
        if c == "&" and ((i + 1 < n and s[i + 1] in "<>") or (i > 0 and s[i - 1] in "<>")):
            out.append(" ")                      # & that is part of a redirect (2>&1, &>f, <&0)
            i += 1; continue
        if c == "|":
            if i + 1 < n and s[i + 1] == "|":
                out.append(" ; "); i += 2; continue      # || is OR — a plain clause boundary
            if i + 1 < n and s[i + 1] == "&":
                out.append(" __pipe__ "); i += 2; continue   # |& pipes stdout+stderr
            out.append(" __pipe__ "); i += 1; continue   # a real pipe: the next clause reads
            # this clause's stdout as ITS stdin — judge() uses this to catch `echo … | bash`
        out.append(" ; " if c in "&;)\n\r" else c)   # stray ")" = malformed; split conservatively
        i += 1
    for body in extracted:
        out.append(" ; ")
        out.append(to_separators(body, depth + 1))
    return "".join(out)

# After the pre-pass every unquoted separator is a lone " ; " or " __pipe__ ", so these are the
# only clause-boundary tokens shlex can produce here (operator text inside quotes stays part of
# its value token). The pipe stays distinct because `echo "gh pr create …" | bash` EXECUTES the
# echoed text (17th review round) — judge() carries an echo/printf clause's payload across a
# pipe boundary and judges it when the receiving clause is a shell reading stdin (no -c).
OPS = {";", "__pipe__"}
# gh flags that consume the NEXT token as an opaque value; that value must never be read as an
# operator or a flag. -R/--repo are handled explicitly below (their value is what we inspect).
VALUE_FLAGS = {"-t","--title","-b","--body","-F","--body-file","-B","--base","-H","--head",
               "-l","--label","-a","--assignee","-r","--reviewer","-m","--milestone",
               "-p","--project","-T","--template","--recover"}

# Shell-wrapper basenames whose `-c <string>` argument is itself a command (15th review round:
# `bash -c "gh pr create …"` is an ORDINARY idiom, inside the accidental-omission threat model —
# and shlex collapsing the string to one opaque token had silently ALLOWED it, a regression vs
# the old raw-grep hook). Such strings are recursively judged as commands, as is everything
# after `eval` (which concatenates its args and executes them). Not covered: `ssh host "…"` /
# `su -c` (remote/privileged contexts our agents never route gh through — and the degraded grep
# below still catches those textually) and non-shell interpreters (`python -c 'os.system(…)'`,
# deliberate-evasion class).
SHELLS = {"bash", "sh", "zsh", "dash", "ksh"}
# Wrappers that keep the following word at command position (their own options/durations are
# skipped by the dash/numeric rules at the use site).
PREFIXES = {"sudo", "doas", "env", "nohup", "setsid", "command", "exec", "time", "xargs",
            "nice", "ionice", "stdbuf", "timeout", "strace", "ltrace"}

def judge(cmd, depth=0):
    # Returns True if any clause anywhere in cmd (including inside bash -c / eval strings) is an
    # untargeted `gh pr create`. Raises ValueError on unparseable input → caller falls back.
    if depth > 5:
        raise ValueError("wrapper nesting too deep")
    toks = shlex.split(to_separators(cmd))   # POSIX tokenization; unquoted newlines act as ";"
    deny = False
    gh = pr = create = targeted = False
    cmd_pos = True        # scanning the clause's COMMAND position (vs its arguments)
    printed = None        # args of the echo/printf clause just scanned (they were PRINTED)
    piped = None          # that payload, if the boundary we just crossed was a pipe
    i, n = 0, len(toks)
    while i < n:
        t = toks[i]
        if t in OPS:                     # clause boundary: judge the clause we just finished
            if gh and pr and create and not targeted:
                deny = True
            # an echo/printf payload only survives across a PIPE — `echo … | bash` feeds it to
            # the shell's stdin, while `echo …; bash` prints and moves on (17th review round)
            piped = printed if t == "__pipe__" else None
            printed = None
            gh = pr = create = targeted = False
            cmd_pos = True
            i += 1
            continue
        if cmd_pos:
            if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", t):
                i += 1; continue         # leading VAR=val assignment — still at command position
            base = t.rsplit("/", 1)[-1]
            # command-position-preserving prefixes and their option/duration arguments: after
            # `sudo`/`env`/`timeout 5`/`nice -n 10`/`xargs`/… the NEXT word is still the invoked
            # command
            if base in PREFIXES or re.match(r"^[0-9]+[smhd]?$", t):
                i += 1; continue
            if t.startswith("-"):
                # a prefix option may take a VALUE (`sudo -u root`, `xargs -I {}`): consume the
                # following plain word as that value so the wrapper AFTER it is still judged at
                # command position (20th review round: `sudo -u root bash -c "…"` bypassed the
                # wrapper check when `root` closed command position). The word is NOT consumed
                # when it is itself a shell/eval — a no-value option directly before the command
                # (`env -i bash -c "…"`) is likelier than a value named after a shell.
                nxt = toks[i + 1] if i + 1 < n and toks[i + 1] not in OPS else None
                if nxt and not nxt.startswith("-") and not re.match(r"^[0-9]+[smhd]?$", nxt) \
                   and nxt.rsplit("/", 1)[-1] not in SHELLS and nxt != "eval" \
                   and not re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", nxt):
                    i += 2; continue
                i += 1; continue
            cmd_pos = False
            # this token IS the clause's invoked command. Wrapper/print semantics apply ONLY
            # here: bash/eval/echo as a mere ARGUMENT (`grep eval -c "gh pr create test" f`,
            # `… | grep bash`) neither executes nor prints anything (19th review round — those
            # shapes were false-denied when wrappers matched anywhere in the clause).
            if base in ("echo", "printf"):
                # a print clause never EXECUTES its arguments — skip it whole, but REMEMBER
                # them: if this clause pipes into a stdin-reading shell, the printed text
                # becomes commands after all (16th/17th review rounds)
                args = []
                i += 1
                while i < n and toks[i] not in OPS:
                    args.append(toks[i]); i += 1
                printed = args
                continue
            if base in SHELLS:
                # scan this clause for -c (alone or in a cluster like -lc); its argument is a
                # command in its own right
                j = i + 1
                saw_c = False
                while j < n and toks[j] not in OPS:
                    f = toks[j]
                    if f.startswith("-") and not f.startswith("--") and "c" in f:
                        saw_c = True
                        if j + 1 < n and toks[j + 1] not in OPS and judge(toks[j + 1], depth + 1):
                            deny = True
                        break
                    j += 1
                # no -c: the shell reads stdin — if an echo/printf payload was piped in, judge
                # it (`cat file | bash` etc. remain unjudgeable: unknown content, degraded grep
                # only; multi-hop pipes like `echo … | tee f | bash` drop the payload — accepted)
                if not saw_c and piped:
                    if judge(" ".join(piped), depth + 1):
                        deny = True
                    piped = None
                # fall through: the shell token itself still walks the generic checks below
            if t == "eval":              # eval concatenates its args and executes them
                j = i + 1
                args = []
                while j < n and toks[j] not in OPS:
                    args.append(toks[j]); j += 1
                if args and judge(" ".join(args), depth + 1):
                    deny = True
                i = j                    # the args were judged in recursion, not in this walk
                continue
        elif t in ("-exec", "-execdir", "-ok"):
            cmd_pos = True               # find(1): the token after -exec is an invoked command
            i += 1
            continue
        if t == "gh" or t.endswith("/gh"):   # bare `gh` or a full/relative path like /usr/bin/gh
            gh = True
        elif t == "pr" and gh:
            pr = True
        elif t == "create" and pr:
            create = True
        # Each -R/--repo SETS the target verdict from its own value — last flag wins, matching gh's
        # repeated-flag semantics (a later -R greyhavens/... after -R claridtimo/... must UN-target).
        if t in ("-R", "--repo"):        # target flag; value is the next token
            if i + 1 < n and toks[i + 1] not in OPS:
                targeted = toks[i + 1].lower().startswith("claridtimo/")
                i += 2
            else:                        # dangling flag at a clause boundary: no value, and the
                targeted = False         # boundary token must still be processed (18th round)
                i += 1
            continue
        if t.startswith("-R=") or t.startswith("--repo="):
            targeted = t.split("=", 1)[1].lower().startswith("claridtimo/")
        elif t.startswith("-R") and len(t) > 2:   # -Rclaridtimo/… glued short form
            targeted = t[2:].lower().startswith("claridtimo/")
        if t in VALUE_FLAGS:             # next token is this flag's opaque value — skip it,
            # unless it is a clause boundary (a dangling value flag must not swallow the OPS
            # token — the clause-reset/deny-check there is what the state machine relies on)
            i += 2 if (i + 1 < n and toks[i + 1] not in OPS) else 1
            continue
        i += 1
    if gh and pr and create and not targeted:
        deny = True
    return deny

try:
    deny = judge(cmd)
except ValueError:
    print("FALLBACK"); sys.exit(0)   # unbalanced quotes / absurd nesting → degraded path decides
print("DENY" if deny else "ALLOW")
PY
)
  case "$verdict" in
    DENY)  emit_deny; exit 0 ;;
    ALLOW) exit 0 ;;
    *)     : ;;   # FALLBACK / empty (python crashed or missing) → degraded path below
  esac
fi

# ---- Degraded path: no python3, or the command couldn't be parsed — conservative -------------
# Deny only the clear-cut case: a `gh pr create` with no -R/--repo flag ADJACENT to a
# "claridtimo/" value anywhere in the input. The adjacency requirement matters: the hook stdin
# is the whole PreToolUse payload (cwd, transcript_path, …), so a bare "claridtimo/" substring
# test would false-ALLOW every bare create on a box whose checkout PATH contains "claridtimo"
# (10th review round) — and the degraded path exists precisely for such less-set-up boxes.
# Requiring the flag form still NEVER false-denies a targeted PR (every targeted create carries
# `-R claridtimo/…`, `-R=…`, `-Rclaridtimo/…`, or a --repo equivalent — all matched below).
#
# KNOWN, ACCEPTED under-blocks (12th review round) — this path prioritizes never-false-denying
# over completeness, and cannot have both without a real tokenizer:
#   - a flag-shaped `-R claridtimo/…` inside a quoted --title/--body satisfies the check;
#   - a real target on an UNRELATED chained clause (`gh pr view -R claridtimo/x; gh pr create`)
#     satisfies a bare create elsewhere in the same input.
# Clause-scoping this fallback with sed/grep was TRIED (the v2 hook that #61 merged) and
# reverted: without a quote-aware tokenizer, operators inside quoted PR bodies split clauses
# wrongly and false-denied real targeted creates — the exact bug class this rework removes.
# Both shapes are pinned in test-enforce-pr-target.sh (degraded-ALLOW vs precise-DENY) so a
# future change flipping either direction fails the battery. Every box we actually use has
# python3; this is a last-resort backstop, and `gh repo set-default` (bin/setup-gh-defaults)
# remains the primary guard.
# [Cc]laridtimo: GitHub owner names are case-insensitive (the precise path lowercases the whole
# value; here only the realistic accidental variant, a capitalized C, is matched — the flag part
# stays case-sensitive so -r/--reviewer values are not read as targets).
# SEP: a separator between tokens can be REAL whitespace or its JSON-ESCAPED form — the hook
# stdin is a JSON document, so a newline/tab inside the command arrives as the two characters
# \n / \t and a shell line-continuation backslash as \\ (16th review round: a backslash-
# continued `gh pr \<newline>create` must still match on exactly the boxes this fallback
# protects; the same class must count as flag/value adjacency or a continued targeted create
# would false-deny).
SEP='([[:space:]]|\\n|\\t|\\r|\\\\)'
# Scope the greps to the "command" FIELD when extractable: the payload also carries description/
# cwd/transcript_path, and a description that MENTIONS the intended target must not satisfy the
# check for a command that forgot the flag — nor should a description quoting `gh pr create`
# false-deny an unrelated command (18th review round). The ERE walks escaped chars inside the
# JSON string value; if extraction yields nothing (unexpected payload shape), fall back to the
# whole input, which errs toward DENY only for inputs that contain the create phrase anyway.
# (grep only — the degraded path must not depend on anything beyond bash/grep/printf/cat)
SCOPE=$(printf '%s' "$INPUT" | grep -oE '"command"[[:space:]]*:[[:space:]]*"(\\.|[^"\\])*"')
[ -n "$SCOPE" ] || SCOPE="$INPUT"
if printf '%s' "$SCOPE" | grep -qE "gh${SEP}+pr${SEP}+create" \
   && ! printf '%s' "$SCOPE" | grep -qE "(-R|--repo)(=|${SEP})*[Cc]laridtimo/"; then
  emit_deny
fi

exit 0

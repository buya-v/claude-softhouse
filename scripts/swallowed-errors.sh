#!/usr/bin/env bash
# Swallowed-error scan: list catch-all handlers a branch ADDS whose body only
# discards the error, turning a failure into an empty success. Softhouse runs it
# in STEP 5 next to the non-negotiables scan; any hit is a REJECTED verdict with
# tag `swallowed-error`, unless the handoff justifies that exact line.
#
# Why: the softfactory mongolbank-rates run wrapped every fetch in
# `except Exception: parsed = []`. A live 404 page became an empty list, served
# as HTTP 200 `[]`, indistinguishable from "no data yet", and review approved it.
#
# Flagged (added lines only; tests, comments and narrow handlers are ignored):
#   Python  `except:` / `except Exception[ as e]:` / `except BaseException:` whose
#           body is only pass, continue, return, return None/[]/{}/""/0/False,
#           or `x = []` / `x = {}` / `x = None`
#   JS/TS   an empty `catch {}`; a catch whose body is only `return`,
#           `return null|undefined|[]|{}`; `.catch(() => null|undefined|[]|{}|{})`
#           when its value is used (assigned, returned or awaited into a name)
#   Go      `if err != nil {` followed by `return nil` or `return nil, nil`
# A handler that logs, re-raises or records the error is not flagged.
#
# Install into the consuming project as scripts/ci/swallowed-errors.sh.
# Usage: scripts/ci/swallowed-errors.sh <base-ref> <branch>
# Prints `path:line: <handler>` per hit. Exit 0 = none, 1 = hits, 2 = usage.
set -euo pipefail

if [ $# -lt 2 ]; then
  sed -n '22,23p' "$0" >&2
  exit 2
fi

BASE="$1"; BRANCH="$2"
# An unresolvable ref made git fail (exit 128), which a caller could not tell from a
# scan result; it is a usage error, never a verdict.
for ref in "$BASE" "$BRANCH"; do
  git rev-parse --verify --quiet "${ref}^{commit}" >/dev/null || { echo "not a commit: $ref" >&2; exit 2; }
done
# Byte-wise awk: the patterns are ASCII, and macOS awk under a UTF-8 locale died
# (exit 2, "towc: multibyte conversion failure") on a diff carrying Cyrillic text.
git diff --unified=0 --no-color "$BASE...$BRANCH" | LC_ALL=C awk '
function is_test(p,   b) {
  if (p ~ /(^|\/)(tests?|__tests__)\//) return 1
  b = p; sub(/.*\//, "", b)
  return (b ~ /\.(test|spec)\./ || b ~ /^test_.*\.py$/ || b ~ /_test\.go$/)
}
function strip_comment(s, lang) {
  if (lang == "py") sub(/[[:space:]]*#.*$/, "", s)
  else sub(/[[:space:]]*\/\/.*$/, "", s)
  return s
}
function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
function indent_of(s,   t) { t = s; sub(/[^[:space:]].*$/, "", t); return length(t) }
function records(s) { return (s ~ /(log(ger|ging)?|console\.(error|warn|log)|warn(ing)?|raise|throw|panic|errors?\.|report|capture|sentry)/) }
function py_discard(s) {
  s = trim(strip_comment(s, "py"))
  if (s == "") return 2                     # blank: neutral
  if (s ~ /^(pass|continue)$/) return 1
  if (s ~ /^return$/) return 1
  if (s ~ /^return[[:space:]]+(None|\[[[:space:]]*\]|\{[[:space:]]*\}|""|'\'''\''|0|False)$/) return 1
  if (s ~ /^[A-Za-z_][A-Za-z0-9_.]*[[:space:]]*=[[:space:]]*(\[[[:space:]]*\]|\{[[:space:]]*\}|None)$/) return 1
  return 0
}
function js_discard(s) {
  s = trim(strip_comment(s, "js"))
  if (s == "" || s == "}") return 2
  if (s ~ /^return;?$/) return 1
  if (s ~ /^return[[:space:]]+(null|undefined|\[[[:space:]]*\]|\{[[:space:]]*\});?$/) return 1
  return 0
}
function hit(p, n, text) { printf "%s:%d: %s\n", p, n, trim(text); found = 1 }
function flush_py() {
  if (py_open && py_body > 0 && py_bad == 0) hit(py_path, py_line, py_text)
  py_open = 0
}
function flush_js() {
  if (js_open && js_bad == 0 && js_closed) hit(js_path, js_line, js_text)
  js_open = 0
}
BEGIN { found = 0 }
/^\+\+\+ / { flush_py(); flush_js(); path = substr($0, 5); sub(/^b\//, "", path); skip = (path == "/dev/null" || is_test(path)); next }
/^--- / { next }
/^@@ / { flush_py(); flush_js(); h = $0; sub(/^@@ -[0-9,]+ \+/, "", h); sub(/[, ].*$/, "", h); line = h + 0; next }
/^\+/ {
  if (skip) { line++; next }
  code = substr($0, 2)
  lang = ""
  if (path ~ /\.py$/) lang = "py"
  else if (path ~ /\.(js|jsx|ts|tsx|mjs|cjs)$/) lang = "js"
  else if (path ~ /\.go$/) lang = "go"
  t = trim(code)
  comment = (t ~ /^(#|\/\/|\/\*|\*)/)

  # A Python handler body: deeper-indented lines right after the handler.
  if (py_open) {
    if (line == py_next && (trim(code) == "" || indent_of(code) > py_indent)) {
      d = py_discard(code)
      if (d == 0 || records(code)) py_bad = 1
      if (d == 1) py_body++
      py_next = line + 1
      line++; next
    }
    flush_py()
  }
  if (js_open) {
    if (line == js_next) {
      if (t ~ /^}/) { js_closed = 1; flush_js() }
      else { d = js_discard(code); if (d == 0 || records(code)) js_bad = 1; js_next = line + 1; line++; next }
    } else flush_js()
  }
  if (go_open) {
    if (line == go_line + 1 && t ~ /^return[[:space:]]+nil([[:space:]]*,[[:space:]]*nil)?$/) hit(path, go_line, go_text)
    go_open = 0
  }
  if (comment || lang == "") { line++; next }

  if (lang == "py" && code ~ /^[[:space:]]*except([[:space:]]+(Exception|BaseException)([[:space:]]+as[[:space:]]+[A-Za-z_][A-Za-z0-9_]*)?)?[[:space:]]*:/) {
    rest = code; sub(/^[^:]*:/, "", rest)
    if (trim(strip_comment(rest, "py")) != "") { if (py_discard(rest) == 1) hit(path, line, code) }
    else { py_open = 1; py_path = path; py_line = line; py_text = code; py_indent = indent_of(code); py_next = line + 1; py_body = 0; py_bad = 0 }
  }
  if (lang == "js") {
    c = strip_comment(code, "js")
    if (c ~ /catch[[:space:]]*(\([^)]*\))?[[:space:]]*\{[[:space:]]*\}/) hit(path, line, code)
    else if (c ~ /catch[[:space:]]*(\([^)]*\))?[[:space:]]*\{[[:space:]]*return([[:space:]]+(null|undefined|\[[[:space:]]*\]|\{[[:space:]]*\}))?;?[[:space:]]*\}/) hit(path, line, code)
    else if (c ~ /catch[[:space:]]*(\([^)]*\))?[[:space:]]*\{[[:space:]]*$/) { js_open = 1; js_path = path; js_line = line; js_text = code; js_next = line + 1; js_bad = 0; js_closed = 0 }
    if (c ~ /\.catch\([[:space:]]*(\([^)]*\)|[A-Za-z_]+)[[:space:]]*=>[[:space:]]*(null|undefined|\[[[:space:]]*\]|\(?\{[[:space:]]*\}\)?)[[:space:]]*\)/ && c ~ /(=[^=>]|^[[:space:]]*return[[:space:]])/) hit(path, line, code)
  }
  if (lang == "go" && t ~ /^if[[:space:]]+err[[:space:]]*!=[[:space:]]*nil[[:space:]]*\{$/) { go_open = 1; go_line = line; go_text = code }
  line++
  next
}
END { flush_py(); flush_js(); exit found }
'

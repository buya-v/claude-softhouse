#!/usr/bin/env bash
# Secret scan: refuse a merge whose ADDED lines carry a credential, or that
# adds a secret file. Softhouse runs it in STEP 6 before every merge; a hit is
# a stop (tag `secret-in-diff`), never a micro-fix the orchestrator pushes past.
#
# Ported from softfactory 6.2.0. Its first version matched variable NAMES
# (`token = request.headers[...]`) and flagged code that only handles
# credentials; this matches VALUES: provider-shaped tokens anywhere, and
# credential-named assignments only when they hold a hard-coded literal that
# is not a placeholder. Nothing it prints contains the secret itself.
#
# Flagged:
#   secret files   .env, .env.* (not .env.example/.sample/.template), *.pem, *.key,
#                  id_rsa* (not .pub), *.p12, credentials.json
#   tokens         PEM private keys, sk-/sk-ant-/sk_live_ keys, GitHub gh?_/github_pat_,
#                  Slack xox?-, AWS AKIA/ASIA, Google AIza, JWTs, user:password@ in URLs
#   assignments    api_key / password / secret / token / private_key / access_key
#                  = "a literal of 8+ chars" (bare values too in .env/.sh/.yml/.ini/.toml);
#                  skipped in test and fixture files, and for placeholders
#                  (changeme, example, xxx, your-api-key, <...>, ${...}, one repeated char)
#
# Allow-list: .softhouse/secret-scan-allow.txt, one extended regex per line
# (# comments). A regex matching a path exempts that file; one matching a line
# skips that line. Keep fake tokens of your own redaction tests there.
#
# Install into the consuming project as scripts/ci/secret-scan.sh.
# Usage: scripts/ci/secret-scan.sh <base-ref> <branch>
# Prints `path:line: <kind>` per hit. Exit 0 = clean, 1 = hits, 2 = usage.
set -uo pipefail

if [ $# -lt 2 ]; then
  sed -n '27,28p' "$0" >&2
  exit 2
fi
BASE="$1"; BRANCH="$2"
ROOT="$(git rev-parse --show-toplevel)"
ALLOW_FILE="$ROOT/.softhouse/secret-scan-allow.txt"
allow=()
if [ -f "$ALLOW_FILE" ]; then
  while IFS= read -r entry; do
    case "$entry" in ''|'#'*) continue ;; esac
    allow+=("$entry")
  done < "$ALLOW_FILE"
fi
allowed() { local e; for e in ${allow[@]+"${allow[@]}"}; do [[ "$1" =~ $e ]] && return 0; done; return 1; }

found=0
report() { echo "$1:$2: $3"; found=1; }

secret_path() {
  local base="${1##*/}"
  case "$base" in
    .env) return 0 ;;
    .env.example|.env.sample|.env.template) return 1 ;;
    .env.*|*.pem|*.key|*.p12|credentials.json) return 0 ;;
    id_rsa*.pub) return 1 ;;
    id_rsa*) return 0 ;;
  esac
  return 1
}
is_fixture() { [[ "$1" =~ (^|/)(tests?|__tests__|spec|fixtures?|__fixtures__|testdata)/ || "$1" =~ [._](test|spec|fixture)\.[a-z0-9]+$ || "$1" =~ (^|/)test_[^/]*$ ]]; }
bare_literals() {
  local base; base="$(printf '%s' "${1##*/}" | tr '[:upper:]' '[:lower:]')"
  [[ "$base" == .env* || "$base" == dockerfile || "$base" =~ \.(env|ini|cfg|conf|properties|toml|ya?ml|sh|bash|zsh|npmrc|pypirc)$ ]]
}
placeholder() {
  local v; v="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr '_' '-')"
  case "$v" in xxx|your-api-key|changeme|example|'') return 0 ;; esac
  [[ "$1" =~ ^\<[^\>]+\>$ || "$1" == *'${'* || "$1" =~ ^(.)\1*$ ]]
}

CRED='(api[_-]?key|apikey|password|passwd|secret|secret[_-]?key|token|private[_-]?key|access[_-]?key)'
scan_line() {
  local path="$1" n="$2" text="$3" fixture="$4" bare="$5"
  [[ "$text" =~ -----BEGIN\ ([A-Z]+\ )?PRIVATE\ KEY----- ]] && report "$path" "$n" "PEM private key"
  [[ "$text" =~ sk-ant-[A-Za-z0-9_-]{20,} ]] && report "$path" "$n" "Anthropic key"
  [[ "$text" =~ (sk-(proj-)?[A-Za-z0-9]{20,}|(sk|rk)_live_[0-9A-Za-z]{16,}) && ! "$text" =~ sk-ant- ]] && report "$path" "$n" "OpenAI/Stripe key"
  [[ "$text" =~ (gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{40,}) ]] && report "$path" "$n" "GitHub token"
  [[ "$text" =~ xox[abposr]-[A-Za-z0-9-]{10,} ]] && report "$path" "$n" "Slack token"
  [[ "$text" =~ (AKIA|ASIA)[0-9A-Z]{16} ]] && report "$path" "$n" "AWS access key"
  [[ "$text" =~ AIza[0-9A-Za-z_-]{35} ]] && report "$path" "$n" "Google API key"
  [[ "$text" =~ eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,} ]] && report "$path" "$n" "JWT"
  if [[ "$text" =~ [a-zA-Z][a-zA-Z0-9+.-]*://[^/[:space:]:@]+:([^/[:space:]:@]+)@ ]] && ! placeholder "${BASH_REMATCH[1]}"; then report "$path" "$n" "URL credential"; fi
  [ "$fixture" = 1 ] && return
  local lower value
  lower="$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]')"
  if [[ "$lower" =~ $CRED[a-z0-9_-]*[\"\']?[[:space:]]*[:=][[:space:]]*(.*)$ ]]; then
    value="${BASH_REMATCH[${#BASH_REMATCH[@]}-1]}"
    # Read the value from the original text at the same offset, so case is kept.
    value="${text: ${#text}-${#value}}"
    value="${value#Bearer }"
    if [[ "$value" =~ ^[\"\'\`]([^\"\'\`]*)[\"\'\`] ]]; then value="${BASH_REMATCH[1]}"
    elif [ "$bare" = 1 ] && [[ "$value" =~ ^([^[:space:],\;\"\'\`]+) ]]; then
      value="${BASH_REMATCH[1]}"
      # An expression or an environment lookup is not a literal.
      if [[ "$value" =~ [\(\)\[\]\{\}\$] || "$value" =~ ^(process\.env|os\.environ|env\.|getenv) ]]; then return; fi
    else return; fi
    if [ "${#value}" -ge 8 ] && [[ ! "$value" =~ [[:space:]] ]] && ! placeholder "$value"; then report "$path" "$n" "Generic assignment"; fi
  fi
}

path=""; n=0; skip=0; fixture=0; bare=0; flagged_path=""
while IFS= read -r raw; do
  case "$raw" in
    '+++ '*)
      path="${raw#+++ }"; path="${path#b/}"
      skip=0; fixture=0; bare=0
      if [ "$path" = /dev/null ] || allowed "$path"; then skip=1; continue; fi
      is_fixture "$path" && fixture=1
      bare_literals "$path" && bare=1
      if secret_path "$path"; then report "$path" 1 "Secret file path"; skip=1; fi
      continue ;;
    '--- '*) continue ;;
    '@@ '*) n="${raw#@@ -* +}"; n="${n%%[, ]*}"; continue ;;
    '+'*)
      if [ "$skip" = 0 ]; then
        text="${raw#+}"
        allowed "$text" || scan_line "$path" "$n" "$text" "$fixture" "$bare"
      fi
      n=$((n + 1)) ;;
  esac
done < <(git -C "$ROOT" diff --unified=0 --no-color "$BASE...$BRANCH")

exit $found

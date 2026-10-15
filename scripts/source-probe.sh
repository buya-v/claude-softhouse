#!/usr/bin/env bash
# Source probe: fetch ONE outside address a plan depends on, once, and say
# whether it answers the way the plan assumes. Softhouse runs it in STEP 2 for
# every entry in tasks.json `external_sources`, before any worker launches.
#
# Why: a softfactory run on mongolbank-rates planned against
# https://www.mongolbank.mn/en/rates, which answers HTTP 200 with a
# "404 - Page Not Found" page. Seven tasks were built and merged against it and
# 127 tests passed on invented fixtures. A plan is only as good as the
# addresses it calls, so a bad source rejects the plan instead of the run.
#
# Install into the consuming project as scripts/ci/source-probe.sh.
#
# Usage:
#   scripts/ci/source-probe.sh <name> <url> [GET|POST] [json|html|xml|csv|any] [save-to]
#     POST sends no body: put parameters in the URL's query string, as the
#     plan lists them. <save-to> receives the response body when the probe is
#     OK (the orchestrator commits it as tests/fixtures/sources/<name>.<ext>).
#
# Prints one line: `OK <name> <status> <content-type> <bytes>B` or
# `NOT OK <name>: <problem>`. Exit 0 = OK, 1 = not OK, 2 = usage error.
#
# Checks, in order: a response arrived (20 s ceiling); HTTP 2xx; a soft 404
# (the page's own <title> or first <h1> says "404" or "not found"); the shape
# the plan promised (json/html/xml/csv); for JSON, that it parses and does not
# report `"success": false` or a non-empty top-level `"error"`. JSON checks use
# python3 when present; without it the shape check falls back to the first byte.
set -uo pipefail

if [ $# -lt 2 ]; then
  sed -n '14,19p' "$0" >&2
  exit 2
fi
NAME="$1"; URL="$2"; METHOD="$(printf '%s' "${3:-GET}" | tr '[:lower:]' '[:upper:]')"; EXPECT="$(printf '%s' "${4:-any}" | tr '[:upper:]' '[:lower:]')"; SAVE="${5:-}"
case "$METHOD" in GET|POST) ;; *) echo "NOT OK $NAME: method must be GET or POST, got $METHOD" ; exit 2 ;; esac
case "$EXPECT" in json|html|xml|csv|any) ;; *) EXPECT=any ;; esac
case "$URL" in http://*|https://*) ;; *) echo "NOT OK $NAME: not a usable URL: $URL"; exit 1 ;; esac

BODY="$(mktemp "${TMPDIR:-/tmp}/source-probe.XXXXXX")"
ERR="$(mktemp "${TMPDIR:-/tmp}/source-probe-err.XXXXXX")"
trap 'rm -f "$BODY" "$ERR"' EXIT

meta="$(curl -sS -L -X "$METHOD" --max-time 20 --max-filesize 20000000 -o "$BODY" -w '%{http_code}\t%{content_type}' "$URL" 2>"$ERR")"
rc=$?
if [ $rc -ne 0 ]; then
  if [ $rc -eq 28 ]; then echo "NOT OK $NAME: request timed out after 20s (no response from the source)"
  else echo "NOT OK $NAME: request failed: $(sed 's/^curl: ([0-9]*) //' "$ERR" | tail -1 | cut -c1-200)"; fi
  exit 1
fi
STATUS="${meta%%$'\t'*}"; CTYPE="${meta#*$'\t'}"
BYTES="$(wc -c < "$BODY" | tr -d ' ')"
lower_ct="$(printf '%s' "$CTYPE" | tr '[:upper:]' '[:lower:]')"
fail() { echo "NOT OK $NAME: $1"; exit 1; }

case "$STATUS" in 2??) ;; *) fail "HTTP $STATUS" ;; esac

# The first non-blank byte (after a UTF-8 BOM) helps decide the kind.
first="$(head -c 4000 "$BODY" | perl -0777 -ne 's/^\xEF\xBB\xBF//; s/^\s+//; print substr($_, 0, 1)')"
looks_html=0
if [[ "$lower_ct" == *html* ]] || LC_ALL=C grep -qiE '<html[[:space:]>]|<!doctype html|<title[[:space:]>]|<h1[[:space:]>]' "$BODY"; then looks_html=1; fi

if [ $looks_html -eq 1 ]; then
  # A soft 404: the page's own title or first heading says it was not found.
  while IFS= read -r text; do
    if [ -n "$text" ] && printf '%s' "$text" | LC_ALL=C grep -qiE '(^|[^0-9])404([^0-9]|$)|not found'; then
      fail "soft 404: the page says \"$(printf '%s' "$text" | cut -c1-120)\""
    fi
  done < <(perl -0777 -ne 'for my $t ("title", "h1") { if (/<$t\b[^>]*>(.*?)<\/$t>/is) { (my $x = $1) =~ s/<[^>]*>/ /g; $x =~ s/\s+/ /g; $x =~ s/^ | $//g; print "$x\n" } }' "$BODY")
  case "$EXPECT" in any|html) ;; *) fail "expected $EXPECT, got HTML (${CTYPE:-no content type})" ;; esac
  [ "$BYTES" -ge 200 ] || fail "HTML body is only ${BYTES} bytes, under the 200-byte minimum"
else
  case "$EXPECT" in
    json) [[ "$lower_ct" == *json* || "$first" == "{" || "$first" == "[" ]] || fail "expected json, got ${CTYPE:-no content type}" ;;
    xml)  [[ "$lower_ct" == *xml* || "$first" == "<" ]] || fail "expected xml, got ${CTYPE:-no content type}" ;;
    csv)  [[ "$lower_ct" == *csv* ]] || { [ "$(grep -c . "$BODY")" -ge 2 ] && head -1 "$BODY" | grep -q ','; } || fail "expected csv, got ${CTYPE:-no content type}" ;;
    html) fail "expected html, got ${CTYPE:-no content type}" ;;
  esac
  if [[ "$EXPECT" == json || "$lower_ct" == *json* || "$first" == "{" || "$first" == "[" ]] && command -v python3 >/dev/null 2>&1; then
    problem="$(python3 -I -c '
import json, sys
try:
    data = json.load(open(sys.argv[1], encoding="utf-8-sig"))
except Exception as error:
    print("unparsable:" + str(error)[:120]); sys.exit()
if isinstance(data, dict):
    if data.get("success") is False:
        print("JSON body reports success: false"); sys.exit()
    error = data.get("error")
    if error not in (None, False, "", {}, []):
        print("JSON body has a top-level \"error\"")
' "$BODY")"
    case "$problem" in
      unparsable:*) [ "$EXPECT" = json ] && fail "expected JSON, but the body did not parse: ${problem#unparsable:}" ;;
      ?*) fail "$problem" ;;
    esac
  fi
fi

if [ -n "$SAVE" ]; then mkdir -p "$(dirname "$SAVE")" && cp "$BODY" "$SAVE"; fi
echo "OK $NAME $STATUS ${CTYPE:-no-content-type} ${BYTES}B"

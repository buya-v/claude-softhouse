#!/usr/bin/env bash
# Tests for the scripts/ helpers. No network: the source probe runs against a
# local server that serves the real shapes the Bank of Mongolia site returned
# (2026-10-13): the JSON rates endpoint, its `success: false` empty result, and
# the soft 404 page that a softfactory plan built seven tasks against.
#
# Usage: scripts/tests/run.sh        (needs bash, git, curl, perl, python3)
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/softhouse-tests.XXXXXX")"
pass=0; fail=0
cleanup() { if [ -n "${SERVER_PID:-}" ]; then kill "$SERVER_PID" 2>/dev/null; wait "$SERVER_PID" 2>/dev/null; fi; rm -rf "$WORK"; }
trap cleanup EXIT

check() { # check <description> <expected-exit> <expected-output-regex|-> <command...>
  local what="$1" want="$2" rx="$3"; shift 3
  local out rc
  out="$("$@" 2>&1)"; rc=$?
  if [ "$rc" = "$want" ] && { [ "$rx" = - ] || printf '%s' "$out" | grep -Eq -- "$rx"; }; then
    pass=$((pass + 1)); echo "ok   $what"
  else
    fail=$((fail + 1)); echo "FAIL $what (exit $rc, want $want)"; printf '%s\n' "$out" | sed 's/^/     | /' | head -15
  fi
}
absent() { # absent <description> <regex> <command...>: exits any way, output must not match
  local what="$1" rx="$2"; shift 2
  local out; out="$("$@" 2>&1)"
  if printf '%s' "$out" | grep -Eq -- "$rx"; then fail=$((fail + 1)); echo "FAIL $what (matched /$rx/)"; printf '%s\n' "$out" | sed 's/^/     | /' | head -15
  else pass=$((pass + 1)); echo "ok   $what"; fi
}
repo() { # a fresh repo with main, then branch `work`
  local dir="$WORK/repo-$RANDOM$RANDOM"
  mkdir -p "$dir" && git -C "$dir" init -q -b main && git -C "$dir" config user.email t@t && git -C "$dir" config user.name t
  echo x > "$dir/README" && git -C "$dir" add . && git -C "$dir" commit -qm init && git -C "$dir" checkout -qb work
  echo "$dir"
}
commit_all() { git -C "$1" add -f . && git -C "$1" commit -qm work; }

# ---------------------------------------------------------------- source-probe
PORT=$(( 20000 + RANDOM % 20000 ))
cat > "$WORK/server.py" <<'EOF'
import http.server, json, sys
SOFT_404 = "<!DOCTYPE html><html><head><title>404 - Page Not Found</title></head><body>" + "x" * 300 + "</body></html>"
RATES = json.dumps({"success": True, "data": [{"RATE_DATE": "2026-10-12", "USD": "3,595.47", "PLN": None}]})
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def send(self, code, ctype, body):
        data = body.encode()
        self.send_response(code); self.send_header("content-type", ctype); self.send_header("content-length", str(len(data))); self.end_headers(); self.wfile.write(data)
    def do_POST(self):
        if self.path.startswith("/en/currency-rates/data?startDate=2030"):
            return self.send(200, "application/json", json.dumps({"success": False, "data": "Тохирох үр дүн олдсонгүй."}))
        if self.path.startswith("/en/currency-rates/data"):
            return self.send(200, "application/json; charset=utf-8", RATES)
        self.send(405, "text/plain", "method not allowed")
    def do_GET(self):
        routes = {
            "/en/rates": (200, "text/html; charset=utf-8", SOFT_404),
            "/en/currency-rates": (200, "text/html", "<html><head><title>Currency rates</title></head><body>" + "y" * 300 + "</body></html>"),
            "/api/error": (200, "application/json", json.dumps({"error": "rate limit"})),
            "/api/ok-null-error": (200, "application/json", json.dumps({"error": None, "items": [1]})),
            "/api/broken": (200, "application/json", "{not json"),
            "/gone": (404, "text/plain", "gone"),
        }
        self.send(*routes.get(self.path.split("?")[0], (404, "text/plain", "no route")))
http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
EOF
python3 "$WORK/server.py" "$PORT" & SERVER_PID=$!
for _ in $(seq 50); do curl -s -o /dev/null "http://127.0.0.1:$PORT/gone" && break; sleep 0.1; done
B="http://127.0.0.1:$PORT"
SP="$HERE/source-probe.sh"
check "probe: a real JSON endpoint by POST is OK and saved" 0 '^OK rates 200 application/json' "$SP" rates "$B/en/currency-rates/data?startDate=2026-10-01&endDate=2026-10-12" POST json "$WORK/saved/rates.json"
check "probe: the saved body is the real response" 0 '3,595.47' cat "$WORK/saved/rates.json"
check "probe: the mongolbank soft 404 (HTTP 200) is NOT OK" 1 'soft 404: the page says "404 - Page Not Found"' "$SP" old "$B/en/rates" GET html
check "probe: success:false is NOT OK" 1 'success: false' "$SP" empty "$B/en/currency-rates/data?startDate=2030-01-01&endDate=2030-01-02" POST json
check "probe: HTML where JSON was promised is NOT OK" 1 'expected json, got HTML' "$SP" page "$B/en/currency-rates" GET json
check "probe: an HTML page is OK when HTML was promised" 0 '^OK page 200' "$SP" page "$B/en/currency-rates" GET html
check "probe: a non-empty top-level error is NOT OK" 1 'top-level "error"' "$SP" err "$B/api/error" GET json
check "probe: \"error\": null is fine" 0 '^OK' "$SP" nullerr "$B/api/ok-null-error" GET json
check "probe: unparsable JSON is NOT OK" 1 'did not parse' "$SP" broken "$B/api/broken" GET json
check "probe: HTTP 404 is NOT OK" 1 'HTTP 404' "$SP" gone "$B/gone" GET any
check "probe: a GET to a POST-only endpoint is NOT OK" 1 'HTTP 404' "$SP" get "$B/en/currency-rates/data?startDate=2026-10-01" GET json
check "probe: no response is NOT OK" 1 'request failed' "$SP" down "http://127.0.0.1:1/x" GET any
check "probe: not a URL" 1 'not a usable URL' "$SP" bad "ftp://x" GET any
check "probe: usage" 2 - "$SP" only-a-name
[ -f "$WORK/saved/never.json" ] && { fail=$((fail + 1)); echo "FAIL probe: a NOT OK source is not saved"; } || true
"$SP" never "$B/en/rates" GET json "$WORK/saved/never.json" >/dev/null 2>&1
[ -f "$WORK/saved/never.json" ] && { fail=$((fail + 1)); echo "FAIL probe: a NOT OK source must not be saved"; } || { pass=$((pass + 1)); echo "ok   probe: a NOT OK source is not saved"; }

# ---------------------------------------------------------- fixture-provenance
R="$(repo)"
mkdir -p "$R/tests/fixtures/sources" && echo '{"success":true}' > "$R/tests/fixtures/sources/rates.json"
git -C "$R" checkout -q main && git -C "$R" merge -q work 2>/dev/null; git -C "$R" add -f . && git -C "$R" commit -qm "probe: rates" && git -C "$R" checkout -qb task
mkdir -p "$R/tests/fixtures" "$R/app" && echo '{"invented":1}' > "$R/tests/fixtures/mongolbank_sample.json" && echo 'x' > "$R/app/a.py" && echo 'def test(): pass' > "$R/tests/test_a.py"
commit_all "$R"
FP="$HERE/fixture-provenance.sh"
check "fixtures: a worker-written fixture beside a probed source is flagged" 1 'tests/fixtures/mongolbank_sample.json' bash -c "cd '$R' && '$FP' main task tests/fixtures/sources/rates.json"
absent "fixtures: code and test files are not flagged" 'app/a.py|test_a.py' bash -c "cd '$R' && '$FP' main task tests/fixtures/sources/rates.json"
git -C "$R" rm -q tests/fixtures/mongolbank_sample.json && git -C "$R" commit -qm rm
check "fixtures: reading the saved response only is clean" 0 - bash -c "cd '$R' && '$FP' main task tests/fixtures/sources/rates.json"
mkdir -p "$R/internal/x/testdata" && echo '{"golden":1}' > "$R/internal/x/testdata/golden.json" && commit_all "$R"
check "fixtures: an undeclared local data file is flagged" 1 'internal/x/testdata/golden.json' bash -c "cd '$R' && '$FP' main task tests/fixtures/sources/rates.json"
check "fixtures: a declared local fixture (--allow) passes" 0 - bash -c "cd '$R' && '$FP' main task --allow internal/x/testdata/golden.json tests/fixtures/sources/rates.json"
echo '{"golden":2}' > "$R/internal/x/testdata/second.json" && commit_all "$R"
check "fixtures: two local fixtures need one --allow each" 0 - bash -c "cd '$R' && '$FP' main task --allow internal/x/testdata/golden.json --allow internal/x/testdata/second.json tests/fixtures/sources/rates.json"
check "fixtures: --allow without a path is a usage error" 2 - bash -c "cd '$R' && '$FP' main task --allow"
echo '{"edited":1}' > "$R/tests/fixtures/sources/rates.json" && commit_all "$R"
check "fixtures: editing a saved response is flagged" 1 'a saved response' bash -c "cd '$R' && '$FP' main task tests/fixtures/sources/rates.json"

# ------------------------------------------------------------- swallowed-errors
R="$(repo)"
mkdir -p "$R/app" "$R/web" "$R/tests"
cat > "$R/app/fetch.py" <<'EOF'
def latest():
    try:
        parsed = get()
    except Exception:
        parsed = []
    try:
        x = get()
    except Exception as e:
        log.error("fetch failed: %s", e)
        raise
    try:
        y = 1
    except ValueError:
        pass
    try:
        z = 2
    except: pass
    # except Exception: pass
EOF
cat > "$R/web/a.ts" <<'EOF'
export async function f() {
  try { await g(); } catch {}
  try { await g(); } catch (e) { console.error(e); }
  const rows = await load().catch(() => []);
  load().catch(() => {});
  try {
    await g();
  } catch (err) {
    return null;
  }
}
EOF
printf 'func h() error {\n\tif err != nil {\n\t\treturn nil\n\t}\n\tif err != nil {\n\t\treturn fmt.Errorf("x: %%w", err)\n\t}\n}\n' > "$R/app/x.go"
printf 'def test_x():\n    try:\n        a()\n    except Exception:\n        pass\n' > "$R/tests/test_a.py"
commit_all "$R"
SE="$HERE/swallowed-errors.sh"
for want in 'app/fetch.py:4: except Exception:' 'app/fetch.py:17: except: pass' 'web/a.ts:2: ' 'web/a.ts:4: ' 'web/a.ts:8: ' 'app/x.go:2: '; do
  check "swallowed: flags $want" 1 "$want" bash -c "cd '$R' && '$SE' main work"
done
for not in 'fetch.py:8' 'fetch.py:13' 'fetch.py:18' 'a.ts:3' 'a.ts:5' 'x.go:5' 'test_a.py'; do
  absent "swallowed: leaves $not alone" "$not" bash -c "cd '$R' && '$SE' main work"
done
R2="$(repo)"; echo 'print(1)' > "$R2/a.py"; commit_all "$R2"
check "swallowed: a clean diff exits 0" 0 - bash -c "cd '$R2' && '$SE' main work"

# ------------------------------------------------------------------ secret-scan
R="$(repo)"
mkdir -p "$R/app" "$R/tests"
cat > "$R/app/config.py" <<'EOF'
API_KEY = "Zx81mQp2Lr7Vb4Nc"
token = request.headers.get("Authorization")
password = os.environ["DB_PASSWORD"]
secret = "changeme"
aws = "AKIAIOSFODNN7EXAMPLE"
DATABASE_URL = "postgres://admin:hunter2pass@db:5432/app"
DATABASE_URL2 = "postgres://admin:${DB_PASS}@db:5432/app"
github = "ghp_abcdefghijklmnopqrstuvwxyz0123456789AB"
EOF
printf 'API_TOKEN=Qm93ZXJ0eTEyMzQ1Njc4\nMODE=prod\nDB_PASSWORD=${DB_PASSWORD}\n' > "$R/deploy.env"
printf 'api_key = "Zx81mQp2Lr7Vb4Nc"\n' > "$R/tests/test_cfg.py"
echo "SECRET=1" > "$R/.env"; printf 'TOKEN=example\n' > "$R/.env.example"
commit_all "$R"
SS="$HERE/secret-scan.sh"
for want in 'app/config.py:1: Generic assignment' 'app/config.py:5: AWS access key' 'app/config.py:6: URL credential' 'app/config.py:8: GitHub token' 'deploy.env:1: Generic assignment' '^\.env:1: Secret file path'; do
  check "secrets: flags $want" 1 "$want" bash -c "cd '$R' && '$SS' main work"
done
for not in 'config.py:[2347]:' 'deploy.env:[23]:' 'test_cfg.py' 'env.example' 'Zx81|hunter2|AKIAIOS|ghp_'; do
  absent "secrets: does not report $not" "$not" bash -c "cd '$R' && '$SS' main work"
done
mkdir -p "$R/tests/fixtures/sources" && printf '<script>key="AIzaSyA1234567890abcdefghijklmnopqrstuv"</script>\n' > "$R/tests/fixtures/sources/page.html" && commit_all "$R"
check "secrets: an unlisted file under fixtures/sources is still scanned" 1 'fixtures/sources/page.html:1: Google API key' bash -c "cd '$R' && '$SS' main work"
absent "secrets: a --skip saved response is not scanned" 'fixtures/sources' bash -c "cd '$R' && '$SS' main work --skip tests/fixtures/sources/page.html"
check "secrets: --skip without a path is a usage error" 2 - bash -c "cd '$R' && '$SS' main work --skip"
mkdir -p "$R/.softhouse" && echo '^app/config\.py$' > "$R/.softhouse/secret-scan-allow.txt"
absent "secrets: an allow-listed path is exempt" 'app/config.py' bash -c "cd '$R' && '$SS' main work"

# ------------------------------------------------------------------- uat-setup
R="$(repo)"
US="$HERE/uat-setup.sh"
start=$(date +%s)
check "uat: start returns while a server it backgrounded (no redirect) keeps running" 0 'started' bash -c "cd '$R' && '$US' start 'sleep 300 & echo \$! > bg.pid; echo started'"
[ $(( $(date +%s) - start )) -lt 10 ] && { pass=$((pass + 1)); echo "ok   uat: start did not wait for the background child"; } || { fail=$((fail + 1)); echo "FAIL uat: start waited for the background child"; }
bgpid="$(cat "$R/bg.pid")"
kill -0 "$bgpid" 2>/dev/null && { pass=$((pass + 1)); echo "ok   uat: the server is up after start"; } || { fail=$((fail + 1)); echo "FAIL uat: the server died with start"; }
check "uat: stop ends the group" 0 'stopped 1 background' bash -c "cd '$R' && '$US' stop"
sleep 0.3; kill -0 "$bgpid" 2>/dev/null && { fail=$((fail + 1)); echo "FAIL uat: the server survived stop"; kill "$bgpid"; } || { pass=$((pass + 1)); echo "ok   uat: the server is gone after stop"; }
check "uat: a failing setup step reports its exit code" 3 'boom' bash -c "cd '$R' && '$US' start 'echo boom; exit 3'"
check "uat: stop after a step that left nothing" 0 'stopped 0' bash -c "cd '$R' && '$US' stop"
check "uat: a process ignoring SIGTERM is SIGKILLed" 0 'stopped 1' bash -c "cd '$R' && '$US' start 'sh -c \"trap \\\"\\\" TERM; sleep 300\" & echo \$! > bg2.pid' >/dev/null && '$US' stop"
sleep 0.3; kill -0 "$(cat "$R/bg2.pid")" 2>/dev/null && { fail=$((fail + 1)); echo "FAIL uat: the TERM-ignoring process survived"; kill -9 "$(cat "$R/bg2.pid")"; } || { pass=$((pass + 1)); echo "ok   uat: the TERM-ignoring process is gone"; }
check "uat: the run state is git-ignored" 0 '^\*$' cat "$R/.softhouse/uat-run/.gitignore"
check "uat: port-free on a free port" 0 'is free' "$US" port-free 1
check "uat: port-free names the holder of a busy port" 1 "port $PORT is held by" "$US" port-free "$PORT"
check "uat: venv is skipped for a non-Python project" 0 'not a Python project' bash -c "cd '$R' && '$US' venv"
: > "$R/requirements.txt"
check "uat: a Python project gets its own venv" 0 'dependencies installed in .*/\.softhouse/uat-venv' bash -c "cd '$R' && '$US' venv"
check "uat: run uses the venv's python" 0 '\.softhouse/uat-venv$' bash -c "cd '$R' && '$US' run 'python3 -c \"import sys; print(sys.prefix)\"'"
check "uat: start uses the venv's python too" 0 '\.softhouse/uat-venv$' bash -c "cd '$R' && '$US' start 'python3 -c \"import sys; print(sys.prefix)\"' && '$US' stop >/dev/null"
check "uat: the venv is git-ignored" 0 '^\*$' cat "$R/.softhouse/uat-venv/.gitignore"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]

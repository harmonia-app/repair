#!/usr/bin/env bash
# THE FAILING-CHECK DOOR (HAR-11): a red job in your workflow opens a
# Fix on your own seat; proven, it lands as a draft pull request.
#
#   - uses: harmonia-app/repair@v1
#     if: failure()
#     with: { key: ${{ secrets.HARMONIA_KEY }}, check: "python -m pytest -q" }
#
# Zero code in your product, one yaml line, one secret. The failing
# check IS the contract: the same command, run in a clean sandbox at
# this commit, must exit 0 for the fix to count. Nothing merges itself.
#
# THE PULL REQUEST'S HEAD (HAR-119, found live 2026-09-08 on PR 54): on a
# pull_request run GITHUB_SHA is the merge commit GitHub made for the
# run, not the commit that went red — so the fix is stood on the pull
# request's head (from the event file) and delivered onto the pull
# request's own branch; a push run keeps GITHUB_SHA.
set -euo pipefail
: "${HARMONIA_KEY:?the key — with: key: \${{ secrets.HARMONIA_KEY }}}"
: "${REPAIR_CHECK:?the check — with: check: \"python -m pytest -q\"}"
SERVICE="${HARMONIA_SERVICE:-https://api.harmonia.build}"
REPO="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY}"
SHA="${GITHUB_SHA:?GITHUB_SHA}"
JOB="${GITHUB_JOB:-job}"
WORKFLOW="${GITHUB_WORKFLOW:-workflow}"
RUN_URL="${GITHUB_SERVER_URL:-https://github.com}/${REPO}/actions/runs/${GITHUB_RUN_ID:-0}"
LOG="${REPAIR_LOG:-}"
if [ -n "$LOG" ] && [ -f "$LOG" ]; then LOG="$(tail -c 4000 "$LOG")"; fi
RAIL="${REPAIR_RAIL:-}"
export SERVICE REPO SHA JOB WORKFLOW RUN_URL LOG RAIL

body=$(python3 - <<'PY'
import json, os
sha, branch = os.environ["SHA"], ""
event_path = os.environ.get("GITHUB_EVENT_PATH") or ""
if event_path and os.path.isfile(event_path):
    # a pull_request run: the head that went red and the branch it is on
    try:
        with open(event_path) as fh:
            event = json.load(fh)
    except (OSError, ValueError):
        event = {}
    head = ((event.get("pull_request") or {}).get("head") or {}) if isinstance(event, dict) else {}
    if isinstance(head, dict) and head.get("sha"):
        sha, branch = str(head["sha"]), str(head.get("ref") or "")
print(json.dumps({
    "ask": "",
    "repo": os.environ["REPO"], "ref": sha, "base_branch": branch,
    "check": os.environ["REPAIR_CHECK"],
    "setup": os.environ.get("REPAIR_SETUP") or "",
    "deliver": "draft_pr",
    "rail": os.environ.get("RAIL") or "",
    "situation": {"kind": "ci",
                  "title": f"{os.environ['JOB']} went red on {sha[:7]}",
                  "check": os.environ["REPAIR_CHECK"],
                  "message": (os.environ.get("LOG") or "")[-4000:],
                  "environment": os.environ["WORKFLOW"],
                  "url": os.environ["RUN_URL"]}}))
PY
)
reply=$(curl -sS --max-time 120 -X POST "$SERVICE/v1/build" \
  -H "Authorization: Bearer $HARMONIA_KEY" -H "Content-Type: application/json" \
  --data "$body") || { echo "::error::the service could not be reached at $SERVICE"; exit 1; }
run=$(printf '%s' "$reply" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("build",{}).get("run_id") or "")')
if [ -z "$run" ]; then
  echo "::error::$(printf '%s' "$reply" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("error") or d)')"
  exit 1
fi
framed=$(printf '%s' "$reply" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("build",{}).get("framed") or "")')
echo "harmonia · $run · $framed"
echo "run=$run" >> "${GITHUB_OUTPUT:-/dev/null}"
# THE RUNNER RAIL: this job's own machine serves the attempts and the
# checks — nothing on Harmonia's metal — until the fix settles
runner_pid=""
if [ "$RAIL" = "runner" ]; then
  HARMONIA_RUN="$run" HARMONIA_RUNNER_LABEL="$WORKFLOW/$JOB" \
    HARMONIA_RUNNER_MINUTES="${REPAIR_TIMEOUT_MINUTES:-20}" \
    python3 "$(dirname "$0")/runner.py" &
  runner_pid=$!
  echo "rail · your runner · $run"
fi
if [ "${REPAIR_WAIT:-true}" != "true" ] && [ -z "$runner_pid" ]; then
  echo "stands=Working" >> "${GITHUB_OUTPUT:-/dev/null}"
  exit 0
fi
deadline=$(( $(date +%s) + ${REPAIR_TIMEOUT_MINUTES:-20} * 60 ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  view=$(curl -sS --max-time 60 "$SERVICE/v1/build/$run" -H "Authorization: Bearer $HARMONIA_KEY") || view='{}'
  status=$(printf '%s' "$view" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("status") or "")')
  if [ "$status" = "completed" ] || [ "$status" = "failed" ] || [ "$status" = "stopped" ] || [ "$status" = "interrupted" ]; then
    word=$(printf '%s' "$view" | python3 -c '
import json,sys; d=json.load(sys.stdin)
s=d.get("status"); p=(d.get("proof_word") or "").lower()
print("Proven" if p=="proven" else "Checked" if p=="checked" or (s=="completed" and d.get("outcome")=="checks green") else "Report")')
    echo "stands=$word" >> "${GITHUB_OUTPUT:-/dev/null}"
    # the delivery is the service's, the moment the proof seals; a short wait for it
    for _ in $(seq 1 24); do
      pr=$(printf '%s' "$view" | python3 -c 'import json,sys; d=json.load(sys.stdin); print((d.get("pull_request") or {}).get("url") or "")')
      [ -n "$pr" ] && break
      sleep 5
      view=$(curl -sS --max-time 60 "$SERVICE/v1/build/$run" -H "Authorization: Bearer $HARMONIA_KEY") || view='{}'
    done
    if [ -n "$pr" ]; then
      echo "pull-request=$pr" >> "${GITHUB_OUTPUT:-/dev/null}"
      echo "$word · $pr"
      echo "::notice::Harmonia · $word · $pr"
    else
      echo "$word · no pull request yet · harmonia build --github $run"
      [ "$word" = "Report" ] && echo "::warning::Harmonia · nothing landed · $run"
    fi
    [ -n "$runner_pid" ] && wait "$runner_pid" 2>/dev/null || true
    exit 0
  fi
  sleep 15
done
echo "stands=Working" >> "${GITHUB_OUTPUT:-/dev/null}"
echo "still working · $run · harmonia build --show $run"
[ -n "$runner_pid" ] && kill "$runner_pid" 2>/dev/null || true
exit 0

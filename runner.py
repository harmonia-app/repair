#!/usr/bin/env python3
"""THE RUNNER — your job's own machine as the sandbox a fix's laps and
checks run in (compute never on Harmonia's metal). Registers this
job for the run, then serves the rail's commands one by one until the
run settles: open (a fresh home), put (a file), run (one command, its
exit and output), get (a file's bytes), kill (the home cleared).

Standard library only. Environment: HARMONIA_SERVICE, HARMONIA_KEY,
HARMONIA_RUN; optional HARMONIA_RUNNER_HOME (default /tmp/harmonia-rail),
HARMONIA_RUNNER_LABEL, HARMONIA_RUNNER_MINUTES (default 60)."""
from __future__ import annotations

import base64
import json
import os
import pathlib
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request

SERVICE = os.environ.get("HARMONIA_SERVICE", "https://api.harmonia.build").rstrip("/")
KEY = os.environ.get("HARMONIA_KEY", "")
RUN = os.environ.get("HARMONIA_RUN", "")
HOME = os.environ.get("HARMONIA_RUNNER_HOME") or "/tmp/harmonia-rail"
LABEL = os.environ.get("HARMONIA_RUNNER_LABEL") or os.environ.get("GITHUB_JOB") or "runner"
MINUTES = float(os.environ.get("HARMONIA_RUNNER_MINUTES") or 60)


def _call(method: str, path: str, payload: dict | None = None, timeout: float = 40.0) -> dict:
    data = json.dumps(payload).encode() if payload is not None else None
    request = urllib.request.Request(
        SERVICE + path, data=data, method=method,
        headers={"Authorization": f"Bearer {KEY}", "Content-Type": "application/json",
                 "User-Agent": "harmonia-runner"})
    try:
        with urllib.request.urlopen(request, timeout=timeout) as reply:
            return json.load(reply)
    except urllib.error.HTTPError as refused:
        body = refused.read()[:300].decode("utf-8", "replace")
        raise SystemExit(f"harmonia · the service refused {method} {path}: {refused.code} {body}")


def _inside(path: str) -> pathlib.Path:
    """A path the rail names must stay inside the runner's home."""
    home = pathlib.Path(HOME).resolve()
    target = pathlib.Path(path)
    if not target.is_absolute():
        target = home / target
    target = target.resolve()
    if target != home and home not in target.parents:
        raise ValueError(f"{path} is outside {HOME}")
    return target


def serve(command: dict) -> dict:
    verb = str(command.get("verb") or "")
    try:
        if verb == "open":
            shutil.rmtree(HOME, ignore_errors=True)
            pathlib.Path(HOME).mkdir(parents=True, exist_ok=True)
            return {"ok": True}
        if verb == "put":
            target = _inside(str(command.get("path") or ""))
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(base64.b64decode(str(command.get("data_b64") or "")))
            return {"ok": True}
        if verb == "run":
            seconds = int(command.get("seconds") or 240)
            try:
                done = subprocess.run(["bash", "-c", str(command.get("command") or "")],
                                      capture_output=True, cwd=HOME, timeout=seconds)
            except subprocess.TimeoutExpired:
                return {"ok": False, "exit": 124, "out": f"timed out after {seconds} s"}
            out = (done.stdout + done.stderr).decode("utf-8", "replace")[-40000:]
            return {"ok": done.returncode == 0, "exit": done.returncode, "out": out}
        if verb == "get":
            target = _inside(str(command.get("path") or ""))
            return {"ok": True, "data_b64": base64.b64encode(target.read_bytes()).decode("ascii")}
        if verb == "kill":
            shutil.rmtree(HOME, ignore_errors=True)
            return {"ok": True}
        return {"ok": False, "out": f"unknown verb {verb!r}"}
    except Exception as refused:                        # noqa: BLE001 — one command's failure is its answer
        return {"ok": False, "out": f"{type(refused).__name__}: {refused}"[:400]}


def main() -> int:
    if not (KEY and RUN):
        print("harmonia · runner needs HARMONIA_KEY and HARMONIA_RUN")
        return 2
    told = _call("POST", f"/v1/build/{RUN}/runner", {"home": HOME, "label": LABEL})
    session = str(told.get("session") or "")
    poll = float(told.get("poll_seconds") or 15)
    print(f"harmonia · runner · {RUN} · registered · {LABEL}", flush=True)
    deadline = time.monotonic() + MINUTES * 60
    served = 0
    while time.monotonic() < deadline:
        answer = _call("GET", f"/v1/build/{RUN}/runner/next?session={session}&wait={int(poll)}",
                       timeout=poll + 25)
        command = answer.get("command")
        if command is None:
            if answer.get("done"):
                print(f"harmonia · runner · {RUN} · settled · {served} commands", flush=True)
                shutil.rmtree(HOME, ignore_errors=True)
                return 0
            continue
        result = serve(command)
        served += 1
        verb = str(command.get("verb") or "")
        if verb == "run":
            print(f"harmonia · runner · ran · exit {result.get('exit')}", flush=True)
        _call("POST", f"/v1/build/{RUN}/runner/{command.get('id')}", {"session": session, **result})
    print(f"harmonia · runner · {RUN} · out of time · {served} commands", flush=True)
    return 1


if __name__ == "__main__":
    sys.exit(main())

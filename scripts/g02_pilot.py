"""Qualify authored G02 requirements through persistent MCP and independent audit."""
from contextlib import closing
import argparse
import json
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import time
import traceback

from continuity_gap_pilot import ROOT, RecordedSession, build_identity, save, sha
from continuity_gap.g02 import exercise
from mlx_authoring_smoke import require


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    started = time.monotonic()
    report = {"status": "failed", "scope": "Disposable synthetic G02 action applicability under ADR-0006"}
    try:
        command = ["cargo", "build", "--locked", "-p", "universe-cli", "-p", "universe-engine", "-p", "universe-mcp"]
        build = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
        save(output / "build.json", {"command": command, "returncode": build.returncode, "stdout": build.stdout, "stderr": build.stderr})
        require(build.returncode == 0, "build failed")
        bin_dir = ROOT / "target/debug"
        identity = build_identity(bin_dir, {"command": command, "returncode": 0})
        oracle = ROOT / "scripts/continuity_gap/g02-oracle.json"
        identity["g02_oracle_sha256"] = sha(oracle)
        save(output / "build-identity.json", identity)
        (output / "oracle.json").write_bytes(oracle.read_bytes())
        with tempfile.TemporaryDirectory(prefix="g02-", dir="/tmp") as directory:
            with (output / "mcp-transcript.jsonl").open("w", encoding="utf-8") as wire:
                s = RecordedSession(directory, bin_dir, report, wire=wire)
                try:
                    s.start()
                    report["installation"] = s.u
                    exercise(s, report)
                    report["status"] = "executed"
                finally:
                    s.close()
                    dbs = list((s.root / "packages").rglob("*.sqlite"))
                    if len(dbs) == 1:
                        with closing(sqlite3.connect(dbs[0])) as source, closing(sqlite3.connect(output / "package.sqlite")) as dest:
                            source.backup(dest)
                        report["package_sha256"] = sha(output / "package.sqlite")
                    save(output / "report.json", report)
        for script, arguments, destination in (
            ("audit_g02.py", [str(output)], "audit-execution.json"),
            ("test_g02_pilot.py", ["--evidence", str(output), "-v"], "audit-negative-tests.json"),
        ):
            result = subprocess.run([sys.executable, str(ROOT / "scripts" / script), *arguments], capture_output=True, text=True)
            save(output / destination, {"returncode": result.returncode, "stdout": result.stdout, "stderr": result.stderr})
            require(result.returncode == 0, f"{script} failed: {result.stderr}")
        final_identity = build_identity(bin_dir, {})
        require(final_identity["source_sha256"] == identity["source_sha256"] and
                final_identity["binaries"] == identity["binaries"], "source/binary changed during proof")
        save(output / "result.json", {"status": "passed", "seconds": time.monotonic() - started,
                                      "audit": "audit.json", "cases": 20})
    except Exception:
        report["error"] = traceback.format_exc()
        save(output / "report.json", report)
        raise
    finally:
        save(output / "evidence-manifest.json", {str(p.relative_to(output)): sha(p)
            for p in sorted(output.rglob("*")) if p.is_file() and p.name != "evidence-manifest.json"})
    print(f"PASS: G02 applicability; audited evidence: {output}")


if __name__ == "__main__":
    main()

"""Maintained baseline pilot. Two isolated installations; no product mutations.

Run: python3 scripts/continuity_gap_pilot.py --output docs/evidence/continuity-gap-RUN
Only disposable synthetic candidates receive automatic author approval.
"""
from contextlib import closing
import argparse
import hashlib
import json
import platform
from pathlib import Path
import subprocess
import tempfile
import traceback
import sqlite3
import sys
import importlib.metadata

from mcp_smoke import MCP
from mlx_authoring_smoke import require
from pilot_support import PilotSession
from continuity_gap.cases import exercise

ROOT = Path(__file__).resolve().parents[1]
ORACLE = ROOT / "scripts/continuity_gap/oracle.json"
BASELINE = ROOT / "scripts/continuity_gap/baseline.json"


def save(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def sha(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


class RecordedMCP(MCP):
    """Capture actual outgoing and received JSON-RPC envelopes, including errors."""
    def __init__(self, *args, wire, **kwargs):
        self.wire = wire
        super().__init__(*args, **kwargs)

    def record(self, direction, frame):
        self.wire.write(json.dumps({"direction": direction, "frame": frame}) + "\n")
        self.wire.flush()

    def write(self, message):
        self.record("sent", message)
        super().write(message)

    def request(self, method, params):
        self.seq += 1
        self.write({"jsonrpc": "2.0", "id": self.seq, "method": method, "params": params})
        while True:
            response = self.responses.get(timeout=20)
            if isinstance(response, Exception):
                raise response
            self.record("received", response)
            if "id" not in response:
                self.notifications.append(response)
                continue
            require(response["id"] == self.seq and "error" not in response, str(response))
            return response["result"]


class RecordedSession(PilotSession):
    def __init__(self, *args, wire, **kwargs):
        self.wire = wire
        super().__init__(*args, **kwargs)

    def connect(self):
        self.client = RecordedMCP(self.bin_dir / "universe-mcp", installation=self.root,
                                  profile=self.agent, wire=self.wire)
        self.instructions = self.client.initialization["instructions"]

    def cli(self, *args, **kwargs):
        # Keep failure output and exact private author requests as well as public MCP.
        result = super().cli(*args, **{**kwargs, "check": False})
        self.report.setdefault("author_cli", []).append({
            "arguments": list(map(str, args)), "profile": kwargs.get("profile"),
            "returncode": result.returncode, "stdout": result.stdout, "stderr": result.stderr})
        if kwargs.get("check", True):
            require(result.returncode == 0, f"author command {args[0]} failed: {result.stderr}")
        return result


def build_identity(bin_dir, build):
    paths = [ROOT / "Cargo.toml", ROOT / "Cargo.lock", ROOT / "rust-toolchain.toml"]
    for directory in ("crates", "contracts", "scripts"):
        paths += [p for p in (ROOT / directory).rglob("*") if p.is_file()
                  and "__pycache__" not in p.parts and p.suffix != ".pyc"]
    return {"git_head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
            "git_status": subprocess.check_output(["git", "status", "--short"], cwd=ROOT, text=True).splitlines(),
            "rustc": subprocess.check_output(["rustc", "--version"], cwd=ROOT, text=True).strip(),
            "python": platform.python_version(), "python_executable": sys.executable,
            "jsonschema": importlib.metadata.version('jsonschema'),
            "platform": platform.platform(), "build": build,
            "binaries": {name: {"sha256": sha(bin_dir / name), "bytes": (bin_dir / name).stat().st_size}
                         for name in ("universe", "universe-engine", "universe-mcp")},
            "source_sha256": {str(p.relative_to(ROOT)): sha(p) for p in sorted(set(paths))},
            "oracle_sha256": sha(ORACLE), "baseline_sha256": sha(BASELINE)}


def run_installation(output, bin_dir):
    output.mkdir()
    report = {"scope": "Disposable synthetic continuity gap probes; no production data",
              "build_identity": "../build-identity.json", "oracle": "../oracle.json", "probes": []}
    # macOS's default temporary path can exceed the existing Unix socket limit.
    with tempfile.TemporaryDirectory(prefix="ub-gap-", dir="/tmp") as directory:
        with (output / "mcp-transcript.jsonl").open("w", encoding="utf-8") as wire:
            s = RecordedSession(directory, bin_dir, report, wire=wire)
            try:
                s.start()
                report["installation"] = s.u
                exercise(s, report)
                report["status"] = "executed"
            except Exception:
                report["status"] = "failed"
                report["error"] = traceback.format_exc()
                raise
            finally:
                try:
                    s.close()
                    databases = list((s.root / "packages").rglob("*.sqlite"))
                    require(len(databases) == 1 or report["status"] == "failed",
                            "expected exactly one synthetic universe package")
                    # Database backup contains state/workflow/source bytes, no profile credentials.
                    if len(databases) == 1:
                        with closing(sqlite3.connect(f"file:{databases[0]}?mode=ro", uri=True)) as source:
                            with closing(sqlite3.connect(output / "package.sqlite")) as dest:
                                source.backup(dest)
                        report["package_sha256"] = sha(output / "package.sqlite")
                finally:
                    save(output / "report.json", report)
    result = subprocess.run([sys.executable, str(ROOT / "scripts/audit_continuity_gap.py"), str(output)],
                            capture_output=True, text=True)
    save(output / "audit-execution.json", {"returncode": result.returncode,
                                           "stdout": result.stdout, "stderr": result.stderr})
    require(result.returncode == 0, f"independent audit failed: {result.stderr}")
    return json.loads((output / "audit.json").read_text())


def evidence_index(output, audits):
    lines = ["# Continuity-gap baseline evidence", "",
             "Two fresh disposable installations; 13 original probes and 42 baseline calls each. "
             "Additional persistence and restart checks bring each transcript to 114 MCP calls. "
             "Each run has 12 MCP commit receipts (seed plus 11 gaps), 13 kernel receipts "
             "(including universe creation), and 14 revisions (including empty genesis).", "",
             "[Build identity](build-identity.json) · [Continuity oracle](oracle.json) · "
             "[Frozen observed baseline](baseline.json) · [Comparison](comparison.json) · "
             "[Negative audit checks](audit-negative-tests.json) · [Artifact hashes](evidence-manifest.json)", "",
             "Independent proof programs read the exact wire envelopes and saved SQLite state. "
             "The audit imports neither the runner nor its test helpers. This is an independent "
             "program audit, not an external human review. These results reproduce gaps; they do not close them.", "",
             "| Case | Baseline validation / approval | Run A evidence | Run B evidence |", "|---|---|---|---|"]
    for case_id in [*[f"G{n:02}" for n in range(1,12)], "C01", "C02"]:
        row = audits[0]["cases"][case_id]
        observed = row["observed_engine"]
        behavior = (observed.get("error_code") or f"{observed['coverage']}; {observed['findings']} findings")
        links = []
        for name, audit in zip(("run-a", "run-b"), audits):
            proof = audit["cases"][case_id]["evidence"]
            start, end = proof["validation_lines"]
            receipt = proof["receipt"]
            links.append(f"[wire lines {start}–{end}]({name}/mcp-transcript.jsonl), "
                         f"[state/receipt audit]({name}/audit.json), "
                         f"[approval and candidate]({name}/report.json)" +
                         (f"; revision `{receipt['revision']}`" if receipt else "; no commit"))
        lines.append(f"| {case_id}: {row['case']} | {behavior}; {observed['approval']} | {' | '.join(links)} |")
    lines += ["", "Each audit entry separates `expected_continuity`, `classification`, "
              "`observed_engine`, exact proposal identity, transcript line ranges and commit receipt. "
              "Raw identities, import times, digests and receipts remain in the proof files. "
              "The equivalence projection removes generated identities/import timestamps only after "
              "checking their exact bindings within each installation. Fixed stimulus identities, "
              "story times, subjects, predicates, roles, actions, effects, polarities, quotes and values remain comparable.", ""]
    (output / "README.md").write_text("\n".join(lines), encoding="utf-8")


def main():
    if "--g05" in sys.argv:
        from g05_pilot import main as g05_main
        g05_main([a for a in sys.argv[1:] if a != "--g05"])
        return
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    require(not output.exists(), "output already exists; use a fresh evidence directory")
    output.mkdir(parents=True)
    result = {"status": "failed"}
    try:
        bin_dir = ROOT / "target/debug"
        command = ["cargo", "build", "--locked", "--target-dir", str(ROOT / "target"),
                   "-p", "universe-cli", "-p", "universe-engine", "-p", "universe-mcp"]
        built = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
        build = {"command": command, "returncode": built.returncode, "stdout": built.stdout, "stderr": built.stderr}
        save(output / "build.json", build)
        require(built.returncode == 0, "build failed; see build.json")
        identity = build_identity(bin_dir, build)
        save(output / "build-identity.json", identity)
        (output / "oracle.json").write_bytes(ORACLE.read_bytes())
        (output / "baseline.json").write_bytes(BASELINE.read_bytes())
        audits = [run_installation(output / name, bin_dir) for name in ("run-a", "run-b")]
        require(audits[0]["equivalence"] == audits[1]["equivalence"], "fresh installation results differ")
        require(audits[0]["universe_id"] != audits[1]["universe_id"], "installations reused an identity")
        negative = subprocess.run([sys.executable, str(ROOT / "scripts/test_continuity_gap_pilot.py"),
                                   "--evidence", str(output / "run-a"), "-v"], capture_output=True, text=True)
        save(output / "audit-negative-tests.json", {"returncode": negative.returncode,
                                                    "stdout": negative.stdout, "stderr": negative.stderr})
        require(negative.returncode == 0, "negative proof checks failed")
        evidence_index(output, audits)
        require(build_identity(bin_dir, build)["source_sha256"] == identity["source_sha256"],
                "source changed during qualification")
        require(build_identity(bin_dir, build)["binaries"] == identity["binaries"],
                "binaries changed during qualification")
        result = {"status": "passed", "fresh_installations": 2, "equivalent": True,
                  "controls_work": True, "gap_ids": [f"G{n:02}" for n in range(1,12)],
                  "audits": ["run-a/audit.json", "run-b/audit.json"], "equivalence": audits[0]["equivalence"]}
    except Exception:
        result["error"] = traceback.format_exc()
        raise
    finally:
        save(output / "comparison.json", result)
        # Bind the proof files to their exact saved bytes; exclude the manifest itself.
        save(output / "evidence-manifest.json", {str(p.relative_to(output)): sha(p)
             for p in sorted(output.rglob("*")) if p.is_file() and p.name != "evidence-manifest.json"})
    print(f"PASS: two installations, thirteen cases each; evidence: {output}")


if __name__ == "__main__":
    main()

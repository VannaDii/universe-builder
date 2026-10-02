"""Persistent MCP pilot transport and exact UTF-8 provenance helpers.

All installations are disposable. Public operations use the real closed MCP
schemas; source staging and approval use the existing private author CLI.
"""
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import time

from mcp_smoke import MCP
from mlx_authoring_smoke import require

NAME = "The Cairn Archive Pilot"


def excerpt_locator(text, excerpt):
    """Return a unique exact UTF-8 byte range, never normalized character offsets."""
    require(isinstance(excerpt, str) and bool(excerpt.strip()), "empty excerpt")
    start = text.find(excerpt)
    require(start >= 0 and text.find(excerpt, start + 1) < 0,
            "excerpt must occur exactly once in its source, including overlapping matches")
    prefix = text[:start].encode("utf-8")
    content = excerpt.encode("utf-8")
    return {"kind": "byte_range", "start": len(prefix), "end": len(prefix) + len(content)}


def source_anchor(uid, source, text, excerpt, context):
    return {"sourceVersion": {"universe": uid, "record": source["identity"]["record_id"],
                             "version": source["record_version_id"]},
            "locator": excerpt_locator(text, excerpt), "excerpt": excerpt,
            "excerptDigest": hashlib.sha256(excerpt.encode("utf-8")).hexdigest(), "context": context}


class PilotSession:
    def __init__(self, directory, bin_dir, report):
        self.directory, self.bin_dir, self.report = Path(directory), Path(bin_dir), report
        self.root = self.directory / "installation"
        self.author, self.client, self.ctx = None, None, None
        self.u = None
        self.report.setdefault("mcp", [])

    def cli(self, *args, profile=None, check=True):
        command = [str(self.bin_dir / "universe"), "--installation", str(self.root)]
        if profile:
            command += ["--profile", profile]
        result = subprocess.run([*command, *map(str, args)], capture_output=True, text=True, timeout=30)
        if check:
            require(result.returncode == 0, f"author command {args[0]} failed: {result.stderr}")
        return result

    def admin(self, *args):
        return json.loads(self.cli(*args, profile=self.author).stdout)

    def start(self):
        self.author = self.cli("init").stdout.strip()
        self.u = self.admin("create", NAME, "--first-time", "10", "--calendar", "Archive days", "--tick-label", "days")
        self.agent = self.admin("enroll")["profile_id"]
        self.admin("grant", self.agent, self.u["universe_id"], "--propose", "--edit", "--protected")
        self.connect()
        self.open()
        clock = self.get([self.u["context_id"]])[0]
        self.calendar = clock["payload"]["chronology"]["calendar"]
        self.scope = {"context": {"universe": self.uid, "record": self.u["context_id"]},
                      "applicability": {"kind": "universe_wide"}}
        return self

    @property
    def uid(self):
        return self.u["universe_id"]

    def rid(self, n):
        return f"rec_{200000+n:024x}"

    def rr(self, n):
        return {"universe": self.uid, "record": self.rid(n) if isinstance(n, int) else n}

    def connect(self):
        self.client = MCP(self.bin_dir / "universe-mcp", installation=self.root, profile=self.agent)
        self.instructions = self.client.initialization["instructions"]

    def call(self, name, args, error=False):
        self.client.schemas[name][0].validate(args)
        result = self.client.call(name, args, error=error)
        self.report["mcp"].append({"tool": name, "arguments": args, "expected_error": error, "result": result})
        return result

    def open(self, revision=None, day=None, represented=None, perspective="author"):
        args = {"universe": NAME, "continuity_id": self.u["continuity_id"],
                "revision": {"kind": "exact", "revision_id": revision} if revision else {"kind": "head"},
                "represented_context": represented or self.u["context_id"],
                "temporal_query": {"kind": "at", "time": self.instant(day)} if day is not None else {"kind": "timeless"},
                "temporal_systems": [], "perspective": perspective}
        result = self.call("universe_open_context", args)["result"]
        if day is None and revision is None and represented is None:
            self.ctx = result["context_id"]
        return result

    def get(self, ids, context=None, groups=None):
        return self.call("universe_get", {"universe": NAME, "context_id": context or self.ctx,
                         "record_ids": ids, "field_groups": groups or ["payload"]})["result"]["records"]

    def state(self, ids, day, context=None, revision=None, perspective="author"):
        frame = self.open(revision, day, context, perspective)
        return self.call("universe_get_state", {"universe": NAME, "context_id": frame["context_id"],
                         "entity_ids": ids, "predicate_filters": []})

    def instant(self, day):
        return {"kind": "exact", "calendar": self.calendar, "value": str(day)}

    def interval(self, start, end=None):
        return {"kind": "calendar_interval", "calendar": self.calendar,
                "start": {"kind": "exact", "value": str(start)},
                "end": {"kind": "exact", "value": str(end)} if end is not None else {"kind": "unbounded"}}

    def propose(self, operations, key, context=None, rationale=None):
        return self.call("universe_propose", {"action": "create", "universe": NAME,
            "context_id": context or self.ctx, "operations": operations, "submission": "submitted",
            "rationale": rationale or key, "idempotency_key": key})["result"]

    @staticmethod
    def reference(p):
        return {k: p[k] for k in ("proposal_id", "version", "digest")}

    def validate(self, p, context=None, error=False):
        result = self.call("universe_validate", {"mode": "proposal", "universe": NAME,
            "context_id": context or self.ctx, "proposal_reference": self.reference(p),
            "check_scope": "universe"}, error)
        return result if error else result["result"]["execution"]

    def impact(self, p):
        return self.call("universe_get_impact", {"mode": "proposal", "universe": NAME,
            "context_id": self.ctx, "proposal_reference": self.reference(p), "scope": "universe", "byte_budget": 65536})

    def approval(self, p, v, check=True):
        return self.cli("approve", NAME, p["proposal_id"], p["version"], p["digest"], v["run_id"],
                        profile=self.author, check=check)

    def commit_args(self, p, v, key):
        return {"universe": NAME, "proposal_reference": self.reference(p),
                "expected_base_revision": p["base_frame"]["revision"], "validation_run": v["run_id"], "idempotency_key": key}

    def publish(self, p, key, model=None):
        v = self.validate(p)
        require(v["coverage"] == "complete" and not v["findings"], f"candidate {key} failed: {v}")
        impact = self.impact(p)
        require(impact["delivery"]["complete"] and impact["result"]["coverage"] == "complete", "incomplete impact")
        args = self.commit_args(p, v, key)
        self.call("universe_commit", args, error=True)
        review = self.admin("review", NAME, p["proposal_id"], p["version"], p["digest"])
        approval = json.loads(self.approval(p, v).stdout)
        require(approval == {"approved": self.reference(p), "validation_run": v["run_id"]},
                "author approval receipt differs from selected candidate")
        if model:
            decision = model.commit(args)
            require(decision == {"tool": "universe_commit", "arguments": args}, "model retargeted commit")
            args = decision["arguments"]
        receipt = self.call("universe_commit", args)["result"]
        require(self.call("universe_commit", args)["result"] == receipt, "commit retry differed")
        self.open()
        self.report.setdefault("publications", []).append({"key": key, "review": review,
            "author_selection": {"author_profile": self.author, "rationale": p["rationale"], "approval": approval},
            "validation": v, "impact": impact, "receipt": receipt, "commit_arguments": args})
        return receipt

    def stage(self, text, label, key):
        path = self.directory / f"{key}.txt"
        path.write_text(text, encoding="utf-8")
        staged = self.admin("stage-source", NAME, label, path)
        require(staged["canonical"] is False, "staging unexpectedly committed canon")
        p = self.propose(staged["operations"], f"{key}-source")
        receipt = self.publish(p, f"{key}-source-commit")
        source = self.get([staged["operations"][1]["client_ref"]])[0]
        require(source["payload"]["digest"] == hashlib.sha256(text.encode()).hexdigest(), "source digest mismatch")
        return source, receipt

    def restart(self):
        self.client.close()
        self.client = None
        # Kill only the engine whose exact argument vector belongs to this pilot.
        root = str(self.root.resolve())
        rows = subprocess.check_output(["ps", "-axo", "pid=,command="], text=True).splitlines()
        matched = [int(line.strip().split(None, 1)[0]) for line in rows
                   if f"universe-engine --installation {root}" in line]
        require(len(matched) == 1, "cannot identify the owned pilot engine")
        os.kill(matched[0], signal.SIGKILL)
        time.sleep(.2)
        self.admin("status")
        self.connect()
        self.open()

    def close(self):
        if self.client:
            self.client.close()
            self.client = None
        if self.author:
            self.cli("shutdown", profile=self.author, check=False)
            deadline = time.monotonic() + 5
            while (self.root / "engine.sock").exists() and time.monotonic() < deadline:
                time.sleep(.02)
            require(not (self.root / "engine.sock").exists(), "pilot engine did not stop")

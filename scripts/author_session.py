"""Interactive offline author research using model-selected MCP calls.

Run with an existing MLX Python environment. Conversation stays in memory;
writing is checked through uncommitted proposals. Explicit author commands
review, approve and publish through a separate private authority.
"""
import argparse
import base64
import copy
import json
from pathlib import Path
import queue
import re
import subprocess
import uuid
import sys

from jsonschema import Draft202012Validator, ValidationError
from local_mlx import OfflineMLX
from mcp_smoke import MCP

RESEARCH_TOOLS = frozenset({
    "universe_describe", "universe_open_context", "universe_search", "universe_read_facts",
    "universe_get_operation", "universe_read_contracts",
})

class ProtocolError(RuntimeError):
    def __init__(self, error):
        self.error = error
        super().__init__("MCP request failed")


class SessionMCP(MCP):
    """Existing stdio transport, with runtime errors instead of test assertions."""
    def __init__(self, *args, **kwargs):
        try:
            super().__init__(*args, client_name="universe-author-session", **kwargs)
        except BaseException:
            if hasattr(self, "process"):
                self.close()
            raise

    def request(self, method, params):
        self.seq += 1
        self.write({"jsonrpc": "2.0", "id": self.seq, "method": method, "params": params})
        while True:
            try:
                response = self.responses.get(timeout=20)
            except queue.Empty as error:
                raise RuntimeError("MCP response timed out; research is incomplete") from error
            if isinstance(response, Exception):
                raise response
            if "id" not in response:
                self.notifications.append(response)
                continue
            if response["id"] != self.seq:
                raise RuntimeError("unexpected MCP response identity")
            if "error" in response:
                raise ProtocolError(response["error"])
            if "result" not in response:
                raise RuntimeError("MCP response has no result")
            return response["result"]


def schema_feedback(error):
    """Expose the failed schema paths, including nested variant failures."""
    def leaves(item):
        if item.context:
            children = item.context
            if isinstance(item.instance, dict):
                matches = []
                for index, branch in enumerate(item.schema.get(item.validator, [])):
                    constants = {key: value["const"] for key, value in branch.get("properties", {}).items() if "const" in value}
                    if constants and all(item.instance.get(key) == value for key, value in constants.items()):
                        matches.append(index)
                if len(matches) == 1:
                    children = [child for child in children if child.schema_path[0] == matches[0]]
            for child in children:
                yield from leaves(child)
        else:
            yield item
    details = []
    for item in leaves(error):
        path = ".".join(map(str, item.absolute_path)) or "arguments"
        details.append(f"{path}: {item.message}")
        if len(details) == 12:
            break
    return "; ".join(details)


class AuthorSession:
    def __init__(self, model, client, universe, *, max_steps=20, max_tokens=3000,
                 max_context_tokens=32768, output=print, checking=True):
        self.model, self.client, self.universe = model, client, universe
        self.max_steps, self.max_tokens = max_steps, max_tokens
        self.max_context_tokens, self.output, self.checking = max_context_tokens, output, checking
        self.tool_calls, self.generations = [], []
        self.last_check = None
        self.last_passage = None
        instructions = client.initialization.get("instructions")
        if not isinstance(instructions, str) or not instructions.strip():
            raise RuntimeError("server did not provide authoring instructions")
        self.tools = {}
        cursor = None
        while True:
            page = client.request("tools/list", {"cursor": cursor} if cursor else {})
            for tool in page["tools"]:
                name = tool["name"]
                if name in self.tools:
                    raise RuntimeError("server delivered duplicate tool names")
                Draft202012Validator.check_schema(tool["inputSchema"])
                Draft202012Validator.check_schema(tool["outputSchema"])
                self.tools[name] = tool
            cursor = page.get("nextCursor")
            if not cursor:
                break
        allowed = RESEARCH_TOOLS | ({"universe_check_changes"} if checking else set())
        self.available = {name: tool for name, tool in self.tools.items() if name in allowed}
        if checking and "universe_check_changes" not in self.available:
            raise RuntimeError("server did not provide ordinary factual checking")
        self.native_tools = [{"type": "function", "function": {
            "name": tool["name"], "description": tool["description"],
            "parameters": self.native_parameters(tool["inputSchema"])}}
            for tool in self.available.values()]
        self.messages = [{"role": "system", "content": instructions},
                         {"role": "user", "content": (
            f"This author session uses universe {universe!r}. " +
            ("Automatically check each submitted passage through the available ordinary tools, then explain the returned result concisely. No private author actions or publication are available." if checking else
             "Research the author request using available tools. State uncertainty and incomplete coverage plainly; no publication is available."))}]

    @staticmethod
    def native_parameters(schema):
        # MLX's native parser reads top-level parameter types. Resolve those
        # references and common object unions without changing valid inputs.
        result = copy.deepcopy(schema)
        definitions = result.get("$defs", {})
        def resolve(value):
            if "$ref" in value:
                value = copy.deepcopy(definitions[value["$ref"].split("/")[-1]])
            alternatives = value.get("oneOf", value.get("anyOf", []))
            if alternatives and all(resolve(branch).get("type") == "object" for branch in alternatives):
                value["type"] = "object"
            return value
        properties = result.setdefault("properties", {})
        for branch in result.get("oneOf", result.get("anyOf", [])):
            for key, value in resolve(branch).get("properties", {}).items():
                hint = resolve(value)
                if key not in properties:
                    properties[key] = hint
                elif resolve(properties[key]).get("type") != hint.get("type"):
                    # Canonical branches with different wire types retain their
                    # full schema; no fabricated parser type is safe.
                    properties[key].pop("type", None)
        for key, value in list(properties.items()):
            properties[key] = resolve(value)
        return result

    def dispatch(self, name, arguments):
        if name not in self.available:
            raise ValueError("tool is not available in this author session")
        tool = self.available[name]
        Draft202012Validator(tool["inputSchema"]).validate(arguments)
        if arguments["universe"] != self.universe:
            raise ValueError("tool call must use the session universe")
        result = self.client.request("tools/call", {"name": name, "arguments": arguments})
        if not result.get("isError", False):
            Draft202012Validator(tool["outputSchema"]).validate(result.get("structuredContent"))
        structured = result.get("structuredContent")
        text = "".join(item["text"] for item in result.get("content", []) if item.get("type") == "text")
        if structured is not None and text and json.loads(text) != structured:
            raise RuntimeError("MCP text and structured data disagree; checking is incomplete")
        self.tool_calls.append((name, copy.deepcopy(arguments), copy.deepcopy(result)))
        return {key: value for key, value in result.items() if key != "content"} if structured is not None else result

    @staticmethod
    def check_report(checked):
        if not checked:
            return "Writing check incomplete: no completed change check. No changes were published."
        labels = {"checked_candidate": "Candidate checked; not published.",
                  "needs_clarification": "Author clarification needed; not published.",
                  "conflict": "Continuity conflict found; not published.",
                  "no_changes": "No factual changes identified in this bounded reading; not published.",
                  "incomplete": "Writing check incomplete; not published."}
        lines = [labels.get(checked.get("status"), "Writing check incomplete; not published.")]
        additions_title = "Tentative held suggestion" if checked.get("clarifications") and not checked.get("candidate_handle") else "Proposed"
        for key, title in (("additions", additions_title), ("unchanged", "Unchanged"),
                           ("excluded", "Excluded from objective facts"),
                           ("clarifications", "Author question"), ("unknowns", "Unknown")):
            for item in checked.get(key, []):
                lines.append(f"{title}: {item}")
        execution = (checked.get("validation") or {}).get("execution", {})
        for finding in execution.get("findings", []):
            lines.append("Finding: " + (finding.get("message") or finding.get("outcome", "unresolved")))
        for opposition in execution.get("opposing_evidence", []):
            lines.append(f"Opposing claims: {opposition.get('kind', 'unresolved')}; coverage {opposition.get('coverage', 'unavailable')}; unresolved: {', '.join(opposition.get('unresolved_reasons', [])) or 'none'}.")
        if checked.get("validation"):
            lines.append(f"Engine coverage: {execution.get('coverage', 'unavailable')}; impact: {(checked.get('impact') or {}).get('coverage', 'unavailable')}.")
        lines.append("This bounded check does not guarantee every prose implication was identified.")
        return "\n".join(lines)

    def respond(self, passage):
        self.last_check = None
        self.last_passage = passage
        self.messages.append({"role": "user", "content": passage})
        checked, previous_error, repeats = None, None, 0
        pending_candidate = False
        check_attempted, reminder_sent = False, False
        stop_reason = "the session reached its turn limit"
        for _ in range(self.max_steps):
            try:
                generated = self.model.generate(self.messages, tools=self.native_tools,
                    max_tokens=self.max_tokens, max_context_tokens=self.max_context_tokens)
                self.generations.append(generated)
                if generated.reached_token_limit:
                    raise ValueError("generation reached its token limit; no call executed")
                calls = generated.tool_calls
                if not calls:
                    self.messages.append({"role": "assistant", "content": generated.text})
                    if self.checking and not check_attempted and not reminder_sent and previous_error is None:
                        self.messages.append({"role":"user", "content":
                            "This submitted passage still has no engine writing check. Use the available ordinary writing-check tool before finishing; if you cannot check it, report the limit honestly."})
                        reminder_sent = True
                        continue
                    if self.checking:
                        self.last_check = checked
                        reply = self.check_report(checked)
                    else:
                        reply = generated.text
                    self.output(reply)
                    return reply
                native_calls = [{"type": "function", "id": f"call_{len(self.messages)}_{index}",
                                 "function": {"name": call["name"], "arguments": call["arguments"]}}
                                for index, call in enumerate(calls)]
                content = generated.text.split("<tool_call>", 1)[0].strip()
                self.messages.append({"role": "assistant", "content": content, "tool_calls": native_calls})
                for call in native_calls:
                    function = call["function"]
                    if function["name"] == "universe_check_changes":
                        check_attempted = True
                        checked = None
                    try:
                        result = self.dispatch(function["name"], function["arguments"])
                    except ProtocolError as error:
                        result = {"isError": True, "error": error.error}
                    except (ValueError, TypeError, ValidationError) as error:
                        result = {"isError": True, "error": schema_feedback(error) if isinstance(error, ValidationError) else str(error)}
                    self.messages.append({"role": "tool", "tool_call_id": call["id"],
                                          "name": function["name"], "content": json.dumps(result)})
                    if result.get("isError", False):
                        reason = json.dumps(result, sort_keys=True)
                        repeats = repeats + 1 if reason == previous_error else 1
                        previous_error = reason
                        if function["name"] == "universe_check_changes":
                            checked = None
                    else:
                        previous_error, repeats = None, 0
                        if function["name"] == "universe_check_changes":
                            checked = result["structuredContent"]["result"]
                            if checked.get("status") == "no_changes" and pending_candidate:
                                checked = None
                                result = {"isError": True, "error": "A prior uncommitted candidate from this passage still exists; an empty delta does not withdraw or validate it."}
                                self.messages[-1]["content"] = json.dumps(result)
                            else:
                                pending_candidate |= bool(checked.get("candidate_handle"))
                if checked and checked.get("status") == "checked_candidate" and checked.get("candidate_handle"):
                    # The engine has finished this candidate. Waiting for a free-text
                    # model ending can turn successful checks into a retry loop.
                    self.last_check = checked
                    reply = self.check_report(checked)
                    self.output(reply)
                    return reply
                if repeats >= 2:
                    stop_reason = "the model repeated the same tool error"
                    break
            except ValueError as error:
                self.messages.append({"role": "user", "content": f"Tool format error: {error}. No call executed."})
                reason = str(error)
                repeats = repeats + 1 if reason == previous_error else 1
                previous_error = reason
                if repeats >= 2:
                    stop_reason = "the model repeated the same invalid tool format"
                    break
            except RuntimeError as error:
                stop_reason = f"inference or transport stopped: {error}"
                break
        message = f"Writing check incomplete: {stop_reason}. No changes were published."
        self.messages.append({"role": "user", "content": message})
        self.output(message)
        return None


class AuthorDecisions:
    """Host-only author authority. Private responses and identities never reach inference."""
    def __init__(self, session, binary, installation, author_profile, output=print):
        self.session, self.binary, self.installation = session, binary, installation
        self.author_profile, self.output = author_profile, output
        self.review = None
        self.publish_key = None

    def action(self, arguments):
        result = subprocess.run([str(self.binary), "--installation", str(self.installation),
            "--profile", self.author_profile, "author-writing", self.session.universe],
            input=json.dumps(arguments), capture_output=True, text=True)
        if result.returncode:
            raise RuntimeError(result.stderr.strip() or "Author action failed; retain the original recovery key.")
        return json.loads(result.stdout)

    def candidate(self):
        checked = self.session.last_check
        if not checked or checked.get("clarifications") or not checked.get("candidate_handle"):
            raise ValueError("Answer the material questions and submit corrected writing first.")
        return checked["candidate_handle"]

    def show_review(self):
        if not self.review:
            raise ValueError("Prepare the author's selected passage first with /review.")
        for line in self.review.get("summary", []):
            self.output(line)
        self.output("Ready for exact approval." if self.review.get("publishable") else "Publication blocked by the engine; correct the writing or explicitly resolve a supported finding.")
        for finding in self.review.get("validation", {}).get("execution", {}).get("findings", []):
            self.output(f"Finding {finding['fingerprint']}: {finding.get('message') or finding['outcome']}")
        for option in self.review.get("acceptance_options", []):
            self.output(f"Creative acceptance option: {option['fingerprint']} {option['scope']}; requires your explicit reason.")
        self.output(f"Exact review: {self.review['candidate']['digest']}")

    def handle(self, passage):
        if not passage.startswith("/"):
            # A natural-language clarification carries the original author's passage;
            # both are preserved verbatim for later source review.
            if self.session.last_check and self.session.last_check.get("clarifications"):
                passage = self.session.last_passage + "\n\nAuthor clarification:\n" + passage
            self.review, self.publish_key = None, None
            return self.session.respond(passage)
        command, _, rest = passage.partition(" ")
        if command == "/review":
            if self.review is None:
                self.review = self.action({"action":"prepare", "candidate":self.candidate(),
                    "label":"Author selected passage", "text":self.session.last_passage})
                self.publish_key = "author-publish:" + uuid.uuid4().hex
            self.show_review()
        elif command == "/reject":
            candidate = self.review["candidate"]["proposal_id"] if self.review else self.candidate()
            self.action({"action":"reject", "candidate":candidate})
            self.review, self.publish_key, self.session.last_check = None, None, None
            self.output("Candidate rejected; no changes published.")
        elif command == "/accept":
            if not self.review:
                raise ValueError("Review the exact current candidate first.")
            fingerprint, _, rest = rest.partition(" ")
            scope, _, rationale = rest.partition(" ")
            if not fingerprint or not scope or not rationale.strip():
                raise ValueError("Use /accept FINDING RESOURCE_SCOPE your reason; this is separate from approval.")
            self.review = self.action({"action":"accept", "candidate":self.review["candidate"],
                "fingerprint":fingerprint,"scope":scope,"rationale":rationale})
            self.publish_key = "author-publish:" + uuid.uuid4().hex
            self.show_review()
        elif command == "/recover":
            try:
                arguments = json.loads(base64.urlsafe_b64decode(rest.encode()))
            except (ValueError, UnicodeError) as error:
                raise ValueError("Invalid recovery token.") from error
            if arguments.get("action") != "publish":
                raise ValueError("Recovery token must identify the original publication.")
            receipt = self.action(arguments)
            self.published(receipt, arguments["candidate"])
            return receipt
        elif command in {"/approve", "/retry"}:
            if not self.review or not self.publish_key or not self.review.get("publishable"):
                raise ValueError("No publishable exact review is awaiting author approval.")
            arguments = {"action":"publish", "candidate":self.review["candidate"],
                "validation_run":self.review["validation"]["execution"]["run_id"],
                "idempotency_key":self.publish_key}
            token = base64.urlsafe_b64encode(json.dumps(arguments).encode()).decode()
            self.output("If interrupted, recover the original operation with /recover " + token)
            receipt = self.action(arguments)
            self.published(receipt, arguments["candidate"])
            return receipt
        else:
            raise ValueError("Commands: /review, /approve, /retry, /recover TOKEN, /reject, /accept FINDING RESOURCE_SCOPE reason, /quit.")

    def published(self, receipt, candidate):
        result = receipt.get("result", {})
        for key, prefix in (("operation_id", "op"), ("proposal_id", "prp"), ("revision", "rev")):
            if not isinstance(result.get(key), str) or not re.fullmatch(prefix + r"_[0-9a-f]{24}", result[key]):
                raise RuntimeError("Publication outcome unknown: no valid commit receipt. Retain the original recovery token.")
        if result["proposal_id"] != candidate["proposal_id"]:
            raise RuntimeError("Publication receipt does not match the approved candidate.")
        self.session.messages = self.session.messages[:2]
        self.review, self.publish_key, self.session.last_check = None, None, None
        self.output("Author-approved changes published.")
        frame = receipt["frame"]
        fresh = self.session.dispatch("universe_open_context", {"universe":self.session.universe,
            "continuity_id":frame["continuity"], "revision":{"kind":"head"},
            "represented_context":frame["context"]["record"],"temporal_query":{"kind":"timeless"},
            "temporal_systems":[],"perspective":"author"})
        if fresh.get("isError"):
            raise RuntimeError("Changes published, but fresh research context is unavailable. Retrieve current canon before continuing.")
        self.session.messages.append({"role":"user", "content":
            "Publication returned a real receipt. Fresh public research context: " + json.dumps(fresh) +
            ". Retrieve relevant facts from this current context before checking further writing."})


def passages(stream):
    """A blank line submits multiline input; /quit between passages exits."""
    lines = []
    for line in stream:
        line = line.rstrip("\r\n")
        if not lines and line.strip() == "/quit":
            return
        if not line.strip():
            if lines:
                yield "\n".join(lines)
                lines = []
        else:
            lines.append(line)
    if lines:
        yield "\n".join(lines)


def positive_integer(value):
    value = int(value)
    if value < 1:
        raise argparse.ArgumentTypeError("must be positive")
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--bin-dir", type=Path, default=Path("target/debug"))
    parser.add_argument("--installation", type=Path, required=True)
    parser.add_argument("--universe", required=True)
    parser.add_argument("--author-profile", required=True,
                        help="Private author identity reserved for author actions; never sent to the model")
    parser.add_argument("--agent-profile", required=True)
    parser.add_argument("--max-steps", type=positive_integer, default=20)
    parser.add_argument("--max-tokens", type=positive_integer, default=3000)
    parser.add_argument("--max-context-tokens", type=positive_integer, default=32768)
    args = parser.parse_args()
    if args.author_profile == args.agent_profile:
        parser.error("author and agent profiles must be distinct")
    if not args.installation.is_dir():
        parser.error("installation must already exist")
    client = None
    try:
        client = SessionMCP(args.bin_dir.resolve() / "universe-mcp",
                            installation=args.installation.resolve(), profile=args.agent_profile)
        print("Loading local model…", flush=True)
        model = OfflineMLX(args.model)
        session = AuthorSession(model, client, args.universe, max_steps=args.max_steps,
                                max_tokens=args.max_tokens, max_context_tokens=args.max_context_tokens)
        decisions = AuthorDecisions(session, args.bin_dir.resolve() / "universe", args.installation.resolve(), args.author_profile)
        print("Enter writing or a research request. Blank line submits; /quit exits. Writing is checked automatically. /review prepares exact author source; /approve publishes only that review; /reject discards; /retry recovers an interrupted publication.", flush=True)
        for passage in passages(sys.stdin):
            print("Checking writing…", flush=True)
            try:
                decisions.handle(passage)
            except (ValueError, RuntimeError) as error:
                print(f"Author action stopped: {error}", file=sys.stderr)
    except (OSError, RuntimeError, ValueError, KeyboardInterrupt) as error:
        print(f"Session stopped; research incomplete: {error}", file=sys.stderr)
        return 1
    finally:
        if client:
            client.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

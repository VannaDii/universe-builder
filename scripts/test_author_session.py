"""Functional session regressions; no saved conversations or model required."""
import copy
import io
import json
import unittest
from types import SimpleNamespace
from unittest.mock import patch

from author_session import AuthorSession, ProtocolError, passages, schema_feedback
from local_mlx import Generation, OfflineMLX


class Client:
    initialization = {"instructions": "Canonical server guidance"}

    def __init__(self):
        self.calls = []
        self.result = {"content": [], "structuredContent": {"answer": "retrieved"}}
        tool = {"name": "universe_describe", "description": "Describe explicit universe",
                "inputSchema": {"type": "object", "required": ["universe"],
                                "properties": {"universe": {"type": "string"}},
                                "additionalProperties": False},
                "outputSchema": {"type": "object", "required": ["answer"],
                                 "properties": {"answer": {"type": "string"}}}}
        self.tools = [tool, {**tool, "name": "universe_commit"}]

    def request(self, method, params):
        if method == "tools/list":
            return {"tools": self.tools}
        self.calls.append((method, params))
        if isinstance(self.result, Exception):
            raise self.result
        return self.result


class Model:
    def __init__(self, *texts):
        self.texts = iter(texts)
        self.inputs = []

    def generate(self, messages, **kwargs):
        self.inputs.append(copy.deepcopy(messages))
        value = next(self.texts)
        if isinstance(value, Generation):
            return value
        return Generation(value, 0, 0, False)


class SessionTests(unittest.TestCase):
    def session(self, model=None, client=None, **kwargs):
        return AuthorSession(model or Model(), client or Client(), "Story", output=lambda _: None, **kwargs)

    def test_multiline_blank_line_eof_and_quit(self):
        self.assertEqual(list(passages(io.StringIO("a\nb\n\n\nc\n\n/quit\nignored"))), ["a\nb", "c"])
        self.assertEqual(list(passages(io.StringIO("tail"))), ["tail"])
        self.assertEqual(list(passages(io.StringIO("/quit\n"))), [])

    def test_model_selected_research_and_reply(self):
        model = Model('{"tool":"universe_describe","arguments":{"universe":"Story"}}',
                      '{"reply":"The world is retrieved."}')
        client = Client()
        session = self.session(model, client)
        self.assertEqual(session.respond("Research my world"), "The world is retrieved.")
        self.assertEqual(client.calls, [("tools/call", {"name": "universe_describe", "arguments": {"universe": "Story"}})])
        self.assertEqual(session.messages[0]["content"], client.initialization["instructions"])
        framing = json.loads(session.messages[1]["content"])
        self.assertEqual([t["name"] for t in framing["tools"]], ["universe_describe"])
        self.assertEqual([set(shape) for shape in framing["response_formats"]],
                         [{"tool", "arguments"}, {"reply"}])
        self.assertIn("retrieved", model.inputs[1][-1]["content"])

    def test_mutating_wrong_universe_and_invalid_arguments_never_dispatch(self):
        from jsonschema import ValidationError
        session = self.session()
        for decision in ({"tool": "universe_commit", "arguments": {"universe": "Story"}},
                         {"tool": "universe_describe", "arguments": {"universe": "Other"}},
                         {"tool": "universe_describe", "arguments": {}},
                         {"tool": "universe_describe", "arguments": {"universe": "Story"}, "approval": True},
                         {"tool": [], "arguments": {}}):
            with self.subTest(decision=decision), self.assertRaises((ValueError, ValidationError)):
                session.dispatch(decision)
        self.assertEqual(session.client.calls, [])

    def test_invalid_json_receives_format_feedback_without_answer(self):
        model = Model('```json {} ```', '{"reply":"Need more information."}')
        session = self.session(model)
        self.assertEqual(session.respond("author prose"), "Need more information.")
        feedback = json.loads(model.inputs[1][-1]["content"])
        self.assertEqual(set(feedback), {"error"})
        self.assertEqual(session.client.calls, [])

    def test_protocol_and_tool_errors_return_to_model(self):
        for result in (ProtocolError({"code": -32602, "message": "invalid context"}),
                       {"content": [{"type": "text", "text": "access denied"}], "isError": True}):
            client = Client()
            client.result = result
            model = Model('{"tool":"universe_describe","arguments":{"universe":"Story"}}',
                          '{"reply":"Research could not finish."}')
            session = self.session(model, client)
            self.assertEqual(session.respond("prose"), "Research could not finish.")
            self.assertIn("error" if isinstance(result, Exception) else "isError", model.inputs[1][-1]["content"])

    def test_turn_and_generation_limits_never_execute_truncated_call(self):
        model = Model(Generation('{"tool":"universe_describe","arguments":{"universe":"Story"}}', 0, 10, True))
        session = self.session(model, max_steps=1)
        self.assertIsNone(session.respond("prose"))
        self.assertEqual(session.client.calls, [])

    def test_discovered_schema_used_instead_of_repository_shape(self):
        client = Client()
        client.tools[0]["inputSchema"]["required"].append("cursor")
        client.tools[0]["inputSchema"]["properties"]["cursor"] = {"type": "string"}
        session = self.session(client=client)
        model = Model('{"tool":"universe_describe","arguments":{"universe":"Story"}}', '{"reply":"Incomplete."}')
        session.model = model
        session.respond("prose")
        self.assertEqual(client.calls, [])
        self.assertIn("cursor", model.inputs[1][-1]["content"])

    def test_nested_schema_feedback_identifies_missing_fields(self):
        from jsonschema import Draft202012Validator
        schema = {"oneOf": [{"type": "object", "required": ["context_id"]},
                            {"type": "object", "required": ["operation_id"]}]}
        error = next(Draft202012Validator(schema).iter_errors({}))
        feedback = schema_feedback(error)
        self.assertIn("context_id", feedback)
        self.assertIn("operation_id", feedback)
        self.assertNotIn("required_response", feedback)

    def test_catalog_pagination_and_duplicate_failure(self):
        client = Client()
        original = client.request
        pages = iter([{"tools": [client.tools[0]], "nextCursor": "next"},
                      {"tools": [client.tools[1]]}])
        client.request = lambda method, params: next(pages) if method == "tools/list" else original(method, params)
        self.assertEqual(len(self.session(client=client).tools), 2)
        client = Client()
        client.tools.append(client.tools[0])
        with self.assertRaisesRegex(RuntimeError, "duplicate"):
            self.session(client=client)


class InferenceTests(unittest.TestCase):
    def runtime(self):
        model = OfflineMLX.__new__(OfflineMLX)
        model.model = object()
        model.tokenizer = SimpleNamespace(
            apply_chat_template=lambda *args, **kwargs: "template",
            encode=lambda *args, **kwargs: [1, 2, 3])
        return model

    def test_context_limit_prevents_generation_without_dropping_history(self):
        calls = []
        modules = {"mlx_lm": SimpleNamespace(stream_generate=lambda *args, **kwargs: calls.append(args)),
                   "mlx_lm.sample_utils": SimpleNamespace(make_sampler=lambda **kwargs: None)}
        with patch.dict("sys.modules", modules):
            with self.assertRaisesRegex(RuntimeError, "context limit"):
                self.runtime().generate([{"role": "user", "content": "writing"}],
                                        max_tokens=2, max_context_tokens=4)
        self.assertEqual(calls, [])

    def test_runtime_returns_limits_without_recording_conversation(self):
        part = SimpleNamespace(text="{}", prompt_tokens=3, generation_tokens=2)
        modules = {"mlx_lm": SimpleNamespace(stream_generate=lambda *args, **kwargs: iter([part])),
                   "mlx_lm.sample_utils": SimpleNamespace(make_sampler=lambda **kwargs: None)}
        model = self.runtime()
        with patch.dict("sys.modules", modules):
            result = model.generate([{"role": "user", "content": "writing"}], max_tokens=2)
        self.assertEqual(result.text, "{}")
        self.assertTrue(result.reached_token_limit)
        self.assertEqual(set(vars(model)), {"model", "tokenizer"})


if __name__ == "__main__":
    unittest.main()

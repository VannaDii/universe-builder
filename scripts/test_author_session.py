"""Functional session regressions; conversations remain in memory."""
import copy
import io
import json
import unittest
from author_session import AuthorSession, ProtocolError, passages
from local_mlx import Generation

class Client:
    initialization = {"instructions": "Canonical server guidance"}
    def __init__(self):
        self.calls = []
        shape = {"type":"object","required":["universe"],"properties":{"universe":{"type":"string"}},"additionalProperties":False}
        self.tools = [{"name":name,"description":name,"inputSchema":shape,"outputSchema":{"type":"object"}} for name in ("universe_describe","universe_check_changes","universe_commit")]
        self.results = iter([])
    def request(self, method, params):
        if method == "tools/list": return {"tools":self.tools}
        self.calls.append(params)
        result = next(self.results, {"structuredContent":{"result":{"status":"checked_candidate"}},"content":[]})
        if isinstance(result, Exception): raise result
        return result
class Model:
    def __init__(self,*responses): self.responses=iter(responses); self.inputs=[]; self.tools=[]
    def generate(self,messages,**kwargs):
        self.inputs.append(copy.deepcopy(messages)); self.tools.append(kwargs["tools"])
        response=next(self.responses)
        if isinstance(response,Exception): raise response
        return response if isinstance(response,Generation) else Generation(response,0,0,False)
def call(name="universe_describe",args=None):
    return Generation("<tool_call>native</tool_call>",0,0,False,({"name":name,"arguments":args if args is not None else {"universe":"Story"}},))
class SessionTests(unittest.TestCase):
    def session(self,model,client=None,**kwargs): return AuthorSession(model,client or Client(),"Story",output=lambda _:None,**kwargs)
    def test_multiline_and_quit(self):
        self.assertEqual(list(passages(io.StringIO("a\nb\n\nc\n\n/quit\nignored"))),["a\nb","c"])
    def test_native_research_then_plain_answer(self):
        model=Model(call(),"Retrieved the world."); client=Client(); session=self.session(model,client,checking=False)
        self.assertEqual(session.respond("Author prose"),"Retrieved the world.")
        self.assertEqual(client.calls[0]["name"],"universe_describe")
        self.assertEqual(model.inputs[1][-1]["role"],"tool")
        self.assertEqual(session.messages[0]["content"],client.initialization["instructions"])
        self.assertEqual(model.inputs[0][-1]["content"],"Author prose")
        self.assertNotIn("universe_commit",[t["function"]["name"] for t in model.tools[0]])
    def test_boundaries_and_real_error_feedback(self):
        model=Model(call("universe_commit"),call(args={"universe":"Other"}),"Can't check.")
        client=Client(); session=self.session(model,client)
        self.assertIn("no completed change check",session.respond("prose")); self.assertEqual(client.calls,[])
        self.assertIn("session universe",model.inputs[2][-1]["content"])
    def test_checked_status_is_engine_result_and_failed_recheck_clears_it(self):
        client=Client(); client.results=iter([{"structuredContent":{"result":{"status":"checked_candidate"}},"content":[]},ProtocolError({"message":"stale context"})])
        model=Model(call("universe_check_changes"),call("universe_check_changes"),"Everything consistent.")
        session=self.session(model,client)
        self.assertIn("no completed change check",session.respond("prose"))
        self.assertIn("stale context",model.inputs[2][-1]["content"])
    def test_backend_report_overrides_false_model_publication_or_creation(self):
        client=Client();client.results=iter([{"structuredContent":{"result":{"status":"needs_clarification","additions":["New object: silver pistol"],"excluded":["Mara plan: plan claim"],"clarifications":["Which owner?"],"unknowns":[],"unchanged":[]}},"content":[]}])
        session=self.session(Model(call("universe_check_changes"),"Canon updated. Mara introduced."),client)
        reply=session.respond("prose")
        self.assertIn("not published",reply);self.assertIn("Tentative held suggestion: New object: silver pistol",reply)
        self.assertNotIn("Canon updated",reply);self.assertNotIn("Mara introduced",reply);self.assertIn("Which owner?",reply)
    def test_empty_delta_cannot_hide_prior_pending_candidate(self):
        client=Client(); client.results=iter([{"structuredContent":{"result":{"status":"checked_candidate","candidate_handle":"opaque"}},"content":[]},{"structuredContent":{"result":{"status":"no_changes"}},"content":[]}])
        session=self.session(Model(call("universe_check_changes"),call("universe_check_changes"),"No changes."),client)
        self.assertIn("no completed change check",session.respond("prose"))
        self.assertIn("prior uncommitted candidate",session.messages[-2]["content"])
    def test_success_conflict_and_unknown_status_labels(self):
        for status,label in (("checked_candidate","Candidate checked"),("conflict","Continuity conflict"),("incomplete","check incomplete")):
            client=Client(); client.results=iter([{"structuredContent":{"result":{"status":status}},"content":[]}])
            session=self.session(Model(call("universe_check_changes"),"Bounded result."),client)
            self.assertIn(label,session.respond("prose"))
    def test_repeated_error_stops_without_publication(self):
        session=self.session(Model(call("universe_commit"),call("universe_commit")))
        self.assertIsNone(session.respond("prose")); self.assertEqual(session.client.calls,[])
    def test_text_structured_parity_failure_is_incomplete(self):
        client=Client();client.results=iter([{"structuredContent":{},"content":[{"type":"text","text":"{\"other\":true}"}]}])
        session=self.session(Model(call()),client)
        self.assertIsNone(session.respond("prose"))
    def test_native_parser_union_and_reference_type_hints(self):
        from mlx_lm.tool_parsers.qwen3_coder import parse_tool_call
        shape={"$defs":{"Focus":{"type":"object","properties":{"world":{"type":"string"}}}},"oneOf":[{"type":"object","properties":{"mode":{"const":"one","type":"string"},"focus":{"$ref":"#/$defs/Focus"},"ids":{"type":"array","items":{"type":"string"}}}}]}
        tools=[{"type":"function","function":{"name":"research","parameters":AuthorSession.native_parameters(shape)}}]
        text='<function=research>\n<parameter=mode>one</parameter>\n<parameter=focus>{"world":"Here"}</parameter>\n<parameter=ids>["a","b"]</parameter>\n</function>'
        parsed=parse_tool_call(text,tools)
        self.assertEqual(parsed["arguments"]["focus"],{"world":"Here"});self.assertEqual(parsed["arguments"]["ids"],["a","b"])
if __name__=="__main__": unittest.main()

"""Functional session regressions; conversations remain in memory."""
import copy
import io
import json
import unittest
from author_session import AuthorSession, AuthorDecisions, ProtocolError, passages
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
        client=Client(); client.results=iter([{"structuredContent":{"result":{"status":"checked_candidate","candidate_handle":"opaque"}},"content":[]},ProtocolError({"message":"stale context"})])
        model=Model(Generation("native checks",0,0,False,call("universe_check_changes").tool_calls*2),"Everything consistent.")
        session=self.session(model,client)
        self.assertIn("no completed change check",session.respond("prose"))
        self.assertIn("stale context",model.inputs[1][-1]["content"])
    def test_absent_check_gets_one_procedural_reminder_without_supplied_delta(self):
        model=Model(call(),"Already unchanged.",call("universe_check_changes"),"Checked.")
        session=self.session(model)
        self.assertIn("Candidate checked",session.respond("Ordinary author prose"))
        reminder=model.inputs[2][-1]["content"]
        self.assertIn("no engine writing check",reminder)
        self.assertNotIn("changes",reminder)
        self.assertEqual(sum("no engine writing check" in m.get("content","") for m in session.messages),1)
    def test_reminder_is_bounded_and_cannot_convert_missing_check_to_success(self):
        session=self.session(Model("It is consistent.","It is still consistent."))
        self.assertIn("no completed change check",session.respond("Author prose"))
        self.assertIsNone(session.last_check)

    def test_backend_report_overrides_false_model_publication_or_creation(self):
        client=Client();client.results=iter([{"structuredContent":{"result":{"status":"needs_clarification","additions":["New object: silver pistol"],"excluded":["Mara plan: plan claim"],"clarifications":["Which owner?"],"unknowns":[],"unchanged":[]}},"content":[]}])
        session=self.session(Model(call("universe_check_changes"),"Canon updated. Mara introduced."),client)
        reply=session.respond("prose")
        self.assertIn("not published",reply);self.assertIn("Tentative held suggestion: New object: silver pistol",reply)
        self.assertNotIn("Canon updated",reply);self.assertNotIn("Mara introduced",reply);self.assertIn("Which owner?",reply)
    def test_empty_delta_cannot_hide_prior_pending_candidate(self):
        client=Client(); client.results=iter([{"structuredContent":{"result":{"status":"checked_candidate","candidate_handle":"opaque"}},"content":[]},{"structuredContent":{"result":{"status":"no_changes"}},"content":[]}])
        session=self.session(Model(Generation("native checks",0,0,False,call("universe_check_changes").tool_calls*2),"No changes."),client)
        self.assertIn("no completed change check",session.respond("prose"))
        self.assertIn("prior uncommitted candidate",session.messages[-2]["content"])
    def test_success_conflict_and_unknown_status_labels(self):
        for status,label in (("checked_candidate","Candidate checked"),("conflict","Continuity conflict"),("incomplete","check incomplete")):
            client=Client(); client.results=iter([{"structuredContent":{"result":{"status":status}},"content":[]}])
            session=self.session(Model(call("universe_check_changes"),"Bounded result."),client)
            self.assertIn(label,session.respond("prose"))
    def test_completed_candidate_returns_backend_report_without_more_generation(self):
        client=Client(); client.results=iter([{"structuredContent":{"result":{"status":"checked_candidate","candidate_handle":"opaque","additions":["Occurred action: authored action"],"validation":{"execution":{"coverage":"complete"}},"impact":{"coverage":"complete"}}},"content":[]}])
        model=Model(call("universe_check_changes"))
        session=self.session(model,client)
        reply=session.respond("Author passage")
        self.assertIn("Candidate checked; not published",reply)
        self.assertIn("Occurred action: authored action",reply)
        self.assertEqual(len(model.inputs),1)
        self.assertEqual(session.last_check["candidate_handle"],"opaque")
        self.assertEqual(len(client.calls),1)

    def test_completed_batch_reports_the_latest_changed_delta(self):
        client=Client()
        shape=next(t["inputSchema"] for t in client.tools if t["name"]=="universe_check_changes")
        shape["properties"]["changes"]={"type":"array","items":{"type":"object"}}
        client.results=iter([{"structuredContent":{"result":{"status":"checked_candidate","candidate_handle":handle}},"content":[]} for handle in ("earlier","latest")])
        first=call("universe_check_changes",{"universe":"Story","changes":[{"name":"Object","facts":[{"property":"colour","value":"green"}]}]})
        second=call("universe_check_changes",{"universe":"Story","changes":[{"name":"Object","facts":[{"property":"colour","value":"blue"}]}]})
        model=Model(Generation("native checks",0,0,False,first.tool_calls+second.tool_calls))
        session=self.session(model,client)
        self.assertIn("Candidate checked",session.respond("Author passage"))
        self.assertEqual(session.last_check["candidate_handle"],"latest")
        self.assertEqual(client.calls[-1]["arguments"],second.tool_calls[0]["arguments"])
        self.assertEqual(len(model.inputs),1)

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

class AuthorDecisionTests(unittest.TestCase):
    def controller(self):
        from types import SimpleNamespace
        session=SimpleNamespace(universe="Story",last_check=None,last_passage="Original author prose",messages=[{"role":"system","content":"guidance"},{"role":"user","content":"setup"},{"role":"tool","content":"old pinned state"}])
        session.dispatch=lambda name,args: {"structuredContent":{"result":{"context_id":"fresh-context"}}}
        session.respond=lambda text: setattr(session,"last_passage",text)
        output=[]
        controller=AuthorDecisions(session,"private binary","installation","secret-author",output.append)
        calls=[]
        controller.action=lambda args: calls.append(copy.deepcopy(args)) or {"result":{"operation_id":"op_"+"1"*24,"proposal_id":"prp_"+"2"*24,"revision":"rev_"+"3"*24},"frame":{"continuity":"continuity","context":{"record":"context"}}}
        return controller,session,calls,output
    def test_questions_hold_and_natural_clarification_keeps_author_bytes(self):
        controller,session,calls,_=self.controller()
        session.last_check={"clarifications":["Who took it?"],"candidate_handle":None}
        with self.assertRaises(ValueError): controller.handle("/review")
        self.assertFalse(calls)
        controller.handle("Mara took it.")
        self.assertEqual(session.last_passage,"Original author prose\n\nAuthor clarification:\nMara took it.")
    def test_exact_review_separate_approval_recovery_and_fresh_context(self):
        import base64,json
        controller,session,calls,output=self.controller()
        controller.review={"publishable":True,"candidate":{"proposal_id":"prp_"+"2"*24,"version":2,"digest":"exact"},"validation":{"execution":{"run_id":"exact-run"}}}
        controller.publish_key="original-key"
        controller.handle("/approve")
        self.assertEqual(calls[0]["candidate"]["digest"],"exact")
        self.assertEqual(calls[0]["idempotency_key"],"original-key")
        token=output[0].split("/recover ",1)[1]
        self.assertEqual(json.loads(base64.urlsafe_b64decode(token)),calls[0])
        self.assertNotIn("secret-author",token)
        self.assertNotIn("old pinned state",str(session.messages))
        controller.handle("/recover "+token)
        self.assertEqual(calls[0],calls[1])
    def test_private_review_resolves_restricted_opaque_handle_without_versions(self):
        controller,session,calls,_=self.controller()
        session.last_check={"candidate_handle":"opaque-candidate","validation":{"kind":"restricted"},"clarifications":[]}
        def private(args):
            calls.append(args)
            return {"candidate":{"proposal_id":"opaque-candidate","version":2,"digest":"exact"},"publishable":False,"summary":["Actual candidate requires author review"]}
        controller.action=private
        controller.handle("/review")
        self.assertEqual(calls[0]["candidate"],"opaque-candidate")
        self.assertNotIn("version",calls[0])
        with self.assertRaises(ValueError): controller.handle("/approve")

    def test_review_reports_actual_impact_and_validation_limits(self):
        controller,_,_,output=self.controller()
        controller.review={"candidate":{"digest":"exact"},"publishable":False,
            "impact":{"coverage":"restricted","records":["visible"]},
            "validation":{"execution":{"findings":[],"unsupported_capabilities":["unmapped chronology"]}}}
        controller.show_review()
        self.assertIn("Impact unresolved: coverage restricted; affected dependencies may be incomplete.",output)
        self.assertIn("Validation limitation: unmapped chronology",output)
        self.assertNotIn("Ready for exact approval.",output)
        output.clear(); controller.review["impact"]={"coverage":"complete","records":["one","two"]}
        controller.show_review()
        self.assertIn("Impact coverage: complete; 2 related records.",output)
        output.clear(); controller.review.pop("impact")
        controller.show_review()
        self.assertIn("Impact unresolved: coverage unavailable; affected dependencies may be incomplete.",output)

    def test_missing_receipt_never_claims_publication(self):
        controller,session,_,output=self.controller()
        controller.review={"publishable":True,"candidate":{"proposal_id":"prp_"+"2"*24},"validation":{"execution":{"run_id":"run"}}}
        controller.publish_key="original-key"
        controller.action=lambda _: {"result":{"status":"pending"}}
        with self.assertRaises(RuntimeError): controller.handle("/approve")
        self.assertFalse(any(line=="Author-approved changes published." for line in output))
        self.assertEqual(controller.publish_key,"original-key")

    def test_failed_publication_retains_exact_review_and_key(self):
        controller,session,_,output=self.controller()
        controller.review={"publishable":True,"candidate":{"digest":"exact"},"validation":{"execution":{"run_id":"run"}}}
        controller.publish_key="same-key"
        def interrupted(args): raise RuntimeError("interrupted")
        controller.action=interrupted
        with self.assertRaises(RuntimeError): controller.handle("/approve")
        self.assertEqual(controller.publish_key,"same-key")
        self.assertEqual(controller.review["candidate"]["digest"],"exact")
        self.assertTrue(output[0].startswith("If interrupted"))

if __name__=="__main__": unittest.main()

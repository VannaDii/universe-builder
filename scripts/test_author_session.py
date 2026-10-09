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

    def test_knowledge_decision_is_private_explicit_and_not_published(self):
        import json
        controller,session,calls,_=self.controller()
        session.tool_calls=[("universe_check_changes",{"context_id":"selected"},{"isError":False})]
        session.last_check={"clarifications":["Explicit author decision needed"],"candidate_handle":None}
        controller.action=lambda args: calls.append(args) or {"candidate":{"proposal_id":"knowledge-candidate","digest":"exact"},"publishable":False,"summary":[]}
        original=copy.deepcopy(session.messages)
        controller.handle('/establish-knowledge '+json.dumps({"holder":"Reader","claim":{"subject":"Door","property":"code","value":"blue"},"at_tick":"2","lifetime":{"kind":"until_changed"},"rationale":"My explicit decision"}))
        self.assertEqual(calls[0]["action"],"establish_knowledge")
        self.assertEqual(calls[0]["context_id"],"selected")
        self.assertEqual(calls[0]["text"],session.last_passage)
        self.assertEqual(calls[0]["rationale"],"My explicit decision")
        self.assertEqual(session.messages,original)
        self.assertNotIn("publish",[c["action"] for c in calls])
        with self.assertRaises(ValueError):controller.handle("/approve")

    def test_contract_declaration_review_is_explicit_and_approval_is_separate(self):
        controller,session,calls,_=self.controller()
        session.last_check={"candidate_handle":"contract-candidate","clarifications":[]}
        controller.action=lambda args: calls.append(args) or {"candidate":{"proposal_id":"contract-candidate","digest":"exact"},"publishable":False,"summary":[]}
        controller.handle("/review-contracts")
        self.assertEqual(calls[0]["action"],"prepare_contracts")
        self.assertEqual(calls[0]["text"],session.last_passage)
        with self.assertRaises(ValueError): controller.handle("/approve")

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

class ConnectedWritingTests(unittest.TestCase):
    def test_default_mcp_story_review_history_and_dependent_correction(self):
        """Real ordinary MCP calls and separate authenticated author decisions; no inference."""
        import os
        import subprocess
        import tempfile
        import time
        from pathlib import Path
        from types import SimpleNamespace
        from mcp_smoke import MCP
        binaries=Path(os.environ.get("UB_TEST_BIN_DIR",Path(__file__).resolve().parents[1]/"target/debug")).resolve()
        if not all((binaries/name).is_file() for name in ("universe","universe-engine","universe-mcp")):
            self.skipTest("Build existing CLI/engine/MCP binaries for installed integration")
        with tempfile.TemporaryDirectory(prefix="ub-connected-writing-",dir="/tmp") as temp:
            installation=Path(temp)/"installation"
            def cli(*args,profile=None):
                argv=[str(binaries/"universe"),"--installation",str(installation)]
                if profile: argv.extend(["--profile",profile])
                result=subprocess.run([*argv,*args],capture_output=True,text=True,timeout=30)
                self.assertEqual(result.returncode,0,result.stderr)
                return result.stdout.strip()
            author=cli("init");client=None
            try:
                universe=json.loads(cli("create","Story","--first-time","0","--calendar","Days","--tick-label","days",profile=author))
                agent=json.loads(cli("enroll",profile=author))["profile_id"]
                cli("grant",agent,universe["universe_id"],"--propose","--edit","--protected",profile=author)
                client=MCP(binaries/"universe-mcp",installation=installation,profile=agent)
                tools={t["name"] for t in client.request("tools/list",{})["tools"]}
                self.assertEqual(len(tools),11)
                self.assertTrue({"universe_check_changes","universe_read_facts","universe_read_contracts"}<=tools)
                self.assertTrue({"universe_propose","universe_validate","universe_get"}.isdisjoint(tools))
                decisions=AuthorDecisions(SimpleNamespace(universe="Story"),binaries/"universe",installation,author,output=lambda _:None)
                def context(tick=None,revision=None):
                    temporal={"kind":"timeless"} if tick is None else {"kind":"at","time":{"kind":"exact","calendar":calendar,"value":str(tick)}}
                    return client.call("universe_open_context",{"universe":"Story","continuity_id":universe["continuity_id"],"revision":revision or {"kind":"head"},"represented_context":universe["context_id"],"temporal_query":temporal,"temporal_systems":[],"perspective":"author"})["result"]["context_id"]
                def check(ctx,**delta):
                    return client.call("universe_check_changes",{"universe":"Story","context_id":ctx,**delta})["result"]
                def publish(checked,text,key,contracts=False):
                    self.assertEqual(checked["status"],"checked_candidate",checked)
                    reviewed=decisions.action({"action":"prepare_contracts" if contracts else "prepare","candidate":checked["candidate_handle"],"label":"Story passage","text":text})
                    self.assertTrue(reviewed["publishable"],reviewed)
                    args={"action":"publish","candidate":reviewed["candidate"],"validation_run":reviewed["validation"]["execution"]["run_id"],"idempotency_key":key}
                    receipt=decisions.action(args)
                    self.assertEqual(decisions.action(args)["result"],receipt["result"])
                    return receipt["result"]["revision"]
                initial=context()
                setup=check(initial,
                    properties=[{"name":"code","introduce":True,"value_type":"text","single_value":True,"persistence":"explicit_interval"},{"name":"locked","introduce":True,"value_type":"boolean","single_value":True,"persistence":"explicit_interval"},{"name":"entrance","introduce":True,"value_type":"object","single_value":False,"persistence":"unspecified"}],
                    changes=[{"name":name,"introduce":True,"facts":([{ "property":"code","value":"green","scope":"universe","at_tick":"0","lifetime":{"kind":"until","end_tick":"20"}},{"property":"locked","value":False,"scope":"universe","at_tick":"0","lifetime":{"kind":"until","end_tick":"20"}}] if name=="Courtyard" else [])} for name in ("Courtyard","Main gate","Side gate","Key","Mara","Leon")],
                    exhaustive_sets=[{"subject":"Courtyard","property":"entrance","members":["Main gate"],"scope":"universe","at_tick":"0","lifetime":{"kind":"until","end_tick":"20"}}],
                    relation_definitions=[{"name":"ownership","introduce":True,"roles":[{"name":"item","multiple":False},{"name":"owner","multiple":False}]}],
                    relation_limits=[{"name":"one key owner","relation":"ownership","grouping":{"kind":"role","role":"item"},"counted_role":"owner","maximum":1,"scope":"universe","at_tick":"0","lifetime":{"kind":"until","end_tick":"20"}}],
                    relationships=[{"relation":"ownership","subject":"Key","participants":{"item":["Key"],"owner":["Mara"]},"scope":"universe","at_tick":"0","lifetime":{"kind":"until","end_tick":"20"}}],
                    actions=[{"name":"enter","introduce":True,"scope":"universe","requirements":[{"role":"place","property":"locked","value":False}]},{"name":"knock","introduce":True,"scope":"universe"}],
                    knowledge_policies=[{"kind":"knowledge","name":"interpreted messages","mode":"justified"},{"kind":"channel","name":"spoken timing","channel":"speech","forward_only":True,"minimum_delay":"0","maximum_delay":"3"}])
                publish(setup,"Before day twenty the courtyard's green code and unlocked gate apply. The main gate is its only entrance. Mara owns the key, with one owner at a time. Enter requires an unlocked place; knock has no such requirement. Knowledge requires justified interpreted messages. Spoken messages move forward with zero to three authored days of delay.","connected-setup",contracts=True)
                current=context()
                facts=client.call("universe_read_facts",{"universe":"Story","context_id":current,"object_names":["Courtyard"]})["result"]
                calendar=facts["clocks"][0]["calendar_id"]
                canon=context(5)
                limits=client.call("universe_read_contracts",{"universe":"Story","context_id":canon})["result"]
                self.assertEqual(limits["exhaustive_sets"][0]["members"],["Main gate"])
                self.assertEqual(limits["relation_limits"][0]["maximum"],1)
                boundary=check(canon,changes=[{"name":"Courtyard","facts":[{"property":"entrance","value":{"object":"Side gate"},"scope":"universe","at_tick":"5"}]}])
                self.assertEqual(boundary["status"],"conflict",boundary)
                ownership=check(canon,relationships=[{"relation":"ownership","subject":"Key","participants":{"item":["Key"],"owner":["Leon"]},"scope":"universe","at_tick":"5","lifetime":{"kind":"until","end_tick":"10"}}])
                self.assertEqual(ownership["status"],"conflict",ownership)
                claim={"subject":"Courtyard","property":"code","value":"green"}
                speech=check(context(),messages=[{"label":"true code","from":"Leon","to":["Mara"],"received_by":["Mara"],"understood_by":["Mara"],"claim":claim,"channel":"speech","sent_tick":"1","received_tick":"2"},{"label":"lie","from":"Leon","to":["Mara"],"received_by":["Mara"],"claim":{**claim,"value":"red"},"channel":"speech","sent_tick":"3","received_tick":"3"}],attitudes=[{"holder":"Mara","attitude":"knows","claim":claim,"message":"true code","at_tick":"2","lifetime":{"kind":"until","end_tick":"10"}},{"holder":"Mara","attitude":"believes","claim":{**claim,"value":"red"},"at_tick":"3","lifetime":{"kind":"until","end_tick":"10"}}])
                publish(speech,"Leon tells Mara the green code at day one; she receives and understands it at day two and knows it until day ten. At day three he falsely says red, which she believes.","connected-speech")
                pre_action=context(5)
                truth=client.call("universe_read_facts",{"universe":"Story","context_id":pre_action,"object_names":["Courtyard"]})["result"]["objects"][0]
                self.assertTrue(any(f["property"]=="code" and f["value"]=="green" and f["state"]=="supported" for f in truth["facts"]))
                self.assertFalse(any(f["property"]=="code" and f["value"]=="red" and f["state"]=="supported" for f in truth["facts"]))
                entered=check(context(),events=[{"action":"enter","participants":{"place":"Courtyard"},"at_tick":"5","requires_knowledge":[{"holder":"Mara","claim":claim}]}])
                action_revision=publish(entered,"At day five Mara enters the courtyard, relying on her knowledge of the code.","connected-enter")
                fresh=context(5)
                obj=client.call("universe_read_facts",{"universe":"Story","context_id":fresh,"object_names":["Courtyard"]})["result"]["objects"][0]
                locked=next(f for f in obj["facts"] if f["property"]=="locked")
                event=next(e for e in obj["occurred_events"] if e["action"]=="enter")
                attributed=client.call("universe_read_contracts",{"universe":"Story","context_id":fresh})["result"]["attitudes"]
                self.assertTrue(any(a["holder"]=="Mara" and a["attitude"]=="believes" and a["claim"]["value"]=="red" for a in attributed),attributed)
                self.assertTrue(any(a["holder"]=="Mara" and a["attitude"]=="knows" and a["claim"]["value"]=="green" for a in attributed),attributed)
                correction={"fact_handle":locked["fact_handle"],"value":True,"reason":"The courtyard was locked during the same authored interval."}
                denied=client.request("tools/call",{"name":"universe_check_changes","arguments":{"universe":"Story","context_id":fresh,"corrections":[correction]}})
                self.assertTrue(denied.get("isError"),denied)
                self.assertIn("requirement",str(denied).lower())
                unchanged=client.call("universe_read_facts",{"universe":"Story","context_id":context(5),"object_names":["Courtyard"]})
                self.assertEqual(unchanged["frame"]["revision"],action_revision)
                corrected=check(fresh,corrections=[correction],event_corrections=[{"event_handle":event["handle"],"action":"knock","reason":"The author corrects the dependent action to knocking; retained knowledge remains attributed."}])
                publish(corrected,"The courtyard was locked; at day five Mara knocked instead of entering, still relying on her code knowledge.","connected-correction")
                after=context(5)
                updated=client.call("universe_read_facts",{"universe":"Story","context_id":after,"object_names":["Courtyard"]})["result"]["objects"][0]
                self.assertTrue(any(f["property"]=="locked" and f["value"] is True and f["state"]=="supported" for f in updated["facts"]))
                self.assertTrue(any(e["action"]=="knock" for e in updated["occurred_events"]))
                current_locked=next(f for f in updated["facts"] if f["property"]=="locked")
                self.assertNotEqual(current_locked["fact_handle"],locked["fact_handle"])
                stale_fact=check(after,corrections=[correction])
                self.assertEqual(stale_fact["status"],"needs_clarification",stale_fact)
                for field in ("candidate_handle","validation","impact"):
                    self.assertIsNone(stale_fact[field],stale_fact)
                current_correction=check(after,corrections=[{"fact_handle":current_locked["fact_handle"],"value":False,"reason":"An explicit correction uses the newly researched version."}])
                self.assertEqual(current_correction["status"],"checked_candidate",current_correction)
                historical=context(5,{"kind":"exact","revision_id":action_revision})
                old=client.call("universe_read_facts",{"universe":"Story","context_id":historical,"object_names":["Courtyard"]})["result"]["objects"][0]
                self.assertTrue(any(f["property"]=="locked" and f["value"] is False and f["state"]=="supported" for f in old["facts"]))
                self.assertTrue(any(e["action"]=="enter" for e in old["occurred_events"]))
                self.assertEqual(next(f for f in old["facts"] if f["property"]=="locked")["fact_handle"],locked["fact_handle"])
                expired=check(context(),events=[{"action":"knock","participants":{"place":"Courtyard"},"at_tick":"11","requires_knowledge":[{"holder":"Mara","claim":claim}]}])
                self.assertNotEqual(expired["status"],"checked_candidate",expired)
                self.assertEqual(expired["validation"]["kind"],"evaluated",expired)
                self.assertTrue(any(f["outcome"] in {"refuted","conflicting","not_established"} for f in expired["validation"]["execution"]["findings"]),expired)
                relationships=client.call("universe_read_contracts",{"universe":"Story","context_id":context()})["result"]["relationships"]
                original=next(r for r in relationships if r["subject"]=="Key")["relationship_handle"]
                new_owner={"relation":"ownership","subject":"Key","participants":{"item":["Key"],"owner":["Leon"]},"scope":"universe","at_tick":"10","lifetime":{"kind":"until","end_tick":"20"}}
                overlapping=check(context(),relationships=[new_owner])
                self.assertEqual(overlapping["status"],"conflict",overlapping)
                transfer=check(context(),relationship_endings=[{"relationship_handle":original,"end_tick":"10","reason":"Mara's ownership ends at the explicitly authored transfer."}],relationships=[new_owner])
                transfer_revision=publish(transfer,"At day ten Mara's ownership of the key ends and Leon owns it until day twenty.","connected-transfer")
                transferred=context()
                stale=check(transferred,relationship_endings=[{"relationship_handle":original,"end_tick":"9","reason":"An old handle must not edit the newer relationship."}])
                self.assertIsNone(stale["candidate_handle"],stale)
                self.assertEqual(stale["status"],"needs_clarification")
                rows=client.call("universe_read_contracts",{"universe":"Story","context_id":context(15)})["result"]["relationships"]
                current_owner=next(r for r in rows if r["subject"]=="Key")
                self.assertTrue(any(p["role"]=="owner" and p["object"]=="Leon" for p in current_owner["participants"]))
                correction=check(context(),relationship_corrections=[{"relationship_handle":current_owner["relationship_handle"],"participants":{"owner":["Mara"]},"reason":"The historical recipient was Mara rather than Leon."}])
                publish(correction,"The author corrects the recorded day-ten recipient to Mara; the key and interval are unchanged.","connected-owner-correction")
                rows=client.call("universe_read_contracts",{"universe":"Story","context_id":context(15)})["result"]["relationships"]
                corrected_owner=next(r for r in rows if r["subject"]=="Key")
                self.assertEqual(corrected_owner["scope"],current_owner["scope"])
                self.assertEqual(corrected_owner["time"],current_owner["time"])
                self.assertTrue(any(p["role"]=="owner" and p["object"]=="Mara" for p in corrected_owner["participants"]))
                self.assertTrue(any(p["role"]=="item" and p["object"]=="Key" for p in corrected_owner["participants"]))
                old=client.call("universe_read_contracts",{"universe":"Story","context_id":context(15,{"kind":"exact","revision_id":transfer_revision})})["result"]["relationships"]
                self.assertTrue(any(p["role"]=="owner" and p["object"]=="Leon" for r in old for p in r["participants"]))
                ended=check(context(),relationship_endings=[{"relationship_handle":corrected_owner["relationship_handle"],"end_tick":"15","reason":"The relationship explicitly ends at day fifteen."}])
                publish(ended,"Mara's ownership of the key ends at day fifteen.","connected-owner-ending")
                final=client.call("universe_read_contracts",{"universe":"Story","context_id":context(16)})["result"]["relationships"]
                self.assertFalse(any(r["subject"]=="Key" for r in final),final)
                tightened=check(context(),relation_limit_corrections=[{"name":"one key owner","maximum":0,"reason":"Explicit proposed tightening."}])
                self.assertEqual(tightened["status"],"conflict",tightened)
                self.assertEqual(tightened["validation"]["kind"],"evaluated",tightened)
                self.assertTrue(any(f["outcome"]=="refuted" for f in tightened["validation"]["execution"]["findings"]),tightened)
                role_edit=check(context(),relation_corrections=[{"name":"ownership","roles":[{"name":"owner","ordered":True}],"reason":"Explicitly order owner participants."}])
                with self.assertRaises(RuntimeError):
                    decisions.action({"action":"prepare","candidate":role_edit["candidate_handle"],"label":"Role edit","text":"Owners are ordered."})
                staged=decisions.action({"action":"prepare_contracts","candidate":role_edit["candidate_handle"],"label":"Role edit","text":"Owners are ordered."})
                self.assertTrue(any("owner (Single, ordered true, participant types unrestricted)" in line for line in staged["summary"]),staged["summary"])
                limit_edit=check(context(),relation_limit_corrections=[{"name":"one key owner","maximum":2,"reason":"Explicitly allow two owners."}])
                limit_revision=publish(limit_edit,"A key may have two owners during the same authored interval.","connected-limit-revision",contracts=True)
                with self.assertRaises(RuntimeError):
                    decisions.action({"action":"publish","candidate":staged["candidate"],"validation_run":staged["validation"]["execution"]["run_id"],"idempotency_key":"stale-role-publication"})
                publish(check(context(),relation_corrections=[{"name":"ownership","roles":[{"name":"owner","ordered":True,"multiple":True}],"reason":"Explicitly order multiple owners."}]),"The owner role is multiple and ordered; the item role is unchanged.","connected-role-revision",contracts=True)
                updated=client.call("universe_read_contracts",{"universe":"Story","context_id":context()})["result"]
                definition=next(r for r in updated["relations"] if r["name"]=="ownership")
                item=next(r for r in definition["roles"] if r["name"]=="item")
                owner=next(r for r in definition["roles"] if r["name"]=="owner")
                self.assertFalse(item["multiple"]);self.assertFalse(item["ordered"]);self.assertEqual(item["participant_types"],[])
                self.assertTrue(owner["multiple"]);self.assertTrue(owner["ordered"])
                limit=next(r for r in updated["relation_limits"] if r["name"]=="one key owner")
                self.assertEqual(limit["maximum"],2);self.assertEqual(limit["grouping"],{"kind":"role","role":"item"});self.assertEqual(limit["counted_role"],"owner");self.assertEqual(limit["scope"],limits["relation_limits"][0]["scope"]);self.assertEqual(limit["time"],limits["relation_limits"][0]["time"])
                historical=client.call("universe_read_contracts",{"universe":"Story","context_id":context(revision={"kind":"exact","revision_id":limit_revision})})["result"]
                historical_owner=next(r for r in historical["relations"] if r["name"]=="ownership")["roles"][1]
                self.assertFalse(historical_owner["ordered"]);self.assertFalse(historical_owner["multiple"])
                joint=check(context(),relationships=[{**new_owner,"at_tick":"20","lifetime":{"kind":"until","end_tick":"30"},"participants":{"item":["Key"],"owner":["Mara","Leon"]}}])
                publish(joint,"Mara and Leon jointly own the key from day twenty to thirty.","connected-joint")
                denied=client.call("universe_check_changes",{"universe":"Story","context_id":context(),"relation_corrections":[{"name":"ownership","roles":[{"name":"owner","multiple":False}],"reason":"Proposed single-owner role contradicts committed joint ownership."}]},error=True)
                self.assertEqual(denied["code"],"INVALID_ARGUMENT",denied)
                self.assertIn("single role has multiple participants",denied["message"])
                preserved=client.call("universe_read_contracts",{"universe":"Story","context_id":context()})["result"]
                self.assertTrue(next(r for r in preserved["relations"] if r["name"]=="ownership")["roles"][1]["multiple"])
                alias={"object":"Courtyard","text":"Garden","language":"en","community":"locals","role":"nickname","at_tick":"10","lifetime":{"kind":"until","end_tick":"12"}}
                alias_revision=publish(check(context(),aliases=[alias]),"Locals call the courtyard Garden from day ten until day twelve.","connected-alias")
                aliased=client.call("universe_read_facts",{"universe":"Story","context_id":context(11),"object_names":["Courtyard","Garden"]})["result"]["objects"]
                self.assertEqual(aliased[0]["names"],aliased[1]["names"])
                self.assertEqual(aliased[0]["facts"],aliased[1]["facts"])
                self.assertTrue(any(n["text"]=="Garden" and n["community"]=="locals" and n["role"]=="nickname" for n in aliased[1]["names"]))
                repeated=check(context(),aliases=[alias])
                self.assertEqual(repeated["status"],"no_changes",repeated)
                self.assertIsNone(repeated["candidate_handle"])
                expired=client.call("universe_read_facts",{"universe":"Story","context_id":context(13),"object_names":["Garden","Courtyard"]})["result"]["objects"]
                self.assertEqual(expired[0]["identity"],"not_found")
                self.assertFalse(any(n["text"]=="Garden" for n in expired[1]["names"]))
                earlier=client.call("universe_read_facts",{"universe":"Story","context_id":context(11,{"kind":"exact","revision_id":limit_revision}),"object_names":["Garden"]})["result"]["objects"]
                self.assertEqual(earlier[0]["identity"],"not_found")
                publish(check(context(),aliases=[{**alias,"object":"Key"}]),"Locals also call the key Garden during that same interval.","connected-ambiguous-alias")
                ambiguous=check(context(11),aliases=[{"object":"Garden","text":"Guess"}])
                self.assertEqual(ambiguous["status"],"needs_clarification",ambiguous)
                self.assertIsNone(ambiguous["candidate_handle"])
                historical=client.call("universe_read_facts",{"universe":"Story","context_id":context(11,{"kind":"exact","revision_id":alias_revision}),"object_names":["Garden"]})["result"]["objects"]
                self.assertEqual(historical[0]["facts"],aliased[0]["facts"])
                names=[{"object":"Mara","text":"Red Fox"},{"object":"Leon","text":"Silver Fox"},{"object":"Key","text":"Golden Key"}]
                named_revision=publish(check(context(),aliases=names),"Mara is Red Fox; Leon is Silver Fox; the key is Golden Key. These aliases establish no communication or knowledge.","connected-relationship-aliases")
                joint=next(r for r in client.call("universe_read_contracts",{"universe":"Story","context_id":context(25)})["result"]["relationships"] if r["subject"]=="Key")
                patch={"relationship_handle":joint["relationship_handle"],"participants":{"owner":["Silver Fox"]},"reason":"The author explicitly clarifies that Leon alone owned the key during the original interval."}
                held=check(context(25),questions=["Which established owner is intended?"],relationship_corrections=[patch])
                self.assertEqual(held["status"],"needs_clarification",held)
                self.assertIsNone(held["candidate_handle"]);self.assertIsNone(held["validation"]);self.assertIsNone(held["impact"])
                publish(check(context(25),relationship_corrections=[patch]),"Author clarification: Silver Fox, meaning Leon, alone owned Golden Key from day twenty to thirty.","connected-clarified-alias-correction")
                corrected=next(r for r in client.call("universe_read_contracts",{"universe":"Story","context_id":context(25)})["result"]["relationships"] if r["subject"]=="Key")
                self.assertEqual(corrected["time"],joint["time"]);self.assertEqual(corrected["scope"],joint["scope"])
                self.assertEqual([p["object"] for p in corrected["participants"] if p["role"]=="owner"],["Leon"])
                transferred=check(context(25),relationship_endings=[{"relationship_handle":corrected["relationship_handle"],"end_tick":"25","reason":"Explicit authored transfer to Red Fox at day twenty-five."}],relationships=[{"relation":"ownership","subject":"Golden Key","participants":{"item":["Golden Key"],"owner":["Red Fox"]},"scope":"universe","at_tick":"25","lifetime":{"kind":"until","end_tick":"30"}}])
                publish(transferred,"At day twenty-five Silver Fox's ownership ends and Red Fox, meaning Mara, owns Golden Key until day thirty.","connected-alias-transfer")
                for tick,owner in ((24,"Leon"),(26,"Mara")):
                    current=next(r for r in client.call("universe_read_contracts",{"universe":"Story","context_id":context(tick)})["result"]["relationships"] if r["subject"]=="Key")
                    self.assertEqual([p["object"] for p in current["participants"] if p["role"]=="owner"],[owner])
                    self.assertEqual([p["object"] for p in current["participants"] if p["role"]=="item"],["Key"])
                original=next(r for r in client.call("universe_read_contracts",{"universe":"Story","context_id":context(26,{"kind":"exact","revision_id":named_revision})})["result"]["relationships"] if r["subject"]=="Key")
                self.assertEqual({p["object"] for p in original["participants"] if p["role"]=="owner"},{"Mara","Leon"})


                # Possession powers use an authored holder property, not ownership relations.
                power=check(context(),properties=[{"name":"holder","introduce":True,"value_type":"object","single_value":True,"persistence":"explicit_interval"},{"name":"night_sight","introduce":True,"value_type":"boolean","single_value":True,"persistence":"explicit_interval"}],changes=[{"name":"Staff","introduce":True,"facts":[{"property":"holder","value":{"object":"Mara"},"scope":"universe","at_tick":"0","lifetime":{"kind":"until","end_tick":"10"}}]}],relationships=[{"relation":"ownership","subject":"Staff","participants":{"item":["Staff"],"owner":["Leon"]},"scope":"universe","at_tick":"0","lifetime":{"kind":"until","end_tick":"30"}}],item_powers=[{"item":"Staff","holder_property":"holder","ability_property":"night_sight","value":True,"scope":"universe","at_tick":"0","lifetime":{"kind":"until","end_tick":"20"}}])
                pending=json.loads(cli("library","Story",profile=author))["writing"]["proposals"]
                self.assertTrue(any("Staff — night_sight" in p["label"] for p in pending))
                with self.assertRaisesRegex(RuntimeError,"protected contracts require explicit author contract review"):
                    decisions.action({"action":"prepare","candidate":power["candidate_handle"],"label":"Forbidden factual review","text":"Holding this staff grants night sight."})
                power_revision=publish(power,"From zero until twenty, the Staff grants night sight to its explicit holder. Mara holds it from zero until ten; Leon owns it throughout zero to thirty, which does not establish possession.","connected-item-power",contracts=True)
                declaration=client.call("universe_read_contracts",{"universe":"Story","context_id":context(5)})["result"]["item_powers"]
                self.assertEqual(len(declaration),1)
                self.assertEqual((declaration[0]["item"],declaration[0]["holder_property"],declaration[0]["ability_property"]),("Staff","holder","night_sight"))
                def powers(tick,revision=None):
                    objects=client.call("universe_read_facts",{"universe":"Story","context_id":context(tick,revision),"object_names":["Mara","Leon"]})["result"]["objects"]
                    return {obj["name"] for obj in objects if any(f["property"]=="night_sight" and f["group"]=="derived" and f["state"]=="supported" and f["value"] is True for f in obj["facts"])}
                self.assertEqual(powers(5),{"Mara"})
                transfer_power=check(context(),changes=[{"name":"Staff","facts":[{"property":"holder","value":{"object":"Leon"},"scope":"universe","at_tick":"10","lifetime":{"kind":"until","end_tick":"15"}},{"property":"holder","value":{"object":"Mara"},"scope":"universe","at_tick":"20","lifetime":{"kind":"until","end_tick":"30"}}]}])
                publish(transfer_power,"Leon holds the Staff from ten until fifteen. Nobody is established as holder from fifteen until twenty. Mara holds it again from twenty until thirty, after its night-sight grant expires.","connected-power-transfer")
                self.assertEqual(powers(12),{"Leon"})
                self.assertEqual(powers(15),set())
                self.assertEqual(powers(20),set())
                self.assertEqual(powers(12,{"kind":"exact","revision_id":power_revision}),set())
                self.assertEqual(powers(5,{"kind":"exact","revision_id":power_revision}),{"Mara"})
                unknown=check(context(),item_powers=[{"item":"Missing staff","holder_property":"holder","ability_property":"night_sight","value":True,"scope":"universe","at_tick":"0"}])
                self.assertEqual(unknown["status"],"needs_clarification",unknown)
                self.assertIsNone(unknown["candidate_handle"])


                property_base=publish(check(context(),properties=[{"name":"tags","introduce":True,"value_type":"text","single_value":False,"persistence":"explicit_interval"}],changes=[{"name":"Key","facts":[{"property":"tags","value":value,"scope":"universe","at_tick":"30","lifetime":{"kind":"until","end_tick":"40"}} for value in ("red","blue")]}]),"The key has red and blue tags during thirty to forty.","connected-property-tags",contracts=True)
                denied=client.request("tools/call",{"name":"universe_check_changes","arguments":{"universe":"Story","context_id":context(),"property_corrections":[{"name":"tags","single_value":True,"reason":"Proposed single tag limit."}]}})
                conflict=denied["structuredContent"]["result"]
                self.assertEqual(conflict["status"],"conflict")
                self.assertTrue(any(f["outcome"]=="conflicting" for f in conflict["validation"]["execution"]["findings"]))
                review=decisions.action({"action":"prepare_contracts","candidate":conflict["candidate_handle"],"label":"Blocked multiplicity","text":"The key must have one tag during thirty to forty."})
                self.assertFalse(review["publishable"])
                self.assertEqual(client.call("universe_read_contracts",{"universe":"Story","context_id":context()})["frame"]["revision"],property_base)
                patch=check(context(),property_corrections=[{"name":"code","persistence":"until_changed","reason":"Explicitly declare continuing future code facts."}],changes=[{"name":"Key","facts":[{"property":"code","value":"gold","scope":"universe","at_tick":"30"}]}])
                with self.assertRaisesRegex(RuntimeError,"protected contracts require explicit author contract review"):
                    decisions.action({"action":"prepare","candidate":patch["candidate_handle"],"label":"Forbidden property edit","text":"Code facts continue until changed."})
                continued=publish(patch,"Code facts continue until explicitly changed. The key's code is gold from thirty.","connected-property-persistence",contracts=True)
                def property_settings(ctx):
                    return next(p for p in client.call("universe_read_contracts",{"universe":"Story","context_id":ctx})["result"]["properties"] if p["name"]=="code")
                self.assertEqual(property_settings(context())["persistence"],"until_changed")
                self.assertTrue(property_settings(context())["single_value"])
                self.assertEqual(property_settings(context())["value_type"],"text")
                old=property_settings(context(None,{"kind":"exact","revision_id":property_base}))
                self.assertEqual(old["persistence"],"explicit_interval")
                key=client.call("universe_read_facts",{"universe":"Story","context_id":context(31),"object_names":["Key"]})["result"]["objects"][0]
                self.assertTrue(any(f["property"]=="code" and f["value"]=="gold" and f["state"]=="supported" for f in key["facts"]))
                retained=client.call("universe_read_facts",{"universe":"Story","context_id":context(5),"object_names":["Courtyard"]})["result"]["objects"][0]
                self.assertTrue(any(e["action"]=="knock" for e in retained["occurred_events"]))
                self.assertTrue(any(f["property"]=="code" and f["value"]=="green" and f["state"]=="supported" for f in retained["facts"]))
                publish(check(context(),property_corrections=[{"name":"code","persistence":"unspecified","reason":"Future code observations have no continuing duration."}],changes=[{"name":"Mara","facts":[{"property":"code","value":"amber","scope":"universe","at_tick":"40"}]}]),"Future code observations have no continuing duration. Mara's code is amber at forty.","connected-property-observation",contracts=True)
                for tick,expected in ((40,True),(41,False)):
                    obj=client.call("universe_read_facts",{"universe":"Story","context_id":context(tick),"object_names":["Mara"]})["result"]["objects"][0]
                    self.assertEqual(any(f["property"]=="code" and f["value"]=="amber" and f["state"]=="supported" for f in obj["facts"]),expected)
                self.assertEqual(property_settings(context(None,{"kind":"exact","revision_id":continued}))["persistence"],"until_changed")
                publish(check(context(),property_corrections=[{"name":"code","single_value":False,"reason":"Explicitly allow multiple code values."}]),"Code may have multiple values; persistence remains unspecified.","connected-property-multiplicity",contracts=True)
                current_property=property_settings(context())
                self.assertFalse(current_property["single_value"])
                self.assertEqual(current_property["persistence"],"unspecified")
                self.assertEqual(current_property["value_type"],"text")
                self.assertTrue(property_settings(context(None,{"kind":"exact","revision_id":continued}))["single_value"])
                # A property approval cannot survive a changed head; restart recovery keeps its original key.
                staged=decisions.action({"action":"prepare_contracts","candidate":check(context(),property_corrections=[{"name":"code","persistence":"until_changed","reason":"Explicit continuing future values."}])["candidate_handle"],"label":"Property approval","text":"Future code values persist until changed."})
                ref=staged["candidate"]
                cli("approve","Story",ref["proposal_id"],str(ref["version"]),ref["digest"],staged["validation"]["execution"]["run_id"],profile=author)
                before_advance=client.call("universe_read_contracts",{"universe":"Story","context_id":context()})["frame"]["revision"]
                publish(check(context(),changes=[{"name":"Key","facts":[{"property":"tags","value":"yellow","scope":"universe","at_tick":"60","lifetime":{"kind":"until","end_tick":"61"}}]}]),"The key has a yellow tag from sixty until sixty-one.","connected-property-advance")
                with self.assertRaisesRegex(RuntimeError,"approval stale"):
                    decisions.action({"action":"publish","candidate":ref,"validation_run":staged["validation"]["execution"]["run_id"],"idempotency_key":"connected-stale-property"})
                self.assertEqual(property_settings(context())["persistence"],"unspecified")
                staged=decisions.action({"action":"prepare_contracts","candidate":check(context(),property_corrections=[{"name":"code","persistence":"until_changed","reason":"Fresh explicit correction after research."}])["candidate_handle"],"label":"Fresh property approval","text":"Future code values persist until changed."})
                ref=staged["candidate"]
                cli("approve","Story",ref["proposal_id"],str(ref["version"]),ref["digest"],staged["validation"]["execution"]["run_id"],profile=author)
                recovery={"action":"publish","candidate":ref,"validation_run":staged["validation"]["execution"]["run_id"],"idempotency_key":"connected-property-recovery"}
                client.close();client=None
                cli("shutdown",profile=author)
                # Shutdown acknowledges the request before draining workers and removing its endpoint.
                deadline=time.monotonic()+5
                while (installation/"engine.sock").exists() and time.monotonic()<deadline:
                    time.sleep(0.01)
                self.assertFalse((installation/"engine.sock").exists(),"Owned daemon did not finish shutdown")
                decisions=AuthorDecisions(SimpleNamespace(universe="Story"),binaries/"universe",installation,author,output=lambda _:None)
                receipt=decisions.action(recovery)
                self.assertEqual(decisions.action(recovery)["result"],receipt["result"])
                client=MCP(binaries/"universe-mcp",installation=installation,profile=agent)
                self.assertEqual(property_settings(context())["persistence"],"until_changed")
                self.assertFalse(property_settings(context())["single_value"])
                self.assertEqual(property_settings(context(None,{"kind":"exact","revision_id":before_advance}))["persistence"],"unspecified")

                # Explicit ending preserves past support; withdrawal does not refute.
                facts=lambda ctx: client.call("universe_read_facts",{"universe":"Story","context_id":ctx,"object_names":["Courtyard"]})["result"]["objects"][0]
                before_end=context(5)
                locked=next(f for f in facts(before_end)["facts"] if f["property"]=="locked")
                duplicate=check(before_end,corrections=[{"fact_handle":locked["fact_handle"],"value":False,"reason":"Explicit correction."}],fact_endings=[{"fact_handle":locked["fact_handle"],"end_tick":"8","reason":"Explicit ending."}])
                self.assertEqual(duplicate["status"],"needs_clarification",duplicate)
                self.assertIsNone(duplicate["candidate_handle"])
                ending=check(before_end,fact_endings=[{"fact_handle":locked["fact_handle"],"end_tick":"8","reason":"The authored lock condition ends at day eight."}])
                before_end_revision=publish(ending,"The courtyard's lock condition ends at day eight; its earlier condition is retained.","connected-fact-end")
                self.assertTrue(any(f["property"]=="locked" and f["state"]=="supported" for f in facts(context(5))["facts"]))
                later=facts(context(9))["facts"]
                self.assertFalse(any(f["property"]=="locked" and f["state"] in {"supported","refuted"} for f in later),later)
                current_locked=next(f for f in facts(context(5))["facts"] if f["property"]=="locked")
                stale=check(context(5),fact_withdrawals=[{"fact_handle":locked["fact_handle"],"reason":"Old version cannot withdraw newer support."}])
                self.assertEqual(stale["status"],"needs_clarification",stale)
                code=next(f for f in facts(context(5))["facts"] if f["property"]=="code")
                denied=client.request("tools/call",{"name":"universe_check_changes","arguments":{"universe":"Story","context_id":context(5),"fact_withdrawals":[{"fact_handle":code["fact_handle"],"reason":"Withdraw the evidence used by later knowledge and action."}]}})
                self.assertTrue(denied.get("isError") or denied.get("structuredContent",{}).get("result",{}).get("status")!="checked_candidate",denied)
                self.assertTrue(any(term in str(denied).lower() for term in ("knowledge","requirement")),denied)
                replacement=check(context(5),fact_withdrawals=[{"fact_handle":current_locked["fact_handle"],"reason":"Explicitly replace the old support."}],changes=[{"name":"Courtyard","facts":[{"property":"locked","value":False,"scope":"universe","at_tick":"0","lifetime":{"kind":"until","end_tick":"8"}}]}])
                self.assertEqual(replacement["status"],"checked_candidate",replacement)
                withdrawn=check(context(5),fact_withdrawals=[{"fact_handle":current_locked["fact_handle"],"reason":"The author withdraws the lock assertion rather than declaring its opposite."}])
                publish(withdrawn,"The author withdraws the courtyard lock claim, without claiming it was unlocked.","connected-fact-withdraw")
                remaining=facts(context(5))["facts"]
                self.assertFalse(any(f["property"]=="locked" and f["state"] in {"supported","refuted"} for f in remaining),remaining)
                historical=facts(context(5,{"kind":"exact","revision_id":before_end_revision}))["facts"]
                self.assertTrue(any(f["property"]=="locked" and f["state"]=="supported" for f in historical),historical)



            finally:
                if client: client.close()
                cli("shutdown",profile=author)

if __name__=="__main__": unittest.main()

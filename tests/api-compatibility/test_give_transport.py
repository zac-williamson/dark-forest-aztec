"""Source-level guard and payload checks for the direct Give settlement.

These are not fee measurements or runtime equivalence claims. The private input,
enqueue and exact custom-store fallback remain available for runtime comparison.
"""
import importlib.util
import json
import re
from pathlib import Path
import unittest
import check

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('give_plans',Path(__file__).with_name('generate-backend-plans.py'))
plans=importlib.util.module_from_spec(spec);spec.loader.exec_module(plans)

class GiveTransportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source=(ROOT/'contracts/system/artifact_valut/src/main.nr').read_text()
        entry=json.loads(plans.p.MANIFEST.read_text())['packages']['artifact_valut']
        cls.record=next(r for r in entry['continuations']if r['private']=='give_spaceships')
        cls.original=plans.original_definition(cls.source,cls.record['original'])
        cls.wrapper,cls.meta=plans.transform('artifact_valut',cls.source,cls.record)

    def test_complete_private_enqueue_and_original_fallback_are_retained(self):
        self.assertEqual(self.meta['flatWidth'],341)
        before=next(r for r in json.loads(plans.MANIFEST.read_text())['continuations']
                    if r['package']=='artifact_valut' and r['private']=='give_spaceships')
        self.assertEqual(self.meta['flatEnqueue'],before['flatEnqueue'])
        fallback=plans.original_raw_fallback(self.original,self.meta['flatSchema'])
        self.assertIn(fallback,self.wrapper)
        # All 337 original words, including the 60 inactive location fields,
        # remain exact in the raw call to the original System continuation.
        self.assertIn('[Field;338]',fallback)
        self.assertIn('for fallback_i in 0..337',fallback)
        self.assertIn('prepared_payload[fallback_i]',fallback)
        self.assertNotIn('WritePlan',self.wrapper)
        self.assertNotIn('state_worker',self.wrapper)

    def test_omitted_count_zero_reads_require_the_actual_arrival_namespace(self):
        self.assertIn('self.storage.arrivals_storage_address.read()',self.wrapper)
        guard='get_namespace_kind(state_backend_address,arrival)==7'
        self.assertLess(self.wrapper.index(guard),self.wrapper.index('try_settle_give_spaceships'))
        baseline=(check.BASE/'sources/contracts/system/artifact_valut/src/main.nr').read_text()
        private=plans.p.functions(baseline)['give_spaceships']['body']
        self.assertIn('assert(planet_events_state.count == 0',private)
        self.assertIn('assert(planet_artifacts_state.count == 0',private)
        self.assertIn('arrival_storage.verify_hashes_batch(',self.original['body'])
        self.assertNotIn('if origin_arrivals_count',self.original['body'])

    def test_direct_payload_preserves_all_used_full_width_words_in_order(self):
        literal=re.search(r'let calldata=\[(.*?)\];',self.wrapper,re.S).group(1)
        words=plans.p.split_arguments(literal)
        self.assertEqual(len(words),187)
        self.assertEqual(words[1:7],[f'{name}.to_field()'for name in
            ['player','planet','planet_events','planet_artifacts','artifact','artifact_location']])
        offsets=list(range(0,6))+list(range(107,184))+list(range(244,341))
        self.assertEqual(words[7:],[f'prepared_payload[{i}]'for i in offsets])
        backend=plans.give_spaceships_backend()
        for start,width in [(13,32),(45,22),(67,22),(89,8)]:
            self.assertIn('['+', '.join(f'payload.words[{i}]'for i in range(start,start+width))+']',backend)
        self.assertIn('let id=payload.words[97+i]',backend)
        self.assertIn('if id!=0',backend)

    def test_original_assertions_permissions_and_event_order_are_kept(self):
        backend=plans.give_spaceships_backend()
        ordered=['assert(self.internal._is_prepared_writer(self.msg_sender())',
                 'if supported {','assert_public_timestamp(',
                 '"planet hash mismatch"','"planet_artifacts hash mismatch"',
                 '"planet_events hash mismatch"','"player hash mismatch"',
                 'self.internal._set_planet_fields(',
                 'self.internal._set_planet_events_fields(',
                 'self.internal._set_planet_artifacts_fields(',
                 'self.internal._assert_authorized(artifact_location,actor)',
                 'self.internal._set_player_fields(',
                 'self.internal._assert_authorized(artifact,actor)',
                 'self.internal._emit_artifact_batch_max5(',
                 'self.internal._assert_authorized(artifact_location,actor)',
                 'self.internal._emit_artifact_location_batch_max5(']
        cursor=0
        for needle in ordered:
            cursor=backend.index(needle,cursor)+len(needle)
        for namespace,kind in [('player',2),('planet',3),('planet_events',5),
                               ('planet_artifacts',6),('artifact',8),('artifact_location',9)]:
            self.assertIn(f'self.storage.kinds.at({namespace}).read()=={kind}',backend)
        self.assertIn('let actor=self.msg_sender()',backend)
        self.assertNotIn('actor:',backend)

if __name__=='__main__':unittest.main()

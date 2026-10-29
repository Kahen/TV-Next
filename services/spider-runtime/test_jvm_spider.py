"""Actual owned JAR class-loading and upstream-signature invocation in OS isolation."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import uuid
from runner import (RuntimeFailure, RuntimeTimeout, RuntimeCleanupFailure, _remove_container,
                    docker_command, run_approved_spider)


class ApprovedJvmSpiderTests(unittest.TestCase):
    def test_all_five_original_methods_preserve_opaque_parameters(self):
        home = run_approved_spider('home', {'filter': False}).data
        self.assertFalse(home['filter'])
        self.assertEqual(home['siteKey'], 'owned-reference')
        self.assertEqual(home['list'][0]['vod_id'], 'opaque$1')
        category = run_approved_spider('category', {'categoryId': 'cat/$', 'page': 2, 'filters': {'year': '2026'}}).data
        self.assertEqual(category['page'], 2)
        self.assertEqual(category['category'], 'cat/$')
        self.assertEqual(category['filters'], {'year': '2026'})
        ids = ['opaque$share/文件?quoted="x"', 'other']
        self.assertEqual(run_approved_spider('detail', {'ids': ids}).data['ids'], ids)
        search = run_approved_spider('search', {'query': 'owned "text"', 'quick': True}).data
        self.assertEqual(search['query'], 'owned "text"')
        self.assertTrue(search['quick'])
        self.assertEqual(search['overload'], 'legacy')
        play = run_approved_spider('player', {'flag': 'line/$', 'id': ids[0], 'vipFlags': ['vip-1', 'vip-2']}).data
        self.assertEqual((play['flag'], play['id'], play['vipFlags']), ('line/$', ids[0], ['vip-1', 'vip-2']))

    def test_paginated_search_fallback_home_and_destroy_failure(self):
        with self.assertRaisesRegex(RuntimeFailure, 'unsupported-pagination'):
            run_approved_spider('search', {'query': 'owned', 'page': 2})
        page = run_approved_spider('search', {'query': 'owned', 'page': 3}, provider='owned-paged', diagnostic=True).data
        self.assertEqual((page['page'], page['overload']), (3, 'paged'))
        home = run_approved_spider('home', provider='owned-fallback', diagnostic=True).data
        self.assertEqual(home['class'][0]['type_id'], 'owned')
        self.assertEqual(home['list'][0]['vod_id'], 'fallback')
        with self.assertRaisesRegex(RuntimeFailure, 'provider-cleanup-failed'):
            run_approved_spider('home', provider='owned-cleanup', diagnostic=True)

    def test_unknown_provider_class_paths_methods_and_invalid_args_fail_closed(self):
        for provider in ['file:///tmp/evil.jar', 'https://example.invalid/evil.jar', 'com.evil.Provider', 'owned-policy']:
            with self.assertRaises(ValueError):
                run_approved_spider('home', provider=provider)
        with self.assertRaises(ValueError):
            run_approved_spider('eval', {'code': 'evil'})
        for method, args in [('category', {}), ('category', {'categoryId':'c','page':0}),
                             ('category', {'categoryId':'c','filters':{'bad':[]}}),
                             ('detail', {'ids':[]}), ('detail', {'ids':['x'] * 21}),
                             ('search', {'query':''}), ('player', {'id':''})]:
            with self.subTest(method=method, args=args), self.assertRaisesRegex(RuntimeFailure, 'invalid-request'):
                run_approved_spider(method, args)

    def test_malformed_wire_unknown_fields_and_unapproved_registry_ids(self):
        normal = {'version':2,'provider':'owned-reference','method':'home','args':{}}
        cases = [b'not-json', b'\xff', b'{"version":2,"version":2}',
                 json.dumps(normal | {'upload':'arbitrary.jar'}).encode(),
                 json.dumps(normal | {'provider':'unapproved'}).encode(),
                 json.dumps(normal | {'provider':'owned-policy'}).encode()]
        for wire in cases:
            name = 'tvnext-fixture-' + uuid.uuid4().hex[:20]
            try:
                result = subprocess.run(docker_command('java-spider', name), input=wire, capture_output=True, timeout=9)
            finally:
                if not _remove_container(name):
                    raise RuntimeCleanupFailure('raw-wire container cleanup unconfirmed')
            self.assertEqual(result.returncode, 2, result.stderr[:300])
            response = json.loads(result.stdout)
            self.assertIn(response['code'], ['invalid-request', 'provider-not-approved'])
            self.assertNotIn('Exception', result.stdout.decode())

    def test_provider_output_exceptions_and_resource_failures_are_redacted(self):
        self.assertIn('list', run_approved_spider('home', provider='owned-output', diagnostic=True).data)
        for provider, code in [('owned-throwing','provider-execution'), ('owned-invalid','invalid-provider-response')]:
            with self.assertRaisesRegex(RuntimeFailure, code) as caught:
                run_approved_spider('home', provider=provider, diagnostic=True)
            self.assertNotIn('secret', str(caught.exception))
            self.assertNotIn('https:', str(caught.exception))
        with self.assertRaises(RuntimeFailure):
            run_approved_spider('home', provider='owned-oom', diagnostic=True)
        with self.assertRaises(RuntimeFailure):
            run_approved_spider('home', provider='owned-processes', diagnostic=True)
        with self.assertRaises(RuntimeTimeout):
            run_approved_spider('home', provider='owned-timeout', diagnostic=True, timeout=1.5)

    def test_loaded_jar_obeys_os_and_classpath_boundaries(self):
        prior = os.environ.get('TVNEXT_HOST_SECRET_TEST')
        os.environ['TVNEXT_HOST_SECRET_TEST'] = 'never-forward-this-secret'
        try:
            policy = run_approved_spider('home', provider='owned-policy', diagnostic=True).data
            for key in ['networkBlocked', 'readonly', 'workerClassesHidden', 'nonroot']:
                self.assertTrue(policy[key], key)
            self.assertFalse(policy['hostSecretVisible'])
            self.assertLessEqual(int(policy['memoryMax']), 128 * 1024 * 1024)
            self.assertLessEqual(int(policy['pidsMax']), 32)
        finally:
            if prior is None: os.environ.pop('TVNEXT_HOST_SECRET_TEST', None)
            else: os.environ['TVNEXT_HOST_SECRET_TEST'] = prior

    def test_packaged_preflight_and_hash_match_the_actual_jar(self):
        container = 'tvnext-fixture-' + uuid.uuid4().hex[:20]
        pending = True
        try:
            subprocess.run(['docker','create','--name',container,'tvnext/spider-jvm-approved:ci'],
                           check=True, capture_output=True, timeout=10)
            pending = False
            with tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                for name in ['approved.jar', 'approved.json']:
                    subprocess.run(['docker','cp',container+':/worker/'+name,str(root/name)], check=True, capture_output=True, timeout=10)
                report = json.loads((root/'approved.json').read_text())
                self.assertEqual(report['status'], 'pure-jvm-candidate')
                self.assertEqual(report['sha256'], hashlib.sha256((root/'approved.jar').read_bytes()).hexdigest())
        finally:
            if not _remove_container(container, pending_creation=pending):
                raise RuntimeCleanupFailure('preflight evidence container cleanup unconfirmed')


if __name__ == '__main__':
    unittest.main(verbosity=2)

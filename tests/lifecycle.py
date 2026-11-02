"""Real packaged-runtime checks; no model accounts, API keys or external model calls."""
import json
import os
from pathlib import Path
import queue
import signal
import socket
import subprocess
import tempfile
import threading
import time
import unittest
import urllib.request

RESOURCES = Path(os.environ['AGNES_TEST_APP']).resolve() / 'Contents/Resources'
NODE = RESOURCES / 'node/bin/node'
SUPERVISOR = RESOURCES / 'supervisor.mjs'

class Lifecycle(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='agnes-desktop-test-')
        self.root = Path(self.temp.name)
        self.procs = []
        self.env = dict(os.environ, AGNES_DESKTOP_HOME=str(self.root / 'Home-v1'),
                        AGNES_DESKTOP_LOGS=str(self.root / 'Logs'),
                        AGNES_DESKTOP_WORKSPACE=str(self.root / 'Workspace'),
                        AGNES_DESKTOP_PARENT_PID=str(os.getpid()))
        self.env.pop('AGNES_DESKTOP_RUNTIME', None)

    def tearDown(self):
        for proc in self.procs:
            if proc.poll() is None:
                proc.send_signal(signal.SIGTERM)
                try: proc.wait(25)
                except subprocess.TimeoutExpired: proc.kill(); proc.wait()
            for stream in [proc.stdin, proc.stdout, proc.stderr]:
                if stream: stream.close()
        # Keep failures inspectable until cleanup; stop only this isolated home.
        subprocess.run([NODE, RESOURCES / 'runtime/agnes.mjs', 'daemon', 'stop'],
                       env=dict(self.env, AGH_HOME=self.env['AGNES_DESKTOP_HOME'], AGNES_PROFILE='local-dev'),
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=20)
        self.temp.cleanup()

    def launch(self, env=None, command=None):
        proc = subprocess.Popen(command or [NODE, SUPERVISOR], env=env or self.env,
                                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                text=True, bufsize=1)
        self.procs.append(proc)
        events = queue.Queue()
        def read():
            for line in proc.stdout:
                try: events.put(json.loads(line))
                except json.JSONDecodeError: pass
        threading.Thread(target=read, daemon=True).start()
        return proc, events

    def event(self, events, kind, timeout=100):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            value = events.get(timeout=max(0.1, deadline - time.monotonic()))
            if value['type'] == kind: return value
            if value['type'] == 'error' and kind != 'error': self.fail(str(value))
        self.fail(f'Missing {kind} event')

    def stop(self, proc, events):
        proc.stdin.write('stop\n'); proc.stdin.flush()
        self.assertEqual(self.event(events, 'stopped', 25)['code'], 0)
        self.assertEqual(proc.wait(5), 0)

    def assert_closed(self, url):
        with self.assertRaises(Exception): urllib.request.urlopen(url + 'healthz', timeout=2)
        result = subprocess.run([NODE, RESOURCES / 'runtime/agnes.mjs', 'daemon', 'status'],
                                env=dict(self.env, AGH_HOME=self.env['AGNES_DESKTOP_HOME'], AGNES_PROFILE='local-dev'),
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(json.loads(result.stdout)['running'], False)

    def test_boot_health_shutdown_and_persistence(self):
        proc, events = self.launch()
        url = self.event(events, 'ready')['url']
        with urllib.request.urlopen(url + 'healthz') as response:
            self.assertEqual(json.load(response), {'status': 'ok'})
        with urllib.request.urlopen(url) as response: self.assertIn(b'Agnes Harness', response.read())
        marker = self.root / 'Workspace/keep.txt'
        marker.write_text('retained workspace')
        self.stop(proc, events)
        self.assert_closed(url)
        proc, events = self.launch()
        self.assertEqual(self.event(events, 'ready')['url'], url)
        self.assertEqual(marker.read_text(), 'retained workspace')
        self.assertEqual((self.root / 'Home-v1').stat().st_mode & 0o777, 0o700)
        self.stop(proc, events)
        self.assert_closed(url)

    def test_occupied_saved_port_and_corrupt_preferences(self):
        sock = socket.socket(); sock.bind(('127.0.0.1', 0)); sock.listen()
        try:
            (self.root / 'web-port.json').write_text(json.dumps({'port': sock.getsockname()[1]}))
            proc, events = self.launch()
            url = self.event(events, 'ready')['url']
            self.assertNotIn(f':{sock.getsockname()[1]}/', url)
            self.stop(proc, events)
        finally: sock.close()
        (self.root / 'web-port.json').write_text('broken JSON')
        proc, events = self.launch()
        self.event(events, 'ready')
        self.stop(proc, events)

    def test_start_failure_reports_error_and_exits(self):
        proc, events = self.launch(env=dict(self.env, AGNES_DESKTOP_RUNTIME=str(self.root / 'missing.mjs')))
        self.assertIn('启动失败', self.event(events, 'error', 20)['message'])
        self.assertEqual(proc.wait(25), 1)

    def test_quit_during_startup_cleans_backend(self):
        for pause in [0, 0.25, 0.8]:
            proc, events = self.launch()
            self.event(events, 'starting')
            time.sleep(pause)
            self.stop(proc, events)
            port = json.loads((self.root / 'web-port.json').read_text())['port']
            # Check again after startup children have had time to report discovery.
            time.sleep(1)
            self.assert_closed(f'http://127.0.0.1:{port}/')

    def test_parent_crash_stops_web_and_daemon(self):
        # The wrapper is the supervisor's parent. The test keeps stdin open after killing it.
        wrapper = ('import os,subprocess,sys; '
                   'e=dict(os.environ,AGNES_DESKTOP_PARENT_PID=str(os.getpid())); '
                   'p=subprocess.Popen(sys.argv[1:],env=e,stdin=sys.stdin,stdout=sys.stdout,stderr=sys.stderr); '
                   'p.wait()')
        import sys
        proc, events = self.launch(command=[sys.executable, '-c', wrapper, str(NODE), str(SUPERVISOR)])
        url = self.event(events, 'ready')['url']
        proc.kill(); proc.wait(5)
        self.assertEqual(self.event(events, 'stopped', 25)['code'], 0)
        self.assert_closed(url)

if __name__ == '__main__': unittest.main(verbosity=2)

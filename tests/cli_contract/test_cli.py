"""Exercise the compiled Dart CLIs through their actual process boundary."""

import contextlib
import json
import os
from pathlib import Path
import select
import signal
import subprocess
import sys
import tempfile
import time
import unittest

if os.name == 'posix':
    import pty
    import termios


SLACK = os.environ['SLACK_TABLE_DART_CLI']
TABLE = os.environ['TABLE_TABLE_DART_CLI']
MARKDOWN = os.environ['MD_TABLE_DART_CLI']
DRIVER = os.environ.get('TABLE_TABLE_CLIPBOARD_DRIVER')

if sys.platform == 'darwin' and not DRIVER:
    raise RuntimeError('Set TABLE_TABLE_CLIPBOARD_DRIVER to the compiled test/fixtures/cli_driver.dart; '
                       'clipboard tests must not access the real general pasteboard.')


@unittest.skipUnless(os.name == 'posix', 'clipboard command harness requires POSIX')
class CliTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.env = dict(os.environ)
        self.env['PATH'] = str(self.root)
        self.clipboard = self.root / 'clipboard.txt'
        self.count = self.root / 'reads.txt'
        self.clipboard.write_text('A,B\n1,2', encoding='utf-8')
        self.count.write_text('0')
        self.env['TEST_CLIPBOARD'] = str(self.clipboard)
        self.env['TEST_READS'] = str(self.count)
        self.env.pop('TEST_CHANGE_AFTER_READ', None)
        self.env.pop('TEST_CHANGE_AGAIN_AFTER_READ', None)
        self.env.pop('TEST_CLIPBOARD_ERROR', None)
        self.env.pop('TEST_COPY_ERROR', None)
        self.env.pop('TEST_INVALID_UTF8', None)
        self.env.pop('TEST_CLIPBOARD_SNAPSHOTS', None)
        self.env.pop('TEST_NATIVE_PASTEBOARD', None)
        self.env.pop('TEST_NATIVE_READS', None)
        # Fake only the external clipboard commands, never Dart internals.
        read = '''import os, pathlib, sys
p = pathlib.Path(os.environ['TEST_READS'])
n = int(p.read_text()) + 1
p.write_text(str(n))
if os.environ.get('TEST_CLIPBOARD_ERROR'):
    sys.stderr.write('clipboard unavailable')
    sys.exit(1)
text = pathlib.Path(os.environ['TEST_CLIPBOARD']).read_text(encoding='utf-8')
if os.environ.get('TEST_INVALID_UTF8'):
    sys.stdout.buffer.write(bytes([255]))
    sys.exit(0)
if 'TEST_CHANGE_AFTER_READ' in os.environ and n > 1:
    text = os.environ['TEST_CHANGE_AFTER_READ']
if 'TEST_CHANGE_AGAIN_AFTER_READ' in os.environ and n > 2:
    text = os.environ['TEST_CHANGE_AGAIN_AFTER_READ']
sys.stdout.buffer.write(text.encode('utf-8'))
'''
        write = '''import os, pathlib, sys
if os.environ.get('TEST_COPY_ERROR'):
    sys.stdin.buffer.read()
    sys.stderr.write('copy failed')
    sys.exit(1)
pathlib.Path(os.environ['TEST_CLIPBOARD']).write_bytes(sys.stdin.buffer.read())
'''
        for name, script in [('pbpaste', read), ('pbcopy', write),
                             ('wl-paste', read), ('wl-copy', write)]:
            command = self.root / name
            command.write_text(f'#!{sys.executable}\n{script}', encoding='utf-8')
            command.chmod(0o755)

    def run_cli(self, flags=(), text='', executable=SLACK):
        return subprocess.run(
            [*self.command(executable), *flags], input=text, capture_output=True,
            text=True, encoding='utf-8', env=self.env, timeout=10,
        )

    def command(self, executable):
        if DRIVER:
            return [DRIVER, Path(executable).name.removesuffix('.exe')]
        return [executable]

    def assert_success(self, result, output):
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, output)
        self.assertEqual(result.stderr, '')

    def test_output_selection_from_stdin(self):
        for flags in ([], ['--output', 'slack'], ['--output', 'markdown']):
            with self.subTest(flags=flags):
                expected = (
                    '| Name  | Count |\n| ----- | ----- |\n| Alpha | 12    |\n'
                    if 'markdown' in flags else 'Name\tCount\nAlpha\t12\n'
                )
                self.assert_success(self.run_cli(flags, 'Name,Count\nAlpha,12'), expected)

    def test_space_aligned_input_from_stdin(self):
        source = 'NAME   PORT(S)          AGE\nweb    80/TCP,443/TCP   1d\n'
        for flags in ([], ['--input', 'space-aligned']):
            with self.subTest(flags=flags):
                self.assert_success(self.run_cli(flags, source),
                                    'NAME\tPORT(S)\tAGE\nweb\t80/TCP,443/TCP\t1d\n')

    def test_markdown_entry_point_and_output_override(self):
        self.assert_success(self.run_cli(text='A,B', executable=MARKDOWN),
                            '| A   | B   |\n| --- | --- |\n')
        self.assert_success(self.run_cli(['--output=slack'], 'A,B', MARKDOWN), 'A\tB\n')

    def test_table_table_entry_point_and_output_override(self):
        self.assert_success(self.run_cli(text='A,B', executable=TABLE), 'A\tB\n')
        self.assert_success(self.run_cli(['--output=markdown'], 'A,B', TABLE),
                            '| A   | B   |\n| --- | --- |\n')
        result = self.run_cli(executable=TABLE)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stderr, 'table-table: no table input found\n')

    def test_files_and_stdin_can_be_combined(self):
        first = self.root / 'first.csv'
        last = self.root / 'last.csv'
        first.write_text('A,B')
        last.write_text('3,4')
        self.assert_success(self.run_cli([str(first), '-', str(last)], '1,2'),
                            'A\tB\n1\t2\n3\t4\n')
        self.assert_success(self.run_cli(['-', '-'], 'A,B'), 'A\tB\n')

    def test_missing_file_and_invalid_encoding(self):
        result = self.run_cli([str(self.root / 'missing')])
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, '')
        self.assertIn('missing', result.stderr)
        invalid = self.root / 'invalid.csv'
        invalid.write_bytes(b'A,B\n\xff,y')
        result = self.run_cli([str(invalid)])
        self.assertEqual(result.returncode, 2)
        self.assertNotIn('Unhandled exception', result.stderr)

    def test_quiet_and_copy(self):
        self.assert_success(self.run_cli(['--copy', '--quiet'], 'X,Y\nα,😀'), '')
        self.assertEqual(self.clipboard.read_text(), 'X\tY\nα\t😀')
        self.assert_success(self.run_cli(['-q'], 'A,B'), '')

    def test_clipboard_aliases(self):
        for flag in ['--clipboard', '--clip']:
            with self.subTest(flag=flag):
                self.clipboard.write_text('A,B\n1,2')
                self.assert_success(self.run_cli([flag]), 'A\tB\n1\t2\n')
                self.assertEqual(self.clipboard.read_text(), 'A\tB\n1\t2')

    def test_markdown_clipboard_workflows(self):
        for flags in (['--copy'], ['--clipboard'], ['--wait']):
            with self.subTest(flags=flags):
                self.clipboard.write_text('A,B\n1,2')
                self.count.write_text('0')
                self.env['TEST_CHANGE_AFTER_READ'] = 'A,B\n1,2'
                if '--wait' in flags:
                    self.clipboard.write_text('old clipboard')
                self.assert_success(self.run_cli([*flags, '--output', 'markdown', '-q'],
                                                 'A,B\n1,2'), '')
                self.assertEqual(self.clipboard.read_text(),
                                 '| A   | B   |\n| --- | --- |\n| 1   | 2   |')

    def test_wait_detects_same_length_text_change(self):
        self.env['TEST_CHANGE_AFTER_READ'] = 'C,D\n3,4'
        self.assert_success(self.run_cli(['--wait']), 'C\tD\n3\t4\n')
        self.assertEqual(self.clipboard.read_text(), 'C\tD\n3\t4')

    def test_wait_converts_the_observed_change_without_reading_again(self):
        self.env['TEST_CHANGE_AFTER_READ'] = 'C,D\n3,4'
        self.env['TEST_CHANGE_AGAIN_AFTER_READ'] = 'E,F\n5,6'
        self.assert_success(self.run_cli(['--wait']), 'C\tD\n3\t4\n')
        self.assertEqual(self.clipboard.read_text(), 'C\tD\n3\t4')
        self.assertEqual(self.count.read_text(), '2')

    @unittest.skipUnless(DRIVER, 'requires the injected clipboard test driver')
    def test_wait_detects_html_only_change_and_converts_the_observed_snapshot(self):
        def html(value):
            return '<table><tr><th>A</th><th>B</th></tr>' + \
                   f'<tr><td>{value}</td><td>value</td></tr></table>'
        snapshots = self.root / 'snapshots.json'
        snapshots.write_text(json.dumps([
            {'text/plain': 'unchanged', 'text/html': html(value)}
            for value in ['before', 'observed', 'too late']
        ]))
        result_file = self.root / 'result.json'
        self.env['TEST_CLIPBOARD_SNAPSHOTS'] = str(snapshots)
        self.env['TEST_CLIPBOARD_RESULT'] = str(result_file)
        self.assert_success(self.run_cli(['--wait']), 'A\tB\nobserved\tvalue\n')
        self.assertEqual(json.loads(result_file.read_text()), {'text/plain': 'A\tB\nobserved\tvalue'})
        self.assertEqual(self.count.read_text(), '2')

    @unittest.skipUnless(DRIVER, 'requires the injected clipboard test driver')
    def test_cli_html_preference_and_explicit_plain_format(self):
        snapshots = self.root / 'snapshots.json'
        snapshots.write_text(json.dumps([{
            'text/plain': 'A,B\nplain,value',
            'text/html': '<table><tr><th>A</th><th>B</th></tr>'
                         '<tr><td>rich</td><td>value</td></tr></table>',
        }]))
        self.env['TEST_CLIPBOARD_SNAPSHOTS'] = str(snapshots)
        self.env['TEST_CLIPBOARD_RESULT'] = str(self.root / 'result.json')
        self.assert_success(self.run_cli(['--clipboard']), 'A\tB\nrich\tvalue\n')
        self.assert_success(self.run_cli(['--clipboard', '--input', 'csv']), 'A\tB\nplain\tvalue\n')

    def test_production_entry_points_read_pipes_without_a_clipboard(self):
        for executable, expected in [(SLACK, 'A\tB\nx\ty\n'), (TABLE, 'A\tB\nx\ty\n'),
                                     (MARKDOWN, '| A   | B   |\n| --- | --- |\n| x   | y   |\n')]:
            with self.subTest(executable=executable):
                result = subprocess.run([executable], input='A,B\nx,y', capture_output=True,
                                        text=True, env=dict(self.env, PATH=''), timeout=10)
                self.assert_success(result, expected)

    def test_wait_reports_an_empty_changed_clipboard(self):
        self.env['TEST_CHANGE_AFTER_READ'] = ''
        result = self.run_cli(['--wait'])
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, '')
        self.assertEqual(result.stderr, 'slack-table: no table text found on the clipboard\n')
        self.assertEqual(self.count.read_text(), '2')

    def test_clipboard_errors(self):
        self.env['TEST_CLIPBOARD_ERROR'] = '1'
        for flags in [['--clipboard'], ['--wait']]:
            result = self.run_cli(flags)
            self.assertEqual(result.returncode, 2)
            self.assertIn('clipboard unavailable', result.stderr)
            self.assertEqual(result.stdout, '')
        del self.env['TEST_CLIPBOARD_ERROR']
        self.env['TEST_COPY_ERROR'] = '1'
        result = self.run_cli(['--copy'], 'A,B')
        self.assertEqual(result.returncode, 2)
        self.assertIn('copy failed', result.stderr)

    def test_empty_clipboard_and_absent_commands(self):
        self.clipboard.write_text('')
        result = self.run_cli(['--clipboard'])
        self.assertEqual(result.returncode, 2)
        self.assertIn('no table text', result.stderr)
        empty_path = self.root / 'empty'
        empty_path.mkdir()
        self.env['PATH'] = str(empty_path)
        self.assert_success(self.run_cli(text='A,B'), 'A\tB\n')
        result = self.run_cli(['--copy'], 'A,B')
        self.assertEqual(result.returncode, 2)
        self.assertIn('no supported clipboard command', result.stderr)

    def test_invalid_clipboard_encoding_is_reported(self):
        self.env['TEST_INVALID_UTF8'] = '1'
        result = self.run_cli(['--clipboard'])
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, '')
        self.assertTrue(result.stderr.startswith('slack-table: could not read clipboard:'))
        self.assertNotIn('Unhandled exception', result.stderr)

    def test_ambiguous_columns_in_pipeline(self):
        text = '\n\n'.join(str(index) for index in range(12))
        result = self.run_cli(text=text)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, '')
        self.assertEqual(result.stderr, 'slack-table: ambiguous column count; '
                         'valid choices are 2, 3, 4, 6; specify one with --columns N\n')
        self.assert_success(self.run_cli(['--columns', '3'], text),
                            '0\t1\t2\n3\t4\t5\n6\t7\t8\n9\t10\t11\n')

    def test_invalid_options_and_conflicts(self):
        for flags in [
            ['--wait', '--clipboard'], ['--wait', 'file'], ['--clip', 'file'],
            ['--columns', '1'], ['--columns', 'no'], ['--columns'], ['--columns', '0x2'],
            ['--input', 'unknown'], ['--output', 'unknown'], ['--unknown'],
            ['--image', 'image.png'],
        ]:
            with self.subTest(flags=flags):
                result = self.run_cli(flags, 'A,B')
                self.assertEqual(result.returncode, 2, result)
                self.assertEqual(result.stdout, '')
                self.assertTrue(result.stderr.startswith('slack-table: '))
                self.assertNotIn('Unhandled exception', result.stderr)

    def test_empty_input_error_is_not_suppressed_by_quiet(self):
        result = self.run_cli(['-q'])
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stderr, 'slack-table: no table input found\n')

    def test_help_and_version(self):
        for executable, name in [(TABLE, 'table-table'), (SLACK, 'slack-table'), (MARKDOWN, 'md-table')]:
            self.assert_success(self.run_cli(['--version'], executable=executable),
                                f'{name} 0.1.0\n')
            result = self.run_cli(['--help'], executable=executable)
            self.assertEqual(result.returncode, 0)
            self.assertIn(f'Usage: {name}', result.stdout)
            self.assertIn('--columns', result.stdout)

    @unittest.skipUnless(os.name == 'posix', 'requires a POSIX terminal')
    def test_interactive_column_prompt_and_retry(self):
        self.clipboard.write_text('\n\n'.join(str(i) for i in range(12)))
        with self.terminal_process(['--clipboard']) as (process, terminal):
            prompt = self.read_until(process.stderr, b'Number of columns (2, 3, 4, 6): ')
            self.assertEqual(prompt, b'Number of columns (2, 3, 4, 6): ')
            os.write(terminal, b'5\n')
            self.assertEqual(self.read_until(process.stderr, b'Number of columns (2, 3, 4, 6): '),
                             b'Choose one of: 2, 3, 4, 6.\nNumber of columns (2, 3, 4, 6): ')
            os.write(terminal, b'3\n')
            stdout, stderr = process.communicate(timeout=10)
            self.assertEqual(process.returncode, 0, stderr)
            self.assertEqual(stdout, b'0\t1\t2\n3\t4\t5\n6\t7\t8\n9\t10\t11\n')
            self.assertEqual(stderr, b'')

    @unittest.skipUnless(os.name == 'posix', 'requires a POSIX terminal')
    def test_interactive_clipboard_default(self):
        with self.terminal_process([]) as (process, _):
            stdout, stderr = process.communicate(timeout=10)
            self.assertEqual(process.returncode, 0, stderr)
            self.assertEqual(stdout, b'A\tB\n1\t2\n')
            self.assertEqual(self.clipboard.read_text(), 'A\tB\n1\t2')

    @unittest.skipUnless(os.name == 'posix', 'requires a POSIX terminal')
    def test_terminal_paste_after_empty_clipboard(self):
        self.clipboard.write_text('')
        with self.terminal_process([]) as (process, terminal):
            os.write(terminal, b'A,B\n1,2\n\x04')
            stdout, stderr = process.communicate(timeout=10)
            self.assertEqual(process.returncode, 0, stderr)
            self.assertEqual(stdout, b'A\tB\n1\t2\n')
            self.assertEqual(self.clipboard.read_text(), 'A\tB\n1\t2')

    @unittest.skipUnless(os.name == 'posix', 'requires POSIX signals')
    def test_interrupt_while_waiting(self):
        process = subprocess.Popen([*self.command(SLACK), '--wait'], stdin=subprocess.DEVNULL,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=self.env)
        try:
            deadline = time.monotonic() + 5
            while self.count.read_text() == '0' and time.monotonic() < deadline:
                time.sleep(0.01)
            self.assertNotEqual(self.count.read_text(), '0')
            process.send_signal(signal.SIGINT)
            stdout, stderr = process.communicate(timeout=10)
            self.assertEqual(process.returncode, 130)
            self.assertEqual(stdout, b'')
            self.assertEqual(stderr, b'slack-table: interrupted\n')
        finally:
            if process.poll() is None:
                process.kill()
            process.communicate()

    @contextlib.contextmanager
    def terminal_process(self, flags):
        master, slave = pty.openpty()
        attributes = termios.tcgetattr(slave)
        attributes[3] &= ~termios.ECHO
        termios.tcsetattr(slave, termios.TCSANOW, attributes)
        process = subprocess.Popen([*self.command(SLACK), *flags], stdin=slave,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=self.env)
        os.close(slave)
        try:
            yield process, master
        finally:
            if process.poll() is None:
                process.kill()
            process.communicate()
            os.close(master)

    def read_until(self, stream, marker):
        result = b''
        deadline = time.monotonic() + 10
        while not result.endswith(marker):
            remaining = deadline - time.monotonic()
            self.assertGreater(remaining, 0, result)
            ready, _, _ = select.select([stream], [], [], remaining)
            self.assertTrue(ready, result)
            chunk = os.read(stream.fileno(), 4096)
            self.assertTrue(chunk, result)
            result += chunk
        return result


if __name__ == '__main__':
    unittest.main()

"""Build Dart and run the core contracts, CLI, and web checks."""

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys


ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / 'build'
SUFFIX = '.exe' if os.name == 'nt' else ''


def run(*command, env=None, cwd=ROOT):
    print('+ ' + ' '.join(str(arg) for arg in command), flush=True)
    subprocess.run(command, cwd=cwd, env=env, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--web', action='store_true', help='also test and build the Jaspr app')
    args = parser.parse_args()
    BUILD.mkdir(exist_ok=True)
    dart = os.environ.get('DART', 'dart')
    run(dart, 'format', '--output=none', '--set-exit-if-changed', 'lib', 'bin', 'test', 'tool')
    # Scope core checks here so editors can still discover the web package.
    for directory in ['lib', 'bin', 'test', 'tool']:
        run(dart, 'analyze', directory)
    run(dart, 'test', '--reporter', 'expanded')
    binaries = {}
    for name, source in [('table-table', 'bin/table_table.dart'),
                         ('slack-table', 'bin/slack_table.dart'),
                         ('md-table', 'bin/md_table.dart')]:
        binaries[name] = str(BUILD / (name + SUFFIX))
        run(dart, 'compile', 'exe', source, '-o', binaries[name])

    env = dict(os.environ, PYTHONDONTWRITEBYTECODE='1')
    env['SLACK_TABLE_DART_CLI'] = binaries['slack-table']
    env['TABLE_TABLE_DART_CLI'] = binaries['table-table']
    env['MD_TABLE_DART_CLI'] = binaries['md-table']
    driver = BUILD / ('clipboard-cli-driver' + SUFFIX)
    run(dart, 'compile', 'exe', 'test/fixtures/cli_driver.dart', '-o', str(driver))
    env['TABLE_TABLE_CLIPBOARD_DRIVER'] = str(driver)
    run(sys.executable, '-m', 'unittest', 'discover', '-s', 'tests/cli_contract', '-v', env=env)

    if sys.platform == 'darwin':
        native_smoke = BUILD / 'clipboard-smoke'
        run(dart, 'compile', 'exe', 'tool/clipboard_smoke.dart', '-o', str(native_smoke))
        run(str(native_smoke), str(driver))

    run(dart, 'compile', 'js', 'tool/web_smoke.dart', '-o', str(BUILD / 'web_smoke.js'))
    if shutil.which('node'):
        run('node', str(BUILD / 'web_smoke.js'))
    else:
        print('Browser compilation passed; install Node to also execute the JS smoke test.')

    if args.web:
        web = ROOT / 'apps' / 'table_web'
        npm = shutil.which('npm')
        if npm is None:
            raise SystemExit('Install Node.js and npm to build the web app styles.')
        run(npm, 'run', 'build:css', cwd=web)
        run(dart, 'format', '--output=none', '--set-exit-if-changed', 'lib', 'test', cwd=web)
        run(dart, 'analyze', cwd=web)
        run(dart, 'test', '--reporter', 'expanded', cwd=web)
        run(dart, 'run', 'jaspr_cli:jaspr', 'build', cwd=web)


if __name__ == '__main__':
    main()

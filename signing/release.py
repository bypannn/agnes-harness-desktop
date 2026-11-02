#!/usr/bin/env python3
"""Explicit signing/notary steps. Credentials stay in the macOS Keychain, not this tree."""
import argparse
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent
MACHO = {bytes.fromhex(value) for value in ['cffaedfe', 'cefaedfe', 'feedfacf', 'feedface', 'cafebabe', 'bebafeca', 'cafebabf', 'bfbafeca']}

def run(argv, **kwargs):
    return subprocess.run([str(value) for value in argv], check=True, text=True, **kwargs)

def capture(argv):
    return run(argv, capture_output=True).stdout

def binaries(app):
    result = []
    for path in app.rglob('*'):
        if path.is_symlink() or not path.is_file():
            continue
        with path.open('rb') as stream:
            if stream.read(4) in MACHO:
                result.append(path)
    return sorted(result, key=lambda value: (-len(value.parts), str(value)))

def metadata(path):
    result = run(['codesign', '-d', '--verbose=4', path], capture_output=True)
    ent = run(['codesign', '-d', '--entitlements', ':-', path], capture_output=True).stdout
    return result.stderr, plistlib.loads(ent.encode()) if ent.strip() else {}

def audit(app, strict=False, real=False):
    entries = []
    targets = binaries(app)
    if len(targets) < 2:
        raise SystemExit('Expected a complete desktop app with embedded native code')
    for path in targets:
        run(['codesign', '--verify', '--strict', path], capture_output=True)
        details, ent = metadata(path)
        if strict and ('runtime)' not in details or ent.get('com.apple.security.get-task-allow')):
            raise SystemExit(f'Not notarization-ready: {path.relative_to(app)}')
        if real and ('Authority=Developer ID Application:' not in details or 'Timestamp=' not in details):
            raise SystemExit(f'Developer ID signature with secure timestamp required: {path.relative_to(app)}')
        entries.append({'path': str(path.relative_to(app)), 'hardenedRuntime': 'runtime)' in details,
                        'debugEntitlement': bool(ent.get('com.apple.security.get-task-allow')),
                        'entitlements': ent})
    run(['codesign', '--verify', '--deep', '--strict', app], capture_output=True)
    return entries

def sign(source, destination, identity, local_test):
    if destination.exists():
        raise SystemExit('Destination already exists; choose an unused path')
    if source.suffix != '.app' or destination.suffix != '.app':
        raise SystemExit('Source and destination must be .app bundles')
    if not local_test:
        if not re.fullmatch(r'[0-9A-Fa-f]{40}', identity or ''):
            raise SystemExit('Use the 40-character SHA-1 identity from security find-identity')
        available = capture(['security', 'find-identity', '-v', '-p', 'codesigning'])
        matches = re.findall(r'([0-9A-Fa-f]{40}) "(Developer ID Application:[^\n"]+)"', available)
        if identity.upper() not in {value.upper() for value, _ in matches}:
            raise SystemExit('No matching valid Developer ID Application identity; no files changed')
    signer = '-' if local_test else identity
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(source, destination, symlinks=True)
    build_file = destination / 'Contents/Resources/BUILD.json'
    build = json.loads(build_file.read_text())
    build['signing'] = 'local hardened-runtime test; NOT for public release' if local_test else 'Developer ID signed; notarization is recorded by the Apple ticket'
    build_file.write_text(json.dumps(build, indent=2) + '\n')
    info = plistlib.loads((destination / 'Contents/Info.plist').read_bytes())
    main = destination / 'Contents/MacOS' / info['CFBundleExecutable']
    for path in binaries(destination):
        if path == main:
            continue
        argv = ['codesign', '--force', '--sign', signer, '--options', 'runtime',
                '--timestamp=none' if local_test else '--timestamp']
        if path == destination / 'Contents/Resources/node/bin/node':
            argv += ['--entitlements', HERE / 'node-entitlements.plist']
        run(argv + [path])
    run(['codesign', '--force', '--sign', signer, '--options', 'runtime',
         '--timestamp=none' if local_test else '--timestamp',
         '--entitlements', HERE / 'app-entitlements.plist', destination])
    entries = audit(destination, strict=True, real=not local_test)
    print(json.dumps({'status': 'local-test-only' if local_test else 'signed-not-notarized', 'binaries': entries}, indent=2))

def notary(args):
    if args.command == 'submit':
        if args.receipt.exists():
            raise SystemExit('Receipt already exists; avoid accidental duplicate submissions')
        if args.file.suffix.lower() not in ['.zip', '.dmg', '.pkg']:
            raise SystemExit('Submit a ZIP, DMG or PKG')
        result = json.loads(capture(['xcrun', 'notarytool', 'submit', args.file, '--keychain-profile', args.profile, '--output-format', 'json', '--no-wait']))
        args.receipt.parent.mkdir(parents=True, exist_ok=True)
        args.receipt.write_text(json.dumps(result, indent=2) + '\n')
        print(json.dumps(result, indent=2))
        return
    receipt = json.loads(args.receipt.read_text())
    submission = receipt['id']
    info = json.loads(capture(['xcrun', 'notarytool', 'info', submission, '--keychain-profile', args.profile, '--output-format', 'json']))
    print(json.dumps(info, indent=2))
    if info.get('status') in ['Accepted', 'Invalid', 'Rejected']:
        log_path = args.receipt.with_suffix('.notary-log.json')
        log = capture(['xcrun', 'notarytool', 'log', submission, '--keychain-profile', args.profile])
        log_path.write_text(log)
        warnings = [issue for issue in json.loads(log).get('issues', []) or [] if issue.get('severity') == 'warning']
        if warnings:
            print(f'Review {len(warnings)} notary warnings in {log_path}', file=sys.stderr)
    if args.command == 'staple':
        if info.get('status') != 'Accepted':
            raise SystemExit('Apple has not accepted this submission; nothing stapled')
        run(['xcrun', 'stapler', 'staple', args.target])
        run(['xcrun', 'stapler', 'validate', args.target])
        if args.target.suffix.lower() == '.app':
            audit(args.target, strict=True, real=True)
            run(['spctl', '--assess', '--type', 'execute', '--verbose=4', args.target])
        elif args.target.suffix.lower() == '.dmg':
            run(['spctl', '--assess', '--type', 'open', '--context', 'context:primary-signature', '--verbose=4', args.target])
        else:
            raise SystemExit('Stapling target must be .app or .dmg')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    check = sub.add_parser('audit')
    check.add_argument('app', type=Path)
    check.add_argument('--strict', action='store_true')
    sign_parser = sub.add_parser('sign')
    sign_parser.add_argument('--source', type=Path, required=True)
    sign_parser.add_argument('--destination', type=Path, required=True)
    group = sign_parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--identity')
    group.add_argument('--local-test', action='store_true')
    for action in ['submit', 'status', 'staple']:
        command = sub.add_parser(action)
        command.add_argument('--profile', required=True)
        command.add_argument('--receipt', type=Path, required=True)
        if action == 'submit': command.add_argument('--file', type=Path, required=True)
        if action == 'staple': command.add_argument('--target', type=Path, required=True)
    args = parser.parse_args()
    if args.command == 'audit':
        print(json.dumps(audit(args.app.resolve(), args.strict), indent=2))
    elif args.command == 'sign':
        sign(args.source.resolve(), args.destination.resolve(), args.identity, args.local_test)
    else:
        notary(args)

if __name__ == '__main__':
    try:
        main()
    except subprocess.CalledProcessError as error:
        print(error.stderr or str(error), file=sys.stderr)
        raise SystemExit(error.returncode)

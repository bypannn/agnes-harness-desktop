#!/usr/bin/env python3
"""Build a self-contained, ad-hoc signed macOS arm64 app from an upstream source build."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--upstream', type=Path, required=True)
parser.add_argument('--node', type=Path, required=True, help='Extracted official Node distribution')
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
source = Path(__file__).resolve().parent
upstream, node, output = args.upstream.resolve(), args.node.resolve(), args.output.resolve()
runtime = upstream / 'packages/cli/dist/local'
assert (runtime / 'agnes.mjs').is_file(), 'Build @agnes/cli build:local first'
assert subprocess.check_output([node / 'bin/node', '--version'], text=True).strip() == 'v24.20.0'
commit = subprocess.check_output(['git', '-C', upstream, 'rev-parse', 'HEAD'], text=True).strip()
if output.exists():
    raise SystemExit(f'Refusing to overwrite an existing app: {output}')
macos = output / 'Contents/MacOS'
resources = output / 'Contents/Resources'
macos.mkdir(parents=True)
resources.mkdir()
try:
    subprocess.run(['swiftc', '-swift-version', '5', '-O', '-target', 'arm64-apple-macosx13.0', '-framework', 'AppKit', '-framework', 'WebKit', source / 'Sources/main.swift', '-o', macos / 'AgnesHarnessDesktop'], check=True)
    shutil.copytree(runtime, resources / 'runtime', symlinks=False)
    # Preserve all bundled modules, helpers and third-party notices, but omit development Node headers.
    (resources / 'node/bin').mkdir(parents=True)
    shutil.copy2(node / 'bin/node', resources / 'node/bin/node')
    shutil.copytree(node / 'lib', resources / 'node/lib', symlinks=True)
    os.symlink('../lib/node_modules/npm/bin/npm-cli.js', resources / 'node/bin/npm')
    os.symlink('../lib/node_modules/npm/bin/npx-cli.js', resources / 'node/bin/npx')
    shutil.copy2(node / 'LICENSE', resources / 'NODE-LICENSE.txt')
    shutil.copy2(source / 'Sources/supervisor.mjs', resources / 'supervisor.mjs')
    shutil.copy2(source / 'Sources/desktop-picker.js', resources / 'desktop-picker.js')
    for name in ['LICENSE', 'NOTICE']:
        shutil.copy2(upstream / name, resources / f'AGNES-{name}.txt')
    (resources / 'BUILD.json').write_text(json.dumps({'app': 'Agnes Harness Desktop', 'version': '0.1.0', 'upstream': 'https://github.com/AgnesAI-Labs/agnes-harness', 'commit': commit, 'node': '24.20.0', 'platform': 'macOS arm64', 'shell': 'AppKit + WKWebView', 'signing': 'ad-hoc; not notarized'}, indent=2) + '\n')
    with tempfile.TemporaryDirectory(prefix='agnes-icon-') as temp:
        iconset = Path(temp) / 'AppIcon.iconset'
        iconset.mkdir()
        for size in [16, 32, 128, 256, 512]:
            for scale in [1, 2]:
                suffix = '@2x' if scale == 2 else ''
                subprocess.run(['sips', '-z', str(size * scale), str(size * scale), upstream / 'packages/web/public/favicon.png', '--out', iconset / f'icon_{size}x{size}{suffix}.png'], check=True, stdout=subprocess.DEVNULL)
        subprocess.run(['iconutil', '-c', 'icns', iconset, '-o', resources / 'AppIcon.icns'], check=True)
    info = {
        'CFBundleDevelopmentRegion': 'zh_CN', 'CFBundleLocalizations': ['zh_CN', 'en'],
        'CFBundleExecutable': 'AgnesHarnessDesktop', 'CFBundleIconFile': 'AppIcon',
        'CFBundleIdentifier': 'local.agnes.harness.desktop', 'CFBundleName': 'Agnes Harness',
        'CFBundleDisplayName': 'Agnes Harness', 'CFBundlePackageType': 'APPL',
        'CFBundleShortVersionString': '0.1.0', 'CFBundleVersion': '1',
        'LSMinimumSystemVersion': '13.0', 'NSHighResolutionCapable': True,
        'NSMicrophoneUsageDescription': '用于你主动开启的语音输入和语音对话。',
        'NSCameraUsageDescription': '用于你主动开启的工作台摄像头功能。',
        'NSAppTransportSecurity': {'NSAllowsLocalNetworking': True},
        'NSHumanReadableCopyright': 'Desktop shell © 2026. Agnes Harness © AgnesAI-Labs. Apache-2.0.',
    }
    (output / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
    # Do not use --deep to re-sign embedded Node; retain its official signature.
    subprocess.run(['codesign', '--force', '--sign', '-', output], check=True)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', output], check=True)
except BaseException:
    shutil.rmtree(output)
    raise
print(output)

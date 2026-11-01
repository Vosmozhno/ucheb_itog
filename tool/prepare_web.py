"""Prepare build/web for Pages without removing renderers needed at runtime."""
import argparse
import hashlib
from pathlib import Path
import shutil

parser = argparse.ArgumentParser()
parser.add_argument('directory', nargs='?', default='build/web')
args = parser.parse_args()
root = Path(args.directory)
bootstrap = (root / 'flutter_bootstrap.js').read_text()
before = sum(p.stat().st_size for p in root.rglob('*') if p.is_file())
wasm_build = '"compileTarget":"dart2wasm"' in bootstrap
for p in (root / 'canvaskit').rglob('*'):
    if not p.is_file():
        continue
    # The JS build uses CanvasKit (full/Chromium); it never loads Skwasm/Wimp.
    if p.name.endswith('.symbols') or (not wasm_build and p.name.startswith(('skwasm', 'wimp'))):
        p.unlink()
# Pages caches static files. Content-based names keep a returning browser from
# mixing the current HTML with JavaScript from a previous deployment.
main_bytes = (root / 'main.dart.js').read_bytes()
main_name = 'main.' + hashlib.sha256(main_bytes).hexdigest()[:16] + '.dart.js'
(root / main_name).write_bytes(main_bytes)
versioned_bootstrap = bootstrap.replace('main.dart.js', main_name)
bootstrap_name = 'flutter_bootstrap.' + hashlib.sha256(versioned_bootstrap.encode()).hexdigest()[:16] + '.js'
(root / bootstrap_name).write_text(versioned_bootstrap)
html = (root / 'index.html').read_text()
html = html.replace('src="flutter_bootstrap.js"', f'src="{bootstrap_name}"')
# Make preparing the same build twice deterministic.
import re
html = re.sub(r'src="flutter_bootstrap\.[a-f0-9]{16}\.js"', f'src="{bootstrap_name}"', html)
(root / 'index.html').write_text(html)
shutil.copyfile(root / 'index.html', root / '404.html')
(root / '.nojekyll').touch()
after = sum(p.stat().st_size for p in root.rglob('*') if p.is_file())
print(f'Before packaging: {before} bytes; after: {after} bytes')
print('Preserved CanvasKit full + Chromium' + (' and Wasm renderers' if wasm_build else ''))

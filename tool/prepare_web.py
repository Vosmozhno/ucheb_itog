"""Prepare build/web for Pages without removing renderers needed at runtime."""
import argparse
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
shutil.copyfile(root / 'index.html', root / '404.html')
(root / '.nojekyll').touch()
after = sum(p.stat().st_size for p in root.rglob('*') if p.is_file())
print(f'Before packaging: {before} bytes; after: {after} bytes')
print('Preserved CanvasKit full + Chromium' + (' and Wasm renderers' if wasm_build else ''))

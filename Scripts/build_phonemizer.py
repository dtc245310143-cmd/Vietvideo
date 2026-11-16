"""Build the existing sea-g2p C API for iPhone and simulator, without Python."""
from pathlib import Path
import shutil
import subprocess
import urllib.request
import zipfile
import platform
import os
import time

ROOT = Path(__file__).resolve().parents[1]
REVISION = 'e825173f235d08ea19315b2b279fb11153b44cea'
vendor = ROOT / 'Vendor'
vendor.mkdir(exist_ok=True)
archive = vendor / 'sea-source.zip'
for attempt in range(3):
    try:
        print(f"Fetching pinned phonemizer source (attempt {attempt + 1})", flush=True)
        with urllib.request.urlopen(f'https://codeload.github.com/pnnbao97/sea-g2p/zip/{REVISION}', timeout=90) as response:
            with archive.open('wb') as target:
                shutil.copyfileobj(response, target)
        break
    except (OSError, TimeoutError):
        if attempt == 2:
            raise
        time.sleep(3)
with zipfile.ZipFile(archive) as z:
    for item in z.infolist():
        target = (vendor / item.filename).resolve()
        if not target.is_relative_to(vendor.resolve()): raise ValueError('Unsafe source archive')
    z.extractall(vendor)
source = vendor / f'sea-g2p-{REVISION}'
cargo = source / 'Cargo.toml'
cargo.write_text(cargo.read_text().replace('["cdylib", "rlib"]', '["staticlib"]'))
simulator_target = 'x86_64-apple-ios' if platform.machine() == 'x86_64' else 'aarch64-apple-ios-sim'
targets = ['aarch64-apple-ios', simulator_target]
subprocess.run(['rustup', 'target', 'add', *targets], check=True)
# Level 1 keeps release optimization without costly level-3 compilation on hosted Macs.
build_env = {**os.environ, 'CARGO_PROFILE_RELEASE_OPT_LEVEL': '1'}
for target in targets:
    print(f'Building phonemizer: {target}', flush=True)
    subprocess.run(['cargo', 'build', '--release', '--locked', '--no-default-features', '--features', 'capi', '--target', target], cwd=source, env=build_env, check=True)
output = vendor / 'SeaG2P.xcframework'
if output.exists(): shutil.rmtree(output)
args = ['xcodebuild', '-create-xcframework']
for target in targets:
    args += ['-library', str(source / 'target' / target / 'release/libsea_g2p_rs.a')]
subprocess.run([*args, '-output', str(output)], check=True)
licenses = ROOT / 'Assets/ThirdParty'
licenses.mkdir(exist_ok=True)
shutil.copy2(source / 'LICENSE', licenses / 'sea-g2p-LICENSE.txt')


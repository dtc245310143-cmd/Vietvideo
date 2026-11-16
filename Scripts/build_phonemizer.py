"""Build the existing sea-g2p C API for iPhone and simulator, without Python."""
from pathlib import Path
import shutil
import subprocess
import urllib.request
import zipfile
import plistlib
import platform

ROOT = Path(__file__).resolve().parents[1]
REVISION = 'e825173f235d08ea19315b2b279fb11153b44cea'
vendor = ROOT / 'Vendor'
vendor.mkdir(exist_ok=True)
archive = vendor / 'sea-source.zip'
urllib.request.urlretrieve(f'https://github.com/pnnbao97/sea-g2p/archive/{REVISION}.zip', archive)
with zipfile.ZipFile(archive) as z:
    for item in z.infolist():
        target = (vendor / item.filename).resolve()
        if not target.is_relative_to(vendor.resolve()): raise ValueError('Unsafe source archive')
    z.extractall(vendor)
source = vendor / f'sea-g2p-{REVISION}'
cargo = source / 'Cargo.toml'
cargo.write_text(cargo.read_text().replace('["cdylib", "rlib"]', '["staticlib"]'))
# Reuse the pinned device library when restoring the stable ARM runner cache.
output = vendor / 'SeaG2P.xcframework'
device_library = None
if (output / 'Info.plist').exists():
    info = plistlib.loads((output / 'Info.plist').read_bytes())
    for row in info['AvailableLibraries']:
        if row.get('SupportedPlatform') == 'ios' and not row.get('SupportedPlatformVariant') and row.get('SupportedArchitectures') == ['arm64']:
            saved = vendor / 'sea-g2p-device.a'
            shutil.copy2(output / row['LibraryIdentifier'] / row['LibraryPath'], saved)
            device_library = saved
            break
simulator_target = 'x86_64-apple-ios' if platform.machine() == 'x86_64' else 'aarch64-apple-ios-sim'
targets = ([ 'aarch64-apple-ios' ] if device_library is None else []) + [simulator_target]
subprocess.run(['rustup', 'target', 'add', *targets], check=True)
for target in targets:
    print(f'Building phonemizer: {target}', flush=True)
    subprocess.run(['cargo', 'build', '--release', '--locked', '--no-default-features', '--features', 'capi', '--target', target], cwd=source, check=True)
output = vendor / 'SeaG2P.xcframework'
if output.exists(): shutil.rmtree(output)
args = ['xcodebuild', '-create-xcframework']
if device_library is not None: args += ['-library', str(device_library)]
for target in targets: args += ['-library', str(source / 'target' / target / 'release/libsea_g2p_rs.a')]
subprocess.run([*args, '-output', str(output)], check=True)
licenses = ROOT / 'Assets/ThirdParty'
licenses.mkdir(exist_ok=True)
shutil.copy2(source / 'LICENSE', licenses / 'sea-g2p-LICENSE.txt')

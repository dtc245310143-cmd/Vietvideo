"""Build the existing sea-g2p C API for iPhone and simulator, without Python."""
from pathlib import Path
import shutil
import subprocess
import urllib.request
import zipfile

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
targets = ['aarch64-apple-ios', 'aarch64-apple-ios-sim', 'x86_64-apple-ios']
subprocess.run(['rustup', 'target', 'add', *targets], check=True)
for target in targets:
    subprocess.run(['cargo', 'build', '--release', '--locked', '--no-default-features', '--features', 'capi', '--target', target], cwd=source, check=True)
output = vendor / 'SeaG2P.xcframework'
if output.exists(): shutil.rmtree(output)
device = source / 'target/aarch64-apple-ios/release/libsea_g2p_rs.a'
simulator = vendor / 'libsea_g2p_simulator.a'
subprocess.run(['lipo', '-create',
                str(source / 'target/aarch64-apple-ios-sim/release/libsea_g2p_rs.a'),
                str(source / 'target/x86_64-apple-ios/release/libsea_g2p_rs.a'),
                '-output', str(simulator)], check=True)
subprocess.run(['xcodebuild', '-create-xcframework', '-library', str(device),
                '-library', str(simulator), '-output', str(output)], check=True)
licenses = ROOT / 'Assets/ThirdParty'
licenses.mkdir(exist_ok=True)
shutil.copy2(source / 'LICENSE', licenses / 'sea-g2p-LICENSE.txt')


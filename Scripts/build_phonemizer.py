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
targets = ['aarch64-apple-ios', 'aarch64-apple-ios-sim']
subprocess.run(['rustup', 'target', 'add', *targets], check=True)
for target in targets:
    subprocess.run(['cargo', 'build', '--release', '--locked', '--no-default-features', '--features', 'capi', '--target', target], cwd=source, check=True)
output = vendor / 'SeaG2P.xcframework'
if output.exists(): shutil.rmtree(output)
args = ['xcodebuild', '-create-xcframework']
for target in targets: args += ['-library', str(source / 'target' / target / 'release/libsea_g2p_rs.a')]
subprocess.run([*args, '-output', str(output)], check=True)
licenses = ROOT / 'Assets/ThirdParty'
licenses.mkdir(exist_ok=True)
shutil.copy2(source / 'LICENSE', licenses / 'sea-g2p-LICENSE.txt')

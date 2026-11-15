"""Download only pinned model files with hashes exported from the approved desktop assets."""
import hashlib
import json
from pathlib import Path
import urllib.request

ROOT = Path(__file__).resolve().parents[1]

def fetch(item, folder):
    target = folder / item['name']
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.is_file() and hashlib.sha256(target.read_bytes()).hexdigest() == item['sha256']:
        return
    temp = target.with_suffix(target.suffix + '.part')
    try:
        digest = hashlib.sha256()
        request = urllib.request.Request(item['url'], headers={'User-Agent': 'VietVideo-iOS-build'})
        with urllib.request.urlopen(request, timeout=120) as response, temp.open('wb') as out:
            while block := response.read(1024 * 1024):
                digest.update(block)
                out.write(block)
        if digest.hexdigest() != item['sha256']:
            raise ValueError('Model checksum mismatch: ' + item['name'])
        temp.replace(target)
    finally:
        temp.unlink(missing_ok=True)

if __name__ == '__main__':
    for item in json.loads((ROOT / 'Assets/model-manifest.json').read_text(encoding='utf-8')):
        print('Downloading ' + item['name'], flush=True)
        fetch(item, ROOT / 'Assets/Models')



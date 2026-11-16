"""Materialize public weights and private voice calibration only inside the build."""
import base64
import json
import os
from pathlib import Path
import zlib
import numpy as np

root = Path(__file__).resolve().parents[1]
target = root / 'Assets/Calibration'
target.mkdir(parents=True, exist_ok=True)
secret = os.environ.get('VIETVIDEO_CALIBRATION_B64', '')
if not secret:
    raise SystemExit('Add repository Actions secret VIETVIDEO_CALIBRATION_B64 from .local/calibration-secret.txt before building.')
raw = zlib.decompress(base64.b64decode(secret, validate=True))
from additional_voices import merge_calibration
additional = json.loads((root / 'VoicePresets/additional.json').read_text(encoding='utf-8'))
record = merge_calibration(raw, additional)
(target / 'calibration.json').write_text(json.dumps(record, ensure_ascii=False, allow_nan=False), encoding='utf-8')
with np.load(root / 'Assets/Models/vieneu_v3_heads.npz', allow_pickle=False) as weights:
    weights['text_emb'].astype('<f4').tofile(target / 'text.f32')
    weights['audio_emb'].astype('<f4').tofile(target / 'audio.f32')
(root / 'Assets/Models/vieneu_v3_heads.npz').unlink()



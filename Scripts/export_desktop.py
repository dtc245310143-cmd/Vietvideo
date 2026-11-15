"""Export deterministic calibration input and exact voice weights from VietVideo 4.4.4."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import base64
import zlib

def export(source, site):
    import numpy as np
    sys.path.insert(0, str(site))
    from tokenizers import Tokenizer
    from vieneu_utils.phonemize_text import phonemize_text_with_emotions
    root = Path(__file__).resolve().parents[1]
    target = root / 'Assets/Calibration'
    target.mkdir(parents=True, exist_ok=True)
    assets = source / 'voice_assets'
    hub = assets / 'hf/hub'
    backbone = next((hub / 'models--pnnbao-ump--VieNeu-TTS-v3-Turbo/snapshots').iterdir())
    codec = next((hub / 'models--OpenMOSS-Team--MOSS-Audio-Tokenizer-Nano-ONNX/snapshots').iterdir())
    model = backbone / 'onnx_update'
    config = json.loads((model / 'config.json').read_text(encoding='utf-8'))
    with np.load(model / 'vieneu_v3_heads.npz', allow_pickle=False) as z:
        text = z['text_emb'].astype('<f4')
        audio = z['audio_emb'].astype('<f4')
        text.tofile(target / 'text.f32')
        audio.tofile(target / 'audio.f32')
        sample = 'Xin chào, đây là giọng thuyết minh Việt Video.'
        phones = phonemize_text_with_emotions(sample)
        tokens = Tokenizer.from_file(str(model / 'tokenizer.json')).encode(phones, add_special_tokens=False).ids
        voices = []
        for i, filename in enumerate(['narration_voice.npz', 'narration_voice2.npz']):
            with np.load(assets / filename, allow_pickle=False) as voice:
                speaker = voice['speaker_emb'].astype(np.float32).reshape(-1)
                anchor = speaker @ z['xvec_w'].T + z['xvec_b']
                anchor = (anchor - anchor.mean()) / np.sqrt(anchor.var() + float(z['xvec_ln_eps']))
                anchor = anchor * z['xvec_ln_w'] + z['xvec_ln_b']
                codes = voice['codes'].astype(np.int64).tolist() if i == 0 else []
                voices.append({'anchor': anchor.tolist(), 'referenceCodes': codes})
        record = {'sample': sample, 'phones': phones, 'tokens': tokens, 'voices': voices,
                  'hidden': config['hidden_size'], 'channels': config['n_vq'],
                  'layers': config['num_hidden_layers'], 'localLayers': config['local_num_hidden_layers'],
                  'localHeads': config['local_num_attention_heads'],
                  'localHeadSize': config['hidden_size'] // config['local_num_attention_heads'],
                  'startToken': config['speech_generation_start_token_id'],
                  'endToken': config['speech_generation_end_token_id'],
                  'styleToken': config['default_style_token_id'],
                  'promptStart': config['text_prompt_start_token_id'],
                  'promptEnd': config['text_prompt_end_token_id'],
                  'referenceToken': config['audio_ref_slot_token_id'],
                  'vocab': text.shape[0], 'audioVocab': audio.shape[1]}
        (target / 'calibration.json').write_text(json.dumps(record, ensure_ascii=False), encoding='utf-8')
    manifest = []
    for repo, revision, folder, names in [
        ('pnnbao-ump/VieNeu-TTS-v3-Turbo', backbone.name, model,
         ['vieneu_prefill.onnx', 'vieneu_decode_step.onnx', 'vieneu_acoustic_cached.onnx', 'vieneu_backbone_shared.data', 'vieneu_v3_heads.npz']),
        ('OpenMOSS-Team/MOSS-Audio-Tokenizer-Nano-ONNX', codec.name, codec,
         ['moss_audio_tokenizer_decode_full.onnx', 'moss_audio_tokenizer_decode_shared.data'])
    ]:
        for name in names:
            path = folder / name
            digest = hashlib.sha256()
            with path.open('rb') as stream:
                while block := stream.read(1024 * 1024): digest.update(block)
            sub = 'onnx_update/' if folder == model else ''
            manifest.append({'name': name, 'sha256': digest.hexdigest(), 'bytes': path.stat().st_size,
                             'url': f'https://huggingface.co/{repo}/resolve/{revision}/{sub}{name}'})
    (root / 'Assets/model-manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    private = root / '.local'
    private.mkdir(exist_ok=True)
    secret = base64.b64encode(zlib.compress((target / 'calibration.json').read_bytes(), 9))
    assert len(secret) < 48 * 1024
    (private / 'calibration-secret.txt').write_bytes(secret)
    print('Exported two original voice anchors, calibration prompt and pinned model hashes.')

if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('--source', type=Path, required=True)
    p.add_argument('--site-packages', type=Path, required=True)
    args = p.parse_args()
    export(args.source, args.site_packages)


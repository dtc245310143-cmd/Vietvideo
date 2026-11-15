import hashlib
from pathlib import Path
import tempfile
import unittest
from fetch_models import fetch

class DownloadTests(unittest.TestCase):
    def test_corrupt_download_preserves_previous_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            upstream = folder / 'upstream'
            upstream.write_bytes(b'bad weights')
            target = folder / 'model.onnx'
            target.write_bytes(b'previous weights')
            item = {'name': 'model.onnx', 'url': upstream.as_uri(), 'sha256': hashlib.sha256(b'expected').hexdigest()}
            with self.assertRaises(ValueError): fetch(item, folder)
            self.assertEqual(target.read_bytes(), b'previous weights')
            self.assertFalse((folder / 'model.onnx.part').exists())

    def test_download_matches_hash(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            source = folder / 'upstream'
            source.write_bytes(b'weights')
            item = {'name': 'model.onnx', 'url': source.as_uri(), 'sha256': hashlib.sha256(b'weights').hexdigest()}
            fetch(item, folder)
            self.assertEqual((folder / 'model.onnx').read_bytes(), b'weights')


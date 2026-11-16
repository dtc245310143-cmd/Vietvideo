"""Merge two narrator presets without changing existing voice cache identities."""
import hashlib
import json
import math


def merge_calibration(raw, additional):
    record = json.loads(raw)
    base = record.get("voices")
    hidden = record.get("hidden")
    if not isinstance(base, list) or len(base) != 2 or not isinstance(hidden, int) or hidden <= 0:
        raise ValueError("Expected the two original voices in the existing Actions secret.")
    extra = additional.get("voices") if isinstance(additional, dict) else None
    if not isinstance(extra, list) or len(extra) != 2:
        raise ValueError("Expected two additional narrator presets.")
    legacy = hashlib.sha256(raw).hexdigest()
    for voice in base:
        if len(voice.get("anchor", [])) != hidden:
            raise ValueError("Original voice dimensions do not match the model.")
        voice["identity"] = legacy
    for voice in extra:
        anchor = voice.get("anchor")
        if not isinstance(anchor, list) or len(anchor) != hidden or not all(
            isinstance(v, (int, float)) and math.isfinite(v) for v in anchor
        ) or not any(v != 0 for v in anchor):
            raise ValueError("Additional voice has an invalid speaker anchor.")
        if voice.get("referenceCodes", []) != []:
            raise ValueError("Additional presets must not contain source audio codes.")
        encoded = json.dumps(anchor, separators=(",", ":"), allow_nan=False).encode("utf-8")
        base.append({"anchor": list(anchor), "referenceCodes": [],
                     "identity": hashlib.sha256(encoded).hexdigest()})
    return record


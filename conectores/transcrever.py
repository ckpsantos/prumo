"""Transcreve áudios (pt) com faster-whisper medium int8. Uso: transcrever.py <saida.json> <audio> [audio...]"""
import json, sys
from faster_whisper import WhisperModel

m = WhisperModel("medium", device="cpu", compute_type="int8")
out = {}
for f in sys.argv[2:]:
    segs, _ = m.transcribe(f, language="pt", vad_filter=True)
    out[f] = " ".join(s.text.strip() for s in segs)
json.dump(out, open(sys.argv[1], "w"), ensure_ascii=False, indent=1)

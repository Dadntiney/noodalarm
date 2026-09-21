# NORI uitlegvideo

Bouwt `media/nori-uitleg.mp4` (+ poster + WebVTT) vanuit
`script.json` met Edge TTS (nl-NL-FennaNeural), Pillow-frames en ffmpeg.

```bash
pip install edge-tts Pillow
export PATH="$HOME/.local/bin:$PATH"
python3 scripts/nori-video/build_video.py
```

Inhoud volgt de echte NORI-app: Contacten, Berichten, ALARM (4s annuleren),
noodcontacten, locatie, reddingskaart. Geen verzonnen functies.

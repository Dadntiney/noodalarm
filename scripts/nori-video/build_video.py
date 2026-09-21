#!/usr/bin/env python3
"""Build NORI explainer video — warm 16:9 animation + natural Dutch VO."""

from __future__ import annotations

import asyncio
import json
import math
import os
import shutil
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "media"
WORK = Path("/tmp/nori-video")
FRAMES = WORK / "frames"
AUDIO = WORK / "audio"
SCRIPT = Path(__file__).with_name("script.json")

W, H = 1920, 1080
FPS = 24
VOICE = "nl-NL-ColetteNeural"
RATE = "-12%"
PITCH = "+2Hz"

BG_TOP = (236, 247, 245)
BG_BOT = (248, 250, 252)
TEAL = (15, 118, 110)
TEAL_SOFT = (45, 158, 148)
RED = (220, 38, 38)
RED_SOFT = (254, 226, 226)
INK = (17, 24, 39)
MUTED = (75, 85, 99)
WHITE = (255, 255, 255)
ACCENT = (24, 119, 242)
GREEN = (22, 163, 74)
AMBER = (217, 119, 6)


def ensure_dirs():
    for p in (OUT_DIR, WORK, FRAMES, AUDIO):
        if p in (FRAMES, AUDIO):
            shutil.rmtree(p, ignore_errors=True)
        p.mkdir(parents=True, exist_ok=True)


def load_font(size: int, bold: bool = False):
    candidates = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
    ]
    for path in candidates:
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def lerp(a, b, t):
    return a + (b - a) * t


def ease_out(t: float) -> float:
    t = max(0.0, min(1.0, t))
    return 1 - (1 - t) ** 3


def ease_in_out(t: float) -> float:
    t = max(0.0, min(1.0, t))
    return 3 * t * t - 2 * t * t * t


def mix(c1, c2, t):
    return tuple(int(lerp(c1[i], c2[i], t)) for i in range(3))


def text_size(draw, text, font):
    box = draw.textbbox((0, 0), text, font=font)
    return box[2] - box[0], box[3] - box[1]


def wrap_text(draw, text, font, max_width):
    words = text.split()
    lines, cur = [], ""
    for w in words:
        trial = (cur + " " + w).strip()
        tw, _ = text_size(draw, trial, font)
        if tw <= max_width or not cur:
            cur = trial
        else:
            lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines


def rounded_rect(draw, box, radius, fill, outline=None, width=1):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def gradient_bg(draw):
    for y in range(H):
        t = y / (H - 1)
        # soft diagonal wash
        c = mix(BG_TOP, BG_BOT, t * 0.85)
        draw.line([(0, y), (W, y)], fill=c)


def soft_blob(img, xy, r, color, alpha=32):
    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)
    x, y = xy
    d.ellipse([x - r, y - r, x + r, y + r], fill=(*color, alpha))
    overlay = overlay.filter(ImageFilter.GaussianBlur(radius=max(8, r // 8)))
    return Image.alpha_composite(img.convert("RGBA"), overlay)


def draw_nori_mark(draw, cx, cy, scale=1.0, color=TEAL):
    for i, (r, _) in enumerate([(48, 0.28), (30, 0.55), (11, 1.0)]):
        rr = int(r * scale)
        if i < 2:
            draw.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], outline=color, width=max(3, int(4 * scale)))
        else:
            draw.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=color)


def draw_person(draw, cx, cy, scale=1.0, shirt=TEAL_SOFT, skin=(255, 224, 196)):
    s = scale
    r = int(32 * s)
    draw.ellipse([cx - r, cy - r - int(58 * s), cx + r, cy + r - int(58 * s)], fill=skin)
    body = [cx - int(42 * s), cy - int(16 * s), cx + int(42 * s), cy + int(72 * s)]
    rounded_rect(draw, body, int(24 * s), shirt)
    draw.arc([cx - int(14 * s), cy - int(66 * s), cx + int(14 * s), cy - int(44 * s)], 20, 160, fill=INK, width=max(2, int(3 * s)))
    er = max(2, int(3 * s))
    draw.ellipse([cx - int(10 * s) - er, cy - int(70 * s) - er, cx - int(10 * s) + er, cy - int(70 * s) + er], fill=INK)
    draw.ellipse([cx + int(10 * s) - er, cy - int(70 * s) - er, cx + int(10 * s) + er, cy - int(70 * s) + er], fill=INK)


def draw_phone(draw, cx, cy, scale=1.0, screen_fn=None):
    pw, ph = int(160 * scale), int(290 * scale)
    x0, y0 = cx - pw // 2, cy - ph // 2
    rounded_rect(draw, [x0, y0, x0 + pw, y0 + ph], int(28 * scale), INK)
    inset = int(10 * scale)
    rounded_rect(draw, [x0 + inset, y0 + inset, x0 + pw - inset, y0 + ph - inset], int(20 * scale), WHITE)
    if screen_fn:
        screen_fn(draw, x0 + inset, y0 + inset, pw - 2 * inset, ph - 2 * inset)


def draw_caption(img, text: str):
    if not text:
        return img
    draw = ImageDraw.Draw(img)
    font = load_font(42, bold=True)
    lines = wrap_text(draw, text, font, W - 200)
    heights = [text_size(draw, ln, font)[1] for ln in lines]
    block_h = sum(heights) + 8 * max(0, len(lines) - 1) + 28
    y0 = H - 48 - block_h
    overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    od.rounded_rectangle([70, y0, W - 70, y0 + block_h], radius=22, fill=(17, 24, 39, 200))
    img = Image.alpha_composite(img.convert("RGBA"), overlay)
    draw = ImageDraw.Draw(img)
    y = y0 + 14
    for line in lines:
        tw, th = text_size(draw, line, font)
        draw.text(((W - tw) / 2, y), line, font=font, fill=WHITE)
        y += th + 8
    return img


def scene_welcome(t_local, seg, _):
    img = Image.new("RGB", (W, H), BG_BOT)
    draw = ImageDraw.Draw(img)
    gradient_bg(draw)
    img = soft_blob(img, (W // 2, 380), 420, TEAL, 40)
    draw = ImageDraw.Draw(img)
    appear = ease_out(min(1.0, t_local / 0.7))
    cx, cy = W // 2, int(lerp(420, 360, appear))
    draw_nori_mark(draw, cx, cy, scale=2.6 * (0.85 + 0.15 * appear))
    title_font = load_font(72, bold=True)
    tw, _ = text_size(draw, "NORI", title_font)
    draw.text(((W - tw) / 2, cy + 120), "NORI", font=title_font, fill=mix(BG_BOT, TEAL, appear))
    if t_local > 1.0:
        p = ease_out(min(1.0, (t_local - 1.0) / 0.8))
        draw_person(draw, int(lerp(W // 2, 480, p)), 720, 1.15, shirt=TEAL_SOFT)
        draw_person(draw, int(lerp(W // 2, 960, p)), 720, 1.15, shirt=(96, 165, 250))
        draw_person(draw, int(lerp(W // 2, 1440, p)), 720, 1.15, shirt=(251, 146, 60))
        if p > 0.35:
            col = mix(BG_BOT, TEAL, p)
            draw.line([(560, 640), (W // 2 - 50, 430)], fill=col, width=5)
            draw.line([(960, 640), (W // 2, 430)], fill=col, width=5)
            draw.line([(1360, 640), (W // 2 + 50, 430)], fill=col, width=5)
    return img


def scene_features(t_local, seg, _):
    img = Image.new("RGB", (W, H), BG_BOT)
    draw = ImageDraw.Draw(img)
    gradient_bg(draw)
    title_font = load_font(52, bold=True)
    draw.text((100, 80), "Wat kun je met NORI?", font=title_font, fill=INK)
    features = [
        ("contacts", "Contacten", "Mensen die jij vertrouwt", TEAL),
        ("messages", "Berichten", "Samen in één chat", ACCENT),
        ("alarm", "ALARM", "Bij nood, één druk", RED),
    ]
    active = seg.get("feature")
    card_w, card_h = 520, 420
    gap = 40
    total = 3 * card_w + 2 * gap
    x0 = (W - total) // 2
    for i, (key, title, sub, color) in enumerate(features):
        delay = i * 0.28
        p = ease_out(max(0.0, min(1.0, (t_local - delay) / 0.55)))
        x = x0 + i * (card_w + gap)
        y = int(lerp(520, 280, p))
        highlight = active == key
        outline = color if highlight else (226, 232, 240)
        fill = mix(WHITE, color, 0.08) if highlight else WHITE
        rounded_rect(draw, [x, y, x + card_w, y + card_h], 32, fill, outline, 5 if highlight else 3)
        cx, cy = x + card_w // 2, y + 140
        draw.ellipse([cx - 55, cy - 55, cx + 55, cy + 55], fill=color)
        if key == "contacts":
            draw.ellipse([cx - 16, cy - 28, cx + 16, cy - 2], fill=WHITE)
            draw.pieslice([cx - 34, cy - 4, cx + 34, cy + 42], 0, 180, fill=WHITE)
        elif key == "messages":
            rounded_rect(draw, [cx - 30, cy - 22, cx + 30, cy + 18], 12, WHITE)
            draw.polygon([(cx - 10, cy + 18), (cx + 4, cy + 18), (cx - 8, cy + 34)], fill=WHITE)
        else:
            draw.ellipse([cx - 28, cy - 28, cx + 28, cy + 28], outline=WHITE, width=6)
            draw.ellipse([cx - 8, cy - 8, cx + 8, cy + 8], fill=WHITE)
        lf = load_font(40, bold=True)
        tw, _ = text_size(draw, title, lf)
        draw.text((x + (card_w - tw) / 2, y + 230), title, font=lf, fill=color if highlight else INK)
        sf = load_font(28)
        tw, _ = text_size(draw, sub, sf)
        draw.text((x + (card_w - tw) / 2, y + 290), sub, font=sf, fill=MUTED)
    return img


def scene_example(t_local, seg, _):
    img = Image.new("RGB", (W, H), BG_BOT)
    draw = ImageDraw.Draw(img)
    gradient_bg(draw)
    title_font = load_font(48, bold=True)
    draw.text((100, 70), "Een herkenbaar voorbeeld", font=title_font, fill=INK)
    step = seg.get("step", 0)

    def phone_screen(d, x, y, w, h):
        d.rectangle([x, y, x + w, y + 54], fill=TEAL)
        d.text((x + 18, y + 14), "NORI", font=load_font(24, bold=True), fill=WHITE)
        cx, cy = x + w // 2, y + h // 2 + 10
        r = 58
        col = RED if step >= 1 else (248, 113, 113)
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=col)
        af = load_font(24, bold=True)
        tw, th = text_size(d, "ALARM", af)
        d.text((cx - tw / 2, cy - th / 2), "ALARM", font=af, fill=WHITE)
        if step == 2:
            d.text((x + 24, y + h - 70), "4… 3… 2… 1", font=load_font(24, bold=True), fill=AMBER)
        if step >= 3:
            rounded_rect(d, [x + 14, y + 70, x + w - 14, y + 130], 14, RED_SOFT)
            d.text((x + 28, y + 88), "Verzonden ✓", font=load_font(22, bold=True), fill=RED)

    draw_phone(draw, 620, 520, 1.35, phone_screen)
    p = ease_out(min(1.0, max(0.0, (t_local - 0.35) / 0.75))) if step >= 3 else 0.1
    rx = int(lerp(2100, 1280, p if step >= 3 else 0))
    draw_phone(draw, rx, 520, 1.15)
    if step >= 3 and p > 0.3:
        nx, ny = rx - 170, 250
        rounded_rect(draw, [nx, ny, nx + 340, ny + 130], 22, WHITE, TEAL, 3)
        draw.text((nx + 22, ny + 24), "Noodmelding", font=load_font(28, bold=True), fill=RED)
        draw.text((nx + 22, ny + 68), "Iemand heeft ALARM\ningedrukt", font=load_font(24), fill=MUTED)
        draw.line([(760, 520), (rx - 140, 520)], fill=TEAL, width=6)
        draw.polygon([(rx - 140, 500), (rx - 140, 540), (rx - 110, 520)], fill=TEAL)
    if step == 0:
        draw_person(draw, W // 2, 480, 1.3, shirt=(251, 146, 60))
        draw.text((W // 2 - 160, 640), "Niet zo lekker…", font=load_font(32), fill=MUTED)
    return img


def scene_contacts(t_local, seg, _):
    img = Image.new("RGB", (W, H), BG_BOT)
    draw = ImageDraw.Draw(img)
    gradient_bg(draw)
    draw.text((100, 70), "Contacten", font=load_font(52, bold=True), fill=INK)
    draw.text((100, 140), "Mensen die jij hebt gekozen", font=load_font(32), fill=MUTED)
    names = [("Anna", TEAL_SOFT), ("Omar", (96, 165, 250)), ("Lisa", (251, 146, 60))]
    card_w = 520
    gap = 36
    total = 3 * card_w + 2 * gap
    x0 = (W - total) // 2
    for i, (name, color) in enumerate(names):
        p = ease_out(max(0.0, min(1.0, (t_local - i * 0.28) / 0.55)))
        x = x0 + i * (card_w + gap)
        y = int(lerp(480, 300, p))
        rounded_rect(draw, [x, y, x + card_w, y + 280], 28, WHITE, (226, 232, 240), 3)
        draw.ellipse([x + 40, y + 70, x + 140, y + 170], fill=color)
        ifont = load_font(44, bold=True)
        tw, th = text_size(draw, name[0], ifont)
        draw.text((x + 90 - tw / 2, y + 120 - th / 2), name[0], font=ifont, fill=WHITE)
        draw.text((x + 170, y + 90), name, font=load_font(36, bold=True), fill=INK)
        status = "Geaccepteerd ✓" if t_local > 1.3 or i == 0 else "Wacht op acceptatie…"
        draw.text((x + 170, y + 150), status, font=load_font(26), fill=GREEN if "✓" in status else AMBER)
    if t_local > 1.5:
        flow = "Zoeken → Toevoegen → Accepteren"
        ff = load_font(34, bold=True)
        tw, _ = text_size(draw, flow, ff)
        draw.text(((W - tw) / 2, 680), flow, font=ff, fill=TEAL)
    return img


def scene_alarm(t_local, seg, _):
    img = Image.new("RGB", (W, H), BG_BOT)
    draw = ImageDraw.Draw(img)
    gradient_bg(draw)
    draw.text((100, 70), "ALARM", font=load_font(52, bold=True), fill=RED)
    draw.text((100, 140), "Voor als je echt hulp nodig hebt", font=load_font(32), fill=MUTED)
    pulse = 0.5 + 0.5 * math.sin(t_local * 2.0)
    r = int(130 + 8 * pulse)
    cx, cy = 420, 520
    for ring in (1.4, 1.2, 1.0):
        rr = int(r * ring)
        draw.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], outline=mix(WHITE, RED, 0.4 if ring > 1 else 1), width=7 if ring == 1 else 4)
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=RED)
    af = load_font(40, bold=True)
    tw, th = text_size(draw, "ALARM", af)
    draw.text((cx - tw / 2, cy - th / 2), "ALARM", font=af, fill=WHITE)

    cards = [
        ("bell", "Noodcontacten\nkrijgen melding", 0.35),
        ("pin", "Jouw locatie\ngaat mee", 0.55),
        ("cross", "Reddingskaart\nop jouw telefoon", 0.75),
    ]
    for i, (icon, label, delay) in enumerate(cards):
        p = ease_out(max(0.0, min(1.0, (t_local - delay) / 0.5)))
        x = 780 + i * 340
        y = int(lerp(620, 360, p))
        rounded_rect(draw, [x, y, x + 300, y + 300], 26, WHITE, (226, 232, 240), 3)
        icx, icy = x + 150, y + 90
        draw.ellipse([icx - 36, icy - 36, icx + 36, icy + 36], fill=TEAL if icon != "cross" else RED)
        if icon == "bell":
            rounded_rect(draw, [icx - 14, icy - 16, icx + 14, icy + 10], 8, WHITE)
            draw.rectangle([icx - 4, icy + 10, icx + 4, icy + 18], fill=WHITE)
            draw.ellipse([icx - 6, icy + 16, icx + 6, icy + 24], fill=WHITE)
        elif icon == "pin":
            draw.ellipse([icx - 14, icy - 18, icx + 14, icy + 10], outline=WHITE, width=5)
            draw.polygon([(icx, icy + 28), (icx - 12, icy + 6), (icx + 12, icy + 6)], fill=WHITE)
            draw.ellipse([icx - 5, icy - 8, icx + 5, icy + 2], fill=TEAL)
        else:
            draw.rectangle([icx - 6, icy - 18, icx + 6, icy + 18], fill=WHITE)
            draw.rectangle([icx - 18, icy - 6, icx + 18, icy + 6], fill=WHITE)
        lf = load_font(26, bold=True)
        for j, line in enumerate(label.split("\n")):
            tw, _ = text_size(draw, line, lf)
            draw.text((x + (300 - tw) / 2, y + 160 + j * 36), line, font=lf, fill=INK)
    return img


def scene_outro(t_local, seg, _):
    img = Image.new("RGB", (W, H), BG_BOT)
    draw = ImageDraw.Draw(img)
    gradient_bg(draw)
    img = soft_blob(img, (W // 2, 420), 460, TEAL, 45)
    draw = ImageDraw.Draw(img)
    appear = ease_out(min(1.0, t_local / 0.55))
    draw_nori_mark(draw, W // 2, int(lerp(480, 380, appear)), scale=2.8)
    title_font = load_font(72, bold=True)
    tw, _ = text_size(draw, "NORI", title_font)
    draw.text(((W - tw) / 2, 520), "NORI", font=title_font, fill=TEAL)
    if t_local > 0.9:
        msg_font = load_font(40, bold=True)
        lines = wrap_text(draw, "Je bent klaar om NORI te gebruiken", msg_font, W - 280)
        y = 620
        for line in lines:
            tw, th = text_size(draw, line, msg_font)
            draw.text(((W - tw) / 2, y), line, font=msg_font, fill=INK)
            y += th + 10
    if t_local > 1.3:
        p = ease_out(min(1.0, (t_local - 1.3) / 0.6))
        draw_person(draw, 640, int(lerp(980, 820, p)), 1.1, shirt=TEAL_SOFT)
        draw_person(draw, 960, int(lerp(980, 840, p)), 1.1, shirt=(96, 165, 250))
        draw_person(draw, 1280, int(lerp(980, 820, p)), 1.1, shirt=(251, 146, 60))
    return img


SCENES = {
    "welcome": scene_welcome,
    "features": scene_features,
    "example": scene_example,
    "contacts": scene_contacts,
    "alarm": scene_alarm,
    "outro": scene_outro,
}


async def synthesize_segment(seg, out_path: Path):
    import edge_tts
    # Light SSML-ish pacing via punctuation already in text; edge-tts rate/pitch for warmth.
    communicate = edge_tts.Communicate(seg["text"], VOICE, rate=RATE, pitch=PITCH)
    await communicate.save(str(out_path))


def audio_duration(path: Path) -> float:
    r = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "default=nk=1:nw=1", str(path)],
        capture_output=True, text=True, check=True,
    )
    return float(r.stdout.strip())


async def build_voice(segments):
    timeline = []
    t = 0.45
    for seg in segments:
        mp3 = AUDIO / f"{seg['id']}.mp3"
        await synthesize_segment(seg, mp3)
        dur = audio_duration(mp3)
        timeline.append({**seg, "start": t, "duration": dur, "path": mp3})
        t += dur + float(seg.get("pauseAfter", 0.4))
    return timeline, t + 0.5


def write_concat_audio(timeline, out_path: Path):
    inputs = ["-f", "lavfi", "-t", "0.45", "-i", "anullsrc=r=24000:cl=mono"]
    concat_labels = ["[0:a]"]
    i = 1
    for seg in timeline:
        inputs += ["-i", str(seg["path"])]
        concat_labels.append(f"[{i}:a]")
        i += 1
        silence = float(seg.get("pauseAfter", 0.4))
        inputs += ["-f", "lavfi", "-t", str(silence), "-i", "anullsrc=r=24000:cl=mono"]
        concat_labels.append(f"[{i}:a]")
        i += 1
    inputs += ["-f", "lavfi", "-t", "0.5", "-i", "anullsrc=r=24000:cl=mono"]
    concat_labels.append(f"[{i}:a]")
    filter_complex = "".join(concat_labels) + f"concat=n={len(concat_labels)}:v=0:a=1[outa]"
    subprocess.run(
        ["ffmpeg", "-y", *inputs, "-filter_complex", filter_complex, "-map", "[outa]", "-ac", "1", "-ar", "24000", str(out_path)],
        check=True, capture_output=True,
    )


def make_music(duration: float, path: Path):
    # Soft warm pad — lower than before so VO stays clear.
    cmd = [
        "ffmpeg", "-y",
        "-f", "lavfi", "-i", f"sine=frequency=174.61:duration={duration}",
        "-f", "lavfi", "-i", f"sine=frequency=220:duration={duration}",
        "-f", "lavfi", "-i", f"sine=frequency=261.63:duration={duration}",
        "-f", "lavfi", "-i", f"sine=frequency=329.63:duration={duration}",
        "-filter_complex",
        "[0:a]volume=0.018[a0];[1:a]volume=0.015[a1];[2:a]volume=0.012[a2];"
        "[3:a]volume=0.01,tremolo=f=0.1:d=0.35[a3];"
        "[a0][a1][a2][a3]amix=inputs=4:duration=longest,lowpass=f=900,volume=0.4[out]",
        "-map", "[out]", "-ac", "2", "-ar", "44100", str(path),
    ]
    subprocess.run(cmd, check=True, capture_output=True)


def make_confirm_sfx(path: Path):
    cmd = [
        "ffmpeg", "-y",
        "-f", "lavfi", "-i", "sine=frequency=784:duration=0.1",
        "-f", "lavfi", "-i", "sine=frequency=988:duration=0.14",
        "-filter_complex", "[0:a][1:a]acrossfade=d=0.04,volume=0.12[out]",
        "-map", "[out]", str(path),
    ]
    subprocess.run(cmd, check=True, capture_output=True)


def render_frames(timeline, total):
    scene_starts = {}
    for seg in timeline:
        scene_starts.setdefault(seg["scene"], seg["start"])
    n_frames = int(math.ceil(total * FPS))
    for fi in range(n_frames):
        t = fi / FPS
        active = timeline[0]
        for seg in timeline:
            if seg["start"] <= t < seg["start"] + seg["duration"] + float(seg.get("pauseAfter", 0.4)):
                active = seg
                break
            if t >= seg["start"]:
                active = seg
        t_local = t - scene_starts[active["scene"]]
        img = SCENES[active["scene"]](t_local, active, 0)
        img = draw_caption(img, active.get("onScreen") or "")
        img.convert("RGB").save(FRAMES / f"frame_{fi:05d}.png", optimize=True)
        if fi % 24 == 0:
            print(f"  frame {fi}/{n_frames} ({100 * fi / n_frames:.0f}%)")
    return n_frames


def write_vtt(timeline, path: Path):
    def vtt_ts(sec: float) -> str:
        h = int(sec // 3600)
        m = int((sec % 3600) // 60)
        s = sec % 60
        return f"{h:02d}:{m:02d}:{s:06.3f}"

    lines = ["WEBVTT", ""]
    for i, seg in enumerate(timeline):
        start = seg["start"]
        end = seg["start"] + seg["duration"] + 0.05
        lines.append(str(i + 1))
        lines.append(f"{vtt_ts(start)} --> {vtt_ts(end)}")
        lines.append(seg["text"])
        lines.append("")
    path.write_text("\n".join(lines), encoding="utf-8")


def mux(voice_path, music_path, sfx_path, timeline, out_mp4: Path):
    sfx_at = next((s["start"] for s in timeline if s["id"] == "s3c"), 20.0)
    cmd = [
        "ffmpeg", "-y",
        "-framerate", str(FPS),
        "-i", str(FRAMES / "frame_%05d.png"),
        "-i", str(voice_path),
        "-i", str(music_path),
        "-i", str(sfx_path),
        "-filter_complex",
        f"[1:a]volume=1.05[vo];"
        f"[2:a]volume=0.12[bg];"
        f"[3:a]adelay={int(sfx_at * 1000)}|{int(sfx_at * 1000)},volume=0.22[sfx];"
        f"[vo][bg][sfx]amix=inputs=3:duration=first:dropout_transition=2[aout]",
        "-map", "0:v", "-map", "[aout]",
        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-profile:v", "main",
        "-crf", "23", "-preset", "medium", "-movflags", "+faststart",
        "-c:a", "aac", "-b:a", "128k", "-shortest",
        str(out_mp4),
    ]
    subprocess.run(cmd, check=True)


def make_poster(timeline, path: Path):
    img = scene_welcome(1.6, timeline[0], 0)
    draw = ImageDraw.Draw(img)
    overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    od.rounded_rectangle([W // 2 - 320, H // 2 + 40, W // 2 + 320, H // 2 + 200], radius=28, fill=(17, 24, 39, 205))
    img = Image.alpha_composite(img.convert("RGBA"), overlay)
    draw = ImageDraw.Draw(img)
    font = load_font(40, bold=True)
    for i, line in enumerate(["Bekijk hoe NORI werkt", "Tik om te openen"]):
        tw, th = text_size(draw, line, font)
        draw.text(((W - tw) / 2, H // 2 + 70 + i * 50), line, font=font, fill=WHITE)
    cx, cy = W // 2, H // 2 - 40
    draw.ellipse([cx - 56, cy - 56, cx + 56, cy + 56], fill=TEAL)
    draw.polygon([(cx - 18, cy - 28), (cx - 18, cy + 28), (cx + 34, cy)], fill=WHITE)
    img.convert("RGB").resize((1280, 720), Image.Resampling.LANCZOS).save(path, quality=86, optimize=True)


async def main():
    ensure_dirs()
    data = json.loads(SCRIPT.read_text(encoding="utf-8"))
    print("Synthesizing voice-over (Colette, warm)…")
    timeline, total = await build_voice(data["segments"])
    print(f"Duration ≈ {total:.1f}s")
    voice_path = AUDIO / "voice.mp3"
    write_concat_audio(timeline, voice_path)
    music_path = AUDIO / "music.mp3"
    make_music(total + 0.5, music_path)
    sfx_path = AUDIO / "confirm.mp3"
    make_confirm_sfx(sfx_path)
    print("Rendering 16:9 frames…")
    render_frames(timeline, total)
    out_mp4 = OUT_DIR / "nori-uitleg.mp4"
    tmp = OUT_DIR / "nori-uitleg-tmp.mp4"
    print("Muxing…")
    mux(voice_path, music_path, sfx_path, timeline, tmp)
    # Compress for chat (~720p wide)
    subprocess.run([
        "ffmpeg", "-y", "-i", str(tmp),
        "-vf", "scale=1280:-2",
        "-c:v", "libx264", "-crf", "25", "-preset", "medium",
        "-c:a", "aac", "-b:a", "96k", "-movflags", "+faststart",
        str(out_mp4),
    ], check=True)
    tmp.unlink(missing_ok=True)
    write_vtt(timeline, OUT_DIR / "nori-uitleg.nl.vtt")
    make_poster(timeline, OUT_DIR / "nori-uitleg-poster.jpg")
    print(f"Done {out_mp4} ({out_mp4.stat().st_size / 1e6:.2f} MB) {total:.1f}s")


if __name__ == "__main__":
    asyncio.run(main())

#!/usr/bin/env python3
"""Build the NORI explainer video: TTS + animated frames + soft music + captions."""

from __future__ import annotations

import asyncio
import json
import math
import os
import shutil
import subprocess
import wave
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "media"
WORK = Path("/tmp/nori-video")
FRAMES = WORK / "frames"
AUDIO = WORK / "audio"
SCRIPT = Path(__file__).with_name("script.json")

W, H = 1080, 1920  # vertical, chat-friendly
FPS = 24
VOICE = "nl-NL-FennaNeural"

# NORI palette (warm, calm, not purple/cream-terracotta cliché)
BG_TOP = (232, 245, 243)
BG_BOT = (248, 250, 252)
TEAL = (15, 118, 110)
TEAL_SOFT = (45, 158, 148)
RED = (220, 38, 38)
RED_SOFT = (254, 226, 226)
INK = (17, 24, 39)
MUTED = (75, 85, 99)
WHITE = (255, 255, 255)
CARD = (255, 255, 255)
ACCENT = (24, 119, 242)
GREEN = (22, 163, 74)
AMBER = (217, 119, 6)


def ensure_dirs():
    for p in (OUT_DIR, WORK, FRAMES, AUDIO):
        if p in (FRAMES, AUDIO):
            shutil.rmtree(p, ignore_errors=True)
        p.mkdir(parents=True, exist_ok=True)


def load_font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    candidates = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
        "/usr/share/fonts/opentype/noto/NotoSans-Bold.ttf" if bold else "/usr/share/fonts/opentype/noto/NotoSans-Regular.ttf",
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


def mix(c1, c2, t):
    return tuple(int(lerp(c1[i], c2[i], t)) for i in range(3))


def gradient_bg(draw: ImageDraw.ImageDraw):
    for y in range(H):
        t = y / (H - 1)
        # soft vertical wash + subtle radial feel via horizontal fade
        c = mix(BG_TOP, BG_BOT, t)
        draw.line([(0, y), (W, y)], fill=c)
    # soft teal glow top-center
    for r in range(420, 0, -12):
        alpha = int(18 * (r / 420))
        # approximate by lightening a circle band
        pass


def draw_soft_circle(img: Image.Image, xy, r, color, alpha=40):
    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)
    x, y = xy
    d.ellipse([x - r, y - r, x + r, y + r], fill=(*color, alpha))
    return Image.alpha_composite(img.convert("RGBA"), overlay)


def rounded_rect(draw, box, radius, fill, outline=None, width=1):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


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


def draw_centered_lines(draw, lines, y, font, fill, gap=12):
    for line in lines:
        tw, th = text_size(draw, line, font)
        draw.text(((W - tw) / 2, y), line, font=font, fill=fill)
        y += th + gap
    return y


def draw_person(draw, cx, cy, scale=1.0, shirt=TEAL_SOFT, skin=(255, 224, 196)):
    s = scale
    # head
    r = int(38 * s)
    draw.ellipse([cx - r, cy - r - int(70 * s), cx + r, cy + r - int(70 * s)], fill=skin)
    # body
    body = [
        cx - int(48 * s), cy - int(20 * s),
        cx + int(48 * s), cy + int(90 * s),
    ]
    rounded_rect(draw, body, int(28 * s), shirt)
    # simple smile
    draw.arc(
        [cx - int(16 * s), cy - int(78 * s), cx + int(16 * s), cy - int(52 * s)],
        start=20, end=160, fill=INK, width=max(2, int(3 * s))
    )
    # eyes
    er = max(2, int(3.5 * s))
    draw.ellipse([cx - int(12 * s) - er, cy - int(82 * s) - er, cx - int(12 * s) + er, cy - int(82 * s) + er], fill=INK)
    draw.ellipse([cx + int(12 * s) - er, cy - int(82 * s) - er, cx + int(12 * s) + er, cy - int(82 * s) + er], fill=INK)


def draw_nori_mark(draw, cx, cy, scale=1.0, color=TEAL):
    for i, (r, a) in enumerate([(52, 0.28), (34, 0.55), (12, 1.0)]):
        rr = int(r * scale)
        if i < 2:
            draw.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], outline=color, width=max(3, int(4 * scale)))
        else:
            draw.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=color)


def draw_phone(draw, cx, cy, scale=1.0, screen_fn=None):
    pw, ph = int(220 * scale), int(400 * scale)
    x0, y0 = cx - pw // 2, cy - ph // 2
    rounded_rect(draw, [x0, y0, x0 + pw, y0 + ph], int(36 * scale), INK)
    inset = int(12 * scale)
    rounded_rect(draw, [x0 + inset, y0 + inset, x0 + pw - inset, y0 + ph - inset], int(26 * scale), WHITE)
    if screen_fn:
        screen_fn(draw, x0 + inset, y0 + inset, pw - 2 * inset, ph - 2 * inset)


def draw_caption_bar(draw, text: str, progress: float = 1.0):
    if not text:
        return
    font = load_font(44, bold=True)
    lines = wrap_text(draw, text, font, W - 140)
    # measure
    heights = [text_size(draw, ln, font)[1] for ln in lines]
    block_h = sum(heights) + 12 * (len(lines) - 1) + 48
    y0 = H - 280 - block_h
    alpha_box = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ad = ImageDraw.Draw(alpha_box)
    ad.rounded_rectangle([50, y0, W - 50, y0 + block_h], radius=28, fill=(17, 24, 39, 200))
    return alpha_box, lines, y0 + 24, font


def scene_welcome(t_local, seg, total_in_scene):
    img = Image.new("RGB", (W, H), BG_BOT)
    draw = ImageDraw.Draw(img)
    gradient_bg(draw)
    img = draw_soft_circle(img, (W // 2, 520), 360, TEAL, 35)
    draw = ImageDraw.Draw(img)

    appear = ease_out(min(1.0, t_local / 0.6))
    cy = int(lerp(640, 560, appear))
    draw_nori_mark(draw, W // 2, cy, scale=2.2 * (0.85 + 0.15 * appear))

    title_font = load_font(72, bold=True)
    sub_font = load_font(40)
    title = "NORI"
    tw, th = text_size(draw, title, title_font)
    draw.text(((W - tw) / 2, cy + 140), title, font=title_font, fill=mix(BG_BOT, TEAL, appear))

    # connection visual: user <-> NORI <-> contacts
    if t_local > 1.2:
        p = ease_out(min(1.0, (t_local - 1.2) / 0.7))
        draw_person(draw, int(lerp(W // 2, 250, p)), 1180, 1.05, shirt=TEAL_SOFT)
        draw_person(draw, int(lerp(W // 2, 830, p)), 1180, 1.05, shirt=(96, 165, 250))
        draw_person(draw, int(lerp(W // 2, 540, p)), 1320, 0.9, shirt=(251, 146, 60))
        if p > 0.4:
            draw.line([(320, 1120), (W // 2 - 40, 700)], fill=mix(BG_BOT, TEAL, p), width=5)
            draw.line([(760, 1120), (W // 2 + 40, 700)], fill=mix(BG_BOT, TEAL, p), width=5)
            draw.line([(540, 1220), (W // 2, 700)], fill=mix(BG_BOT, TEAL_SOFT, p), width=4)

    return img


def scene_features(t_local, seg, total_in_scene):
    img = Image.new("RGB", (W, H), BG_BOT)
    draw = ImageDraw.Draw(img)
    gradient_bg(draw)
    title_font = load_font(52, bold=True)
    label_font = load_font(36, bold=True)
    draw.text((80, 180), "Wat kun je met NORI?", font=title_font, fill=INK)

    features = [
        ("contacts", "Contacten", "Mensen die jij vertrouwt", TEAL, 0),
        ("messages", "Berichten", "Samen in één chat", ACCENT, 1),
        ("alarm", "ALARM", "Bij nood, één druk", RED, 2),
    ]
    active = seg.get("feature")
    for key, title, sub, color, i in features:
        y = 360 + i * 320
        delay = i * 0.35
        p = ease_out(max(0.0, min(1.0, (t_local - delay) / 0.55)))
        x = int(lerp(-80, 70, p))
        alpha = int(255 * p)
        card = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        cd = ImageDraw.Draw(card)
        highlight = active == key
        fill = (*WHITE, 245) if not highlight else (*color, 28)
        outline = color if highlight else (226, 232, 240)
        cd.rounded_rectangle([x, y, x + 940, y + 250], radius=36, fill=fill if highlight else (*WHITE, 250), outline=outline, width=5 if highlight else 3)
        # icon circle
        cx, cy = x + 120, y + 125
        cd.ellipse([cx - 55, cy - 55, cx + 55, cy + 55], fill=color)
        if key == "contacts":
            cd.ellipse([cx - 16, cy - 28, cx + 16, cy - 2], fill=WHITE)
            cd.pieslice([cx - 34, cy - 4, cx + 34, cy + 42], 0, 180, fill=WHITE)
        elif key == "messages":
            cd.rounded_rectangle([cx - 30, cy - 22, cx + 30, cy + 18], radius=12, fill=WHITE)
            cd.polygon([(cx - 10, cy + 18), (cx + 4, cy + 18), (cx - 8, cy + 34)], fill=WHITE)
        else:
            cd.ellipse([cx - 28, cy - 28, cx + 28, cy + 28], outline=WHITE, width=6)
            cd.ellipse([cx - 8, cy - 8, cx + 8, cy + 8], fill=WHITE)
        cd.text((x + 220, y + 70), title, font=label_font, fill=INK if not highlight else color)
        cd.text((x + 220, y + 130), sub, font=load_font(30), fill=MUTED)
        img = Image.alpha_composite(img.convert("RGBA"), card).convert("RGB")
        draw = ImageDraw.Draw(img)
    return img


def scene_example(t_local, seg, total_in_scene):
    img = Image.new("RGB", (W, H), BG_BOT)
    draw = ImageDraw.Draw(img)
    gradient_bg(draw)
    title_font = load_font(48, bold=True)
    draw.text((80, 160), "Een herkenbaar voorbeeld", font=title_font, fill=INK)

    step = seg.get("step", 0)

    def phone_screen(d, x, y, w, h):
        # header
        d.rectangle([x, y, x + w, y + 70], fill=TEAL)
        nf = load_font(26, bold=True)
        d.text((x + 24, y + 20), "NORI", font=nf, fill=WHITE)
        # alarm button
        cx, cy = x + w // 2, y + h // 2 + 20
        r = 78
        col = RED if step >= 1 else (248, 113, 113)
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=col)
        af = load_font(28, bold=True)
        tw, th = text_size(d, "ALARM", af)
        d.text((cx - tw / 2, cy - th / 2), "ALARM", font=af, fill=WHITE)
        if step == 2:
            d.text((x + 36, y + h - 110), "4… 3… 2… 1", font=load_font(28, bold=True), fill=AMBER)
        if step >= 3:
            d.rounded_rectangle([x + 20, y + 90, x + w - 20, y + 170], radius=16, fill=RED_SOFT)
            d.text((x + 36, y + 112), "Verzonden ✓", font=load_font(26, bold=True), fill=RED)

    draw_phone(draw, 340, 980, 1.15, phone_screen)

    # right side contact phone receiving notification
    p = ease_out(min(1.0, max(0.0, (t_local - 0.4) / 0.8))) if step >= 3 else 0.15
    rx = int(lerp(1300, 780, p if step >= 3 else 0))
    draw_phone(draw, rx, 980, 0.95)

    if step >= 3 and p > 0.3:
        # notification card
        nx, ny = rx - 150, 620
        rounded_rect(draw, [nx, ny, nx + 300, ny + 150], 24, WHITE, TEAL, 3)
        draw.text((nx + 24, ny + 28), "Noodmelding", font=load_font(28, bold=True), fill=RED)
        draw.text((nx + 24, ny + 78), "Iemand heeft\nALARM ingedrukt", font=load_font(24), fill=MUTED)
        # arrow
        draw.line([(460, 900), (rx - 120, 900)], fill=TEAL, width=6)
        draw.polygon([(rx - 120, 880), (rx - 120, 920), (rx - 90, 900)], fill=TEAL)

    if step == 0:
        draw_person(draw, W // 2, 560, 1.2, shirt=(251, 146, 60))
        draw.text((W // 2 - 180, 720), "Niet zo lekker…", font=load_font(34), fill=MUTED)

    return img


def scene_contacts(t_local, seg, total_in_scene):
    img = Image.new("RGB", (W, H), BG_BOT)
    draw = ImageDraw.Draw(img)
    gradient_bg(draw)
    title_font = load_font(52, bold=True)
    draw.text((80, 180), "Contacten", font=title_font, fill=INK)
    sub = load_font(34)
    draw.text((80, 260), "Mensen die jij hebt gekozen", font=sub, fill=MUTED)

    names = [("Anna", TEAL_SOFT), ("Omar", (96, 165, 250)), ("Lisa", (251, 146, 60))]
    for i, (name, color) in enumerate(names):
        p = ease_out(max(0.0, min(1.0, (t_local - i * 0.35) / 0.55)))
        y = 420 + i * 220
        x = int(lerp(-100, 80, p))
        rounded_rect(draw, [x, y, x + 920, y + 180], 32, WHITE, (226, 232, 240), 3)
        draw.ellipse([x + 40, y + 40, x + 140, y + 140], fill=color)
        initials = name[0]
        ifont = load_font(44, bold=True)
        tw, th = text_size(draw, initials, ifont)
        draw.text((x + 90 - tw / 2, y + 90 - th / 2), initials, font=ifont, fill=WHITE)
        draw.text((x + 180, y + 55), name, font=load_font(40, bold=True), fill=INK)
        status = "Geaccepteerd ✓" if t_local > 1.4 or i == 0 else "Wacht op acceptatie…"
        sc = GREEN if "✓" in status else AMBER
        draw.text((x + 180, y + 110), status, font=load_font(28), fill=sc)

    # flow caption near bottom of illustration area
    if t_local > 1.6:
        flow_font = load_font(36, bold=True)
        draw_centered_lines(draw, ["Zoeken → Toevoegen → Accepteren"], 1180, flow_font, TEAL)
    return img


def scene_alarm(t_local, seg, total_in_scene):
    img = Image.new("RGB", (W, H), BG_BOT)
    draw = ImageDraw.Draw(img)
    gradient_bg(draw)
    title_font = load_font(52, bold=True)
    draw.text((80, 160), "ALARM", font=title_font, fill=RED)
    draw.text((80, 240), "Voor als je echt hulp nodig hebt", font=load_font(34), fill=MUTED)

    # big calm alarm button
    pulse = 0.5 + 0.5 * math.sin(t_local * 2.2)
    r = int(170 + 10 * pulse)
    cx, cy = W // 2, 700
    for ring in (1.45, 1.25, 1.0):
        rr = int(r * ring)
        draw.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], outline=mix(WHITE, RED, 0.35 if ring > 1 else 1), width=8 if ring == 1 else 4)
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=RED)
    af = load_font(48, bold=True)
    tw, th = text_size(draw, "ALARM", af)
    draw.text((cx - tw / 2, cy - th / 2), "ALARM", font=af, fill=WHITE)

    # outcomes
    cards = [
        ("🔔", "Noodcontacten\nkrijgen melding", 0.4),
        ("📍", "Jouw locatie\ngaat mee", 0.7),
        ("🩺", "Reddingskaart\nop jouw telefoon", 1.0),
    ]
    for i, (icon, label, delay) in enumerate(cards):
        p = ease_out(max(0.0, min(1.0, (t_local - delay) / 0.5)))
        x = 70 + i * 330
        y = int(lerp(1400, 1080, p))
        rounded_rect(draw, [x, y, x + 300, y + 280], 28, WHITE, (226, 232, 240), 3)
        draw.text((x + 110, y + 36), icon, font=load_font(52), fill=INK)
        lf = load_font(28, bold=True)
        for j, line in enumerate(label.split("\n")):
            tw, _ = text_size(draw, line, lf)
            draw.text((x + (300 - tw) / 2, y + 130 + j * 40), line, font=lf, fill=INK)
    return img


def scene_outro(t_local, seg, total_in_scene):
    img = Image.new("RGB", (W, H), BG_BOT)
    draw = ImageDraw.Draw(img)
    gradient_bg(draw)
    img = draw_soft_circle(img, (W // 2, 620), 400, TEAL, 40)
    draw = ImageDraw.Draw(img)
    appear = ease_out(min(1.0, t_local / 0.55))
    draw_nori_mark(draw, W // 2, int(lerp(700, 560, appear)), scale=2.4)
    title_font = load_font(68, bold=True)
    tw, _ = text_size(draw, "NORI", title_font)
    draw.text(((W - tw) / 2, 760), "NORI", font=title_font, fill=TEAL)
    if t_local > 1.0:
        msg_font = load_font(40, bold=True)
        lines = wrap_text(draw, "Je bent klaar om NORI te gebruiken", msg_font, W - 160)
        draw_centered_lines(draw, lines, 920, msg_font, INK)
    # people connected
    if t_local > 1.4:
        p = ease_out(min(1.0, (t_local - 1.4) / 0.6))
        draw_person(draw, 280, int(lerp(1500, 1280, p)), 1.0, shirt=TEAL_SOFT)
        draw_person(draw, 540, int(lerp(1500, 1320, p)), 1.0, shirt=(96, 165, 250))
        draw_person(draw, 800, int(lerp(1500, 1280, p)), 1.0, shirt=(251, 146, 60))
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
    communicate = edge_tts.Communicate(seg["text"], VOICE, rate="-8%", pitch="+0Hz")
    await communicate.save(str(out_path))


def audio_duration(path: Path) -> float:
    # use ffprobe for mp3
    r = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "default=nk=1:nw=1", str(path)],
        capture_output=True, text=True, check=True,
    )
    return float(r.stdout.strip())


async def build_voice(segments):
    timeline = []
    t = 0.35  # lead-in
    for seg in segments:
        mp3 = AUDIO / f"{seg['id']}.mp3"
        await synthesize_segment(seg, mp3)
        dur = audio_duration(mp3)
        timeline.append({**seg, "start": t, "duration": dur, "path": mp3})
        t += dur + float(seg.get("pauseAfter", 0.3))
    total = t + 0.4
    return timeline, total


def write_concat_audio(timeline, total, out_wav_mp3: Path):
    # Build one voice track with silence using ffmpeg aevalsrc + concat
    parts = []
    filter_parts = []
    inputs = ["-f", "lavfi", "-t", "0.35", "-i", "anullsrc=r=24000:cl=mono"]
    idx = 1
    for seg in timeline:
        inputs += ["-i", str(seg["path"])]
        silence = float(seg.get("pauseAfter", 0.3))
        inputs += ["-f", "lavfi", "-t", str(silence), "-i", f"anullsrc=r=24000:cl=mono"]
        # voice then silence
        filter_parts.append(f"[{idx}:a]")
        filter_parts.append(f"[{idx+1}:a]")
        idx += 2
    # trailing silence
    inputs += ["-f", "lavfi", "-t", "0.4", "-i", "anullsrc=r=24000:cl=mono"]
    n = 1 + len(timeline) * 2 + 1  # lead + pairs + trail
    # Actually recount: lead(0) + for each (voice, silence) + trail
    # indices: 0=lead, then for each seg: voice, silence, then trail
    concat_labels = ["[0:a]"]
    i = 1
    for _ in timeline:
        concat_labels.append(f"[{i}:a]")
        concat_labels.append(f"[{i+1}:a]")
        i += 2
    concat_labels.append(f"[{i}:a]")
    filter = "".join(concat_labels) + f"concat=n={len(concat_labels)}:v=0:a=1[outa]"
    cmd = ["ffmpeg", "-y", *inputs, "-filter_complex", filter, "-map", "[outa]", "-ac", "1", "-ar", "24000", str(out_wav_mp3)]
    subprocess.run(cmd, check=True, capture_output=True)


def make_music(duration: float, path: Path):
    # Soft ambient pad: gentle sine chords, low volume
    # Use ffmpeg sine generators mixed
    cmd = [
        "ffmpeg", "-y",
        "-f", "lavfi", "-i", f"sine=frequency=196:duration={duration}",
        "-f", "lavfi", "-i", f"sine=frequency=246.94:duration={duration}",
        "-f", "lavfi", "-i", f"sine=frequency=293.66:duration={duration}",
        "-f", "lavfi", "-i", f"sine=frequency=392:duration={duration}",
        "-filter_complex",
        "[0:a]volume=0.03[a0];[1:a]volume=0.025[a1];[2:a]volume=0.02[a2];[3:a]volume=0.015,tremolo=f=0.12:d=0.4[a3];"
        "[a0][a1][a2][a3]amix=inputs=4:duration=longest,lowpass=f=1200,volume=0.55[out]",
        "-map", "[out]", "-ac", "2", "-ar", "44100", str(path),
    ]
    subprocess.run(cmd, check=True, capture_output=True)


def make_confirm_sfx(path: Path):
    cmd = [
        "ffmpeg", "-y",
        "-f", "lavfi", "-i", "sine=frequency=880:duration=0.12",
        "-f", "lavfi", "-i", "sine=frequency=1174.66:duration=0.16",
        "-filter_complex", "[0:a][1:a]acrossfade=d=0.05,volume=0.18[out]",
        "-map", "[out]", str(path),
    ]
    subprocess.run(cmd, check=True, capture_output=True)


def render_frames(timeline, total):
    # Precompute scene local times
    scene_starts = {}
    for seg in timeline:
        scene_starts.setdefault(seg["scene"], seg["start"])

    n_frames = int(math.ceil(total * FPS))
    font_cap = load_font(42, bold=True)

    for fi in range(n_frames):
        t = fi / FPS
        # find active segment
        active = timeline[0]
        for seg in timeline:
            if seg["start"] <= t < seg["start"] + seg["duration"] + float(seg.get("pauseAfter", 0.3)):
                active = seg
                break
            if t >= seg["start"]:
                active = seg

        scene = active["scene"]
        t_local = t - scene_starts[scene]
        renderer = SCENES[scene]
        img = renderer(t_local, active, 0)

        # overlay on-screen caption text (large)
        caption = active.get("onScreen") or ""
        draw = ImageDraw.Draw(img)
        # translucent caption plate
        lines = wrap_text(draw, caption, font_cap, W - 160)
        heights = [text_size(draw, ln, font_cap)[1] for ln in lines]
        block_h = sum(heights) + 10 * max(0, len(lines) - 1) + 40
        y0 = H - 260 - block_h
        overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        od = ImageDraw.Draw(overlay)
        od.rounded_rectangle([48, y0, W - 48, y0 + block_h], radius=28, fill=(17, 24, 39, 205))
        img = Image.alpha_composite(img.convert("RGBA"), overlay)
        draw = ImageDraw.Draw(img)
        y = y0 + 20
        for line in lines:
            tw, th = text_size(draw, line, font_cap)
            draw.text(((W - tw) / 2, y), line, font=font_cap, fill=WHITE)
            y += th + 10

        # burn-in subtitle (same as VO, slightly smaller) for accessibility without relying only on VTT
        # Keep short: use onScreen already as primary visual text.

        out = FRAMES / f"frame_{fi:05d}.png"
        img.convert("RGB").save(out, optimize=True)
        if fi % 24 == 0:
            print(f"  frame {fi}/{n_frames} ({100*fi/n_frames:.0f}%)")

    return n_frames


def write_vtt(timeline, path: Path):
    def ts(sec: float) -> str:
        h = int(sec // 3600)
        m = int((sec % 3600) // 60)
        s = sec % 60
        return f"{h:02d}:{m:02d}:{s:06.3f}".replace(".", ",")

    # WebVTT uses . as decimal
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


def mux(n_frames, voice_path, music_path, sfx_path, timeline, out_mp4: Path):
    # Place soft confirm sfx at end of alarm-send moment (s3c start)
    sfx_at = next((s["start"] for s in timeline if s["id"] == "s3c"), 20.0)
    cmd = [
        "ffmpeg", "-y",
        "-framerate", str(FPS),
        "-i", str(FRAMES / "frame_%05d.png"),
        "-i", str(voice_path),
        "-i", str(music_path),
        "-i", str(sfx_path),
        "-filter_complex",
        f"[1:a]volume=1.0[vo];"
        f"[2:a]volume=0.22[bg];"
        f"[3:a]adelay={int(sfx_at*1000)}|{int(sfx_at*1000)},volume=0.35[sfx];"
        f"[vo][bg][sfx]amix=inputs=3:duration=first:dropout_transition=2[aout]",
        "-map", "0:v",
        "-map", "[aout]",
        "-c:v", "libx264",
        "-pix_fmt", "yuv420p",
        "-profile:v", "main",
        "-crf", "24",
        "-preset", "medium",
        "-movflags", "+faststart",
        "-c:a", "aac",
        "-b:a", "128k",
        "-shortest",
        str(out_mp4),
    ]
    subprocess.run(cmd, check=True)


def make_poster(timeline, path: Path):
    # render first welcome frame-like poster
    img = scene_welcome(1.8, timeline[0], 0)
    draw = ImageDraw.Draw(img)
    font = load_font(52, bold=True)
    overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    od.rounded_rectangle([80, H // 2 + 80, W - 80, H // 2 + 280], radius=32, fill=(17, 24, 39, 200))
    img = Image.alpha_composite(img.convert("RGBA"), overlay)
    draw = ImageDraw.Draw(img)
    lines = ["Bekijk hoe NORI werkt", "Tik op afspelen"]
    y = H // 2 + 120
    for line in lines:
        tw, th = text_size(draw, line, font)
        draw.text(((W - tw) / 2, y), line, font=font, fill=WHITE)
        y += th + 16
    # play affordance
    cx, cy = W // 2, H // 2 - 40
    draw.ellipse([cx - 70, cy - 70, cx + 70, cy + 70], fill=(*TEAL, ) if False else TEAL)
    draw.polygon([(cx - 22, cy - 34), (cx - 22, cy + 34), (cx + 40, cy)], fill=WHITE)
    img.convert("RGB").resize((540, 960), Image.Resampling.LANCZOS).save(path, quality=85, optimize=True)


async def main():
    ensure_dirs()
    data = json.loads(SCRIPT.read_text(encoding="utf-8"))
    segments = data["segments"]
    print("Synthesizing voice-over…")
    timeline, total = await build_voice(segments)
    print(f"Total duration ≈ {total:.1f}s")

    voice_path = AUDIO / "voice.mp3"
    print("Concatenating voice…")
    write_concat_audio(timeline, total, voice_path)

    music_path = AUDIO / "music.mp3"
    print("Generating soft music…")
    make_music(total + 0.5, music_path)

    sfx_path = AUDIO / "confirm.mp3"
    make_confirm_sfx(sfx_path)

    print("Rendering frames…")
    n_frames = render_frames(timeline, total)

    out_mp4 = OUT_DIR / "nori-uitleg.mp4"
    print("Muxing video…")
    mux(n_frames, voice_path, music_path, sfx_path, timeline, out_mp4)

    vtt_path = OUT_DIR / "nori-uitleg.nl.vtt"
    write_vtt(timeline, vtt_path)

    poster_path = OUT_DIR / "nori-uitleg-poster.jpg"
    make_poster(timeline, poster_path)

    # also export a smaller mobile-friendly version
    small = OUT_DIR / "nori-uitleg-720.mp4"
    subprocess.run([
        "ffmpeg", "-y", "-i", str(out_mp4),
        "-vf", "scale=720:-2",
        "-c:v", "libx264", "-crf", "26", "-preset", "medium",
        "-c:a", "aac", "-b:a", "96k", "-movflags", "+faststart",
        str(small),
    ], check=True)

    size_mb = out_mp4.stat().st_size / (1024 * 1024)
    size_s = small.stat().st_size / (1024 * 1024)
    print(f"Done. {out_mp4} ({size_mb:.1f} MB), {small} ({size_s:.1f} MB), {vtt_path}, {poster_path}")
    print(f"Duration {total:.1f}s, frames {n_frames}")


if __name__ == "__main__":
    asyncio.run(main())

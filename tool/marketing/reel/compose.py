"""Composite live screen-recording footage into the reel's white page style.
usage: compose.py <segment-name> [--test T]"""
import sys, subprocess, numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

W, H, FPS = 1080, 1920, 30
DESK = "/Users/macmini/Desktop/"
SEGS = {
  "A": dict(src=DESK+"Screen Recording 2026-09-27 at 17.46.48.mov", ss=2.7, dur=8.3,
            crop=(0, 250, 560, 850), tag="7 tools", line="Every AI tool you use, one hover away."),
  "B": dict(src=DESK+"Screen Recording 2026-09-27 at 17.47.45.mov", ss=0.5, dur=6.2,
            crop=(1360, 0, 720, 680), tag="Top edge", line="Or dock it up top. Same rings, same cards."),
}
CARD_W, RADIUS = 960, 36
BAR_X, BAR_Y, BAR_W, BAR_H = 90, 1596, 900, 96
BLUE, INK = (44, 107, 242), (10, 10, 11)

def font(size, weight):
    f = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", size)
    try: f.set_variation_by_name(weight)
    except Exception: pass
    return f

def rounded_mask(w, h, r):
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, w-1, h-1], r, fill=255)
    return m

def shadow(w, h, r, blur, alpha, dy):
    pad = blur * 3
    s = Image.new("L", (w + pad*2, h + pad*2), 0)
    ImageDraw.Draw(s).rounded_rectangle([pad, pad+dy, pad+w, pad+h+dy], r, fill=int(255*alpha))
    return s.filter(ImageFilter.GaussianBlur(blur)), pad

def ease(x):  # ease-out cubic
    x = max(0.0, min(1.0, x)); return 1 - (1 - x) ** 3

def build(name, test=None):
    s = SEGS[name]; cx, cy, cw, ch = s["crop"]
    card_h = round(ch * CARD_W / cw / 2) * 2
    card_x, card_y = (W - CARD_W)//2, (BAR_Y - 36 - card_h)//2

    # --- static layers -------------------------------------------------------
    base = Image.new("RGB", (W, H), "white")
    sh, pad = shadow(CARD_W, card_h, RADIUS, 34, 0.22, 22)
    base.paste((12, 16, 28), (card_x - pad, card_y - pad), sh)
    cmask = rounded_mask(CARD_W, card_h, RADIUS)

    ftag, fline = font(24, "Semibold"), font(28, "Medium")
    tw = int(ftag.getlength(s["tag"])); tag_w = tw + 40
    bar = Image.new("RGBA", (BAR_W + 120, BAR_H + 120), (0, 0, 0, 0))
    bsh, bpad = shadow(BAR_W, BAR_H, 48, 16, 0.16, 8)
    bar.paste((13, 18, 31, 255), (60 - bpad, 60 - bpad), bsh)
    d = ImageDraw.Draw(bar)
    d.rounded_rectangle([60, 60, 60 + BAR_W, 60 + BAR_H], 48, fill=(255, 255, 255, 255))
    d.rounded_rectangle([60 + 24, 60 + 22, 60 + 24 + tag_w, 60 + 74], 26, fill=BLUE + (255,))
    d.text((60 + 24 + 20, 60 + 48), s["tag"], font=ftag, fill="white", anchor="lm")
    line_x = 60 + 24 + tag_w + 22
    # every prefix of the line, pre-rendered, for the typewriter
    prefixes = []
    for n in range(len(s["line"]) + 1):
        im = Image.new("RGBA", bar.size, (0, 0, 0, 0))
        ImageDraw.Draw(im).text((line_x, 60 + 48), s["line"][:n], font=fline, fill=INK + (255,), anchor="lm")
        prefixes.append(im)

    # --- timing ----------------------------------------------------------------
    D = s["dur"]
    def card_alpha(t):  return ease(t / 0.35) * (1 - ease((t - (D - 0.3)) / 0.3))
    def bar_alpha(t):   return ease((t - 0.25) / 0.4) * (1 - ease((t - (D - 0.3)) / 0.3))
    def bar_dy(t):      return int(34 * (1 - ease((t - 0.25) / 0.45)))
    def typed(t):       return int(len(s["line"]) * max(0, min(1, (t - 0.55) / 1.1)))

    # --- decode ------------------------------------------------------------------
    vf = f"fps={FPS},crop={cw}:{ch}:{cx}:{cy},scale={CARD_W}:{card_h}:flags=lanczos"
    dec = subprocess.Popen(["ffmpeg", "-v", "error", "-ss", str(s["ss"]), "-t", str(D), "-i", s["src"],
                            "-vf", vf, "-pix_fmt", "rgb24", "-f", "rawvideo", "-"], stdout=subprocess.PIPE)
    enc = None
    if test is None:
        enc = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24",
                                "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-", "-c:v", "libx264",
                                "-crf", "16", "-pix_fmt", "yuv420p", f"seg_{name}.mp4"], stdin=subprocess.PIPE)
    fsize = CARD_W * card_h * 3; i = 0
    while True:
        raw = dec.stdout.read(fsize)
        if len(raw) < fsize: break
        t = i / FPS
        if test is not None and abs(t - test) > 0.5 / FPS: i += 1; continue
        frame = base.copy()
        foot = Image.frombytes("RGB", (CARD_W, card_h), raw)
        a = card_alpha(t)
        frame.paste(foot, (card_x, card_y), cmask.point(lambda v: int(v * a)))
        ba = bar_alpha(t)
        if ba > 0:
            layer = Image.alpha_composite(bar, prefixes[typed(t)])
            if ba < 1:
                al = layer.getchannel("A").point(lambda v: int(v * ba)); layer.putalpha(al)
            frame.paste(layer, (BAR_X - 60, BAR_Y - 60 + bar_dy(t)), layer)
        if test is not None:
            frame.save(f"test_{name}.png"); print("saved", f"test_{name}.png", "card", card_x, card_y, CARD_W, card_h); break
        enc.stdin.write(frame.tobytes()); i += 1
    dec.stdout.close(); dec.wait()
    if enc: enc.stdin.close(); enc.wait(); print(f"seg_{name}.mp4", i, "frames")

if __name__ == "__main__":
    t = float(sys.argv[sys.argv.index("--test")+1]) if "--test" in sys.argv else None
    build(sys.argv[1], t)

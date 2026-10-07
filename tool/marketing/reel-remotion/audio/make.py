"""Sound design for the DevNotch reel — every cue is placed on the edit's own frames.
Writes sfx.wav, music.wav and mix.wav (48 kHz stereo). Numbers come from src/Reel.tsx."""
import numpy as np, wave

SR, FPS, DUR = 48000, 30, 1125 / 30
N = int(SR * DUR)
rng = np.random.default_rng(7)
T = lambda frame: frame / FPS                      # frame -> seconds

# ------------------------------------------------------------------ helpers
def env(n, a=0.002, d=0.1):                       # attack + exponential decay
    t = np.arange(n) / SR
    e = np.exp(-t / d); na = max(1, int(a * SR)); e[:na] *= np.linspace(0, 1, na); return e

def bandpass(x, lo, hi):
    X = np.fft.rfft(x); f = np.fft.rfftfreq(len(x), 1 / SR)
    X[(f < lo) | (f > hi)] = 0; return np.fft.irfft(X, len(x))

def sweep_noise(dur, f0, f1, width=0.9):
    """noise through a band that glides f0 -> f1 (overlap-add, 50 ms hops)"""
    n = int(dur * SR); out = np.zeros(n); hop = int(0.025 * SR); win = np.hanning(hop * 2)
    src = rng.standard_normal(n + hop * 2)
    for i, s in enumerate(range(0, n, hop)):
        c = f0 * (f1 / f0) ** (s / n)
        seg = bandpass(src[s:s + hop * 2] * win, c * (1 - width / 2), c * (1 + width))
        out[s:s + hop * 2][: len(seg[: n - s])] += seg[: n - s]
    return out / (np.abs(out).max() + 1e-9)

def reverb(x, secs=1.8, mix=0.25):
    ir = rng.standard_normal(int(secs * SR)) * np.exp(-np.arange(int(secs * SR)) / SR / (secs / 5))
    ir = bandpass(ir, 300, 9000); ir /= np.abs(ir).sum() ** 0.5 * 12
    L = 1 << int(np.ceil(np.log2(len(x) + len(ir))))
    wet = np.fft.irfft(np.fft.rfft(x, L) * np.fft.rfft(ir, L), L)[: len(x)]
    return x * (1 - mix) + wet * mix * 3

def place(bus, snd, at, gain=1.0, pan=0.0):
    i = int(at * SR)
    if i >= N or i + len(snd) <= 0: return
    s = snd[: max(0, N - i)] * gain
    bus[0, i:i + len(s)] += s * (1 - max(0, pan)); bus[1, i:i + len(s)] += s * (1 + min(0, pan))

def add(*parts):
    n = max(len(p) for _, p in parts); out = np.zeros(n)
    for g, p in parts: out[:len(p)] += g * p
    return out

# ------------------------------------------------------------------ the sounds
def tick(pitch=2600):
    n = int(0.03 * SR); t = np.arange(n) / SR
    return (np.sin(2 * np.pi * pitch * t) * env(n, 0.0005, 0.006)
            + 0.5 * np.sin(2 * np.pi * pitch * 0.35 * t) * env(n, 0.0005, 0.01)
            + 0.25 * rng.standard_normal(n) * env(n, 0.0002, 0.002))

def pop(pitch=520, dec=0.09):
    n = int(0.25 * SR); t = np.arange(n) / SR
    f = pitch * (1 + 1.2 * np.exp(-t / 0.015))
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * env(n, 0.001, dec)

def thump(f0=120, f1=48, dec=0.22):
    n = int(0.6 * SR); t = np.arange(n) / SR
    f = f1 + (f0 - f1) * np.exp(-t / 0.04)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * env(n, 0.002, dec) + 0.3 * bandpass(rng.standard_normal(n), 60, 900) * env(n, 0.001, 0.02)

def bell(freq, dec=1.1):
    n = int((dec * 4) * SR); t = np.arange(n) / SR
    return sum(a * np.sin(2 * np.pi * freq * r * t) * np.exp(-t / (dec / r ** 0.6))
               for r, a in ((1, 1), (2.76, 0.45), (5.4, 0.22), (8.93, 0.1))) * env(n, 0.001, 99)

def whoosh(dur=0.45, up=True, gain=1.0):
    s = sweep_noise(dur, 400 if up else 3000, 3200 if up else 350)
    shape = np.sin(np.linspace(0, np.pi, len(s))) ** (1.6 if up else 1.2)
    return s * shape * gain

def boom():
    return add((1.1, thump(90, 38, 0.7)), (0.35, whoosh(0.5, False)))

# ------------------------------------------------------------------ SFX timeline
sfx = np.zeros((2, N))
C = lambda x1, y1, x2, y2: (lambda u: _bez(u, x1, y1, x2, y2))
def _bez(u, x1, y1, x2, y2):
    lo, hi = 0.0, 1.0
    for _ in range(40):
        t = (lo + hi) / 2; x = 3 * (1 - t) ** 2 * t * x1 + 3 * (1 - t) * t ** 2 * x2 + t ** 3
        lo, hi = (t, hi) if x < u else (lo, t)
    t = (lo + hi) / 2; return 3 * (1 - t) ** 2 * t * y1 + 3 * (1 - t) * t ** 2 * y2 + t ** 3

# hero spin — Easing.bezier(0.16, 0.6, 0.12, 1) from frame 16 to 82 across 13 steps
ease = C(0.16, 0.6, 0.12, 1); S0, S1, NS = 16, 82, 13
fr = np.arange(S0, S1, 0.01); pos = np.array([ease((x - S0) / (S1 - S0)) * NS for x in fr])
speed = np.gradient(pos, fr)
for k in range(1, NS + 1):
    idx = np.argmax(pos >= k - 0.5)
    if pos[idx] >= k - 0.5:
        sp = speed[idx]; place(sfx, tick(2300 + 900 * min(1, sp)), T(fr[idx]), 0.55, pan=(-0.2 if k % 2 else 0.2))
wh = bandpass(rng.standard_normal(int(T(S1 - S0) * SR)), 900, 5200)
sp_env = np.interp(np.arange(len(wh)) / SR, (fr - S0) / FPS, np.clip(speed, 0, None))
place(sfx, wh * sp_env / (sp_env.max() + 1e-9) * 0.10, T(S0))
place(sfx, thump(150, 60, 0.18), T(S1), 0.9)                       # lands on "Notch."
place(sfx, reverb(np.pad(bell(1318.5, 0.9), (0, SR))), T(S1), 0.30)  # ding
place(sfx, whoosh(0.62, True), T(120) - 0.55, 0.55)                  # dive into the pill

# scene cuts: whoosh through every zoom-through, thump on each close-up snap
cuts = [192, 270, 341, 413, 488, 578, 674, 749, 845, 950]
for i, b in enumerate(cuts):
    place(sfx, whoosh(0.42, i % 2 == 0), T(b) - 0.26, 0.42, pan=(-0.3 if i % 2 else 0.3))
for b in (192, 270, 341, 674):
    place(sfx, thump(110, 55, 0.16), T(b + 3), 0.55)

# footage: rail pop, then a soft click as each card opens
place(sfx, pop(300, 0.12), 4.33, 0.5)
for t in (4.28, 6.04, 9.45, 10.0, 10.51, 16.37, 17.37, 18.37, 19.67, 21.27, 21.67, 22.07):
    place(sfx, tick(1700), t, 0.28)

# "Seven tools." — seven pops climbing a pentatonic
for i, st in enumerate((0, 3, 5, 7, 10, 12, 15)):
    place(sfx, pop(440 * 2 ** (st / 12), 0.1), T(413 + 8 + i * 4), 0.42, pan=(i - 3) * 0.12)

# menu bar — a tick on every label flip
for k in range(6):
    place(sfx, tick(2000 + 120 * k), T(749 + 16 + k * 11), 0.35)

# statements — each line lands with a soft whoomp
for b in (845, 880, 915):
    place(sfx, add((0.8, thump(90, 50, 0.25)), (0.2, whoosh(0.3, False))), T(b + 2), 0.55)

# ending
E = 950
place(sfx, reverb(np.pad(boom(), (0, SR)), 2.2, 0.3), T(E), 0.95)          # "One rail."
for i in range(7):
    place(sfx, pop(440 * 2 ** ((0, 3, 5, 7, 10, 12, 15)[i] / 12), 0.08), T(E + 20 + i * 4), 0.38, pan=0)
suck = whoosh(0.8, True)[::-1] * np.linspace(0.3, 1, int(0.8 * SR)) ** 2    # rail collapses
place(sfx, suck, T(E + 60), 0.45)
chord = sum(np.pad(bell(f, 1.6), (int(i * 0.045 * SR), 0))[: int(6.4 * SR)]
            for i, f in enumerate((523.3, 659.3, 784.0, 1046.5)))            # logo forms: C major shimmer
place(sfx, reverb(np.pad(chord, (0, SR)), 2.4, 0.35), T(E + 82), 0.30)
place(sfx, thump(80, 36, 0.5), T(E + 84), 0.75)
for i in range(8):                                                           # letters rise
    place(sfx, tick(3000 + 60 * i), T(E + 100 + i * 2.5), 0.12)
place(sfx, whoosh(0.35, True), T(E + 116), 0.22)                            # tagline wipe
place(sfx, pop(620, 0.1), T(E + 128), 0.45)                                  # button
sparkle = add(*[(1.0, np.pad(bell(2093 * 2 ** (st / 12), 0.35), (int(k * 0.03 * SR), 0))) for k, st in enumerate((0, 4, 7, 12))])
place(sfx, reverb(np.pad(sparkle, (0, SR)), 1.5, 0.4), T(E + 142), 0.12)       # sparkle on the shine

# ------------------------------------------------------------------ music: pop beat, locked to the edit
# 14 bars between the dive (4.0s) and "One rail." (31.67s) -> 121.45 BPM, both land on a downbeat
BAR = (T(950) - T(120)) / 14; BEAT = BAR / 4; S16 = BEAT / 4
bar_t = lambda k: T(120) + k * BAR
music = np.zeros((2, N))
def mn(m): return 440 * 2 ** ((m - 69) / 12)
PROG = [(57, 60, 64, 69), (53, 57, 60, 65), (48, 52, 55, 60), (55, 59, 62, 67)]      # Am F C G
ROOT = [45, 41, 48, 43]

def saw(f, n, harm=10, bright=3.0, phase=0.0):
    t = np.arange(n) / SR
    return sum(np.sin(2 * np.pi * f * h * t + phase * h) * np.exp(-h / bright) / h for h in range(1, harm + 1))

def kick():
    n = int(0.42 * SR); t = np.arange(n) / SR
    f = 46 + 110 * np.exp(-t / 0.035)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * env(n, 0.001, 0.2) + 0.25 * bandpass(rng.standard_normal(n), 1500, 6000) * env(n, 0.0003, 0.004)

def clap():
    n = int(0.35 * SR); x = np.zeros(n); nz = bandpass(rng.standard_normal(n), 900, 7000)
    for o in (0, 0.009, 0.018, 0.027):
        i = int(o * SR); x[i:] += nz[: n - i] * env(n - i, 0.0005, 0.01 if o < 0.027 else 0.11)
    body = np.sin(2 * np.pi * 190 * np.arange(n) / SR) * env(n, 0.001, 0.05) * 0.4
    return reverb(x + body, 0.9, 0.18)

def hat(open_=False):
    n = int((0.22 if open_ else 0.05) * SR)
    return bandpass(rng.standard_normal(n), 7000, 16000) * env(n, 0.0005, 0.07 if open_ else 0.012)

def crash():
    n = int(2.2 * SR); return bandpass(rng.standard_normal(n), 4500, 16000) * env(n, 0.002, 0.7)

def pluck(freqs, dec=0.22):
    n = int((dec * 3) * SR); out = np.zeros(n)
    for f in freqs:
        for det in (-0.08, 0.08):
            out += saw(f * 2 ** (det / 12), n, 10, 2.6) * env(n, 0.002, dec)
    return out / len(freqs)

def bass(f, dec=0.2):
    n = int(0.32 * SR); return saw(f, n, 6, 2.2) * env(n, 0.003, dec)

def lead(f, dec=0.28):
    n = int((dec * 3) * SR); t = np.arange(n) / SR
    vib = 1 + 0.004 * np.sin(2 * np.pi * 5.5 * t)
    return (saw(f, n, 7, 2.4) * 0.6 + np.sin(2 * np.pi * f * 2 * t * vib) * 0.25) * env(n, 0.004, dec)

KICK, CLAP, HAT, OHAT, CRASH = kick(), clap(), hat(), hat(True), crash()
# lead hook — 4 bars over Am F C G, (step in 16ths, midi)
HOOK = [[(0, 69), (4, 72), (8, 76), (12, 74), (14, 72)],
        [(0, 69), (6, 72), (10, 69)],
        [(0, 67), (4, 72), (8, 76), (12, 79), (14, 76)],
        [(0, 74), (4, 71), (8, 67)]]
STAB = [0, 3, 6, 8, 11, 14]                      # syncopated chord stabs (16th steps)

LOGO = T(950 + 84)
for k in range(-2, 16):                          # two intro bars before the dive
    t0 = bar_t(k)
    if t0 >= LOGO: break
    chord = PROG[k % 4]; root = ROOT[k % 4]
    build = (k == 13)
    for st in range(16):
        tt = t0 + st * S16
        if tt >= LOGO: break
        if st % 4 == 0 and not build: place(music, KICK, tt, 0.95)
        if st in (4, 12) and not build: place(music, CLAP, tt, 0.55)
        if not build:
            place(music, HAT, tt, 0.16 if st % 2 else 0.09, pan=0.3)
            if st % 4 == 2: place(music, OHAT, tt, 0.10, pan=-0.25)
        if st % 4 == 2 and not build: place(music, bass(mn(root - 12)), tt, 0.55)
        if st in STAB: place(music, pluck([mn(m) for m in chord]), tt, 0.24 if not build else 0.14, pan=(-0.15 if st % 2 else 0.15))
    if (4 <= k <= 12) or k >= 14:
        for st, m in HOOK[k % 4]:
            tt = t0 + st * S16
            if tt < LOGO: place(music, lead(mn(m)), tt, 0.20, pan=0.1)
    if build:                                    # snare roll: 8ths -> 16ths -> 32nds, rising
        hits = [i * 2 * S16 for i in range(4)] + [BEAT * 2 + i * S16 for i in range(4)] + [BEAT * 3 + i * S16 / 2 for i in range(8)]
        for j, h in enumerate(hits): place(music, CLAP, t0 + h, 0.18 + 0.4 * j / len(hits))

# sidechain pump keyed to the kick
tt_all = np.arange(N) / SR
ph = ((tt_all - bar_t(-2)) % BEAT)
pump = 1 - 0.45 * np.exp(-ph / 0.07)
music *= pump
for at in (T(120), T(950)): place(music, CRASH, at, 0.35)
# final chord on the logo: C major (G -> C resolves), rings out
fin = add(*[(1.0, pluck([mn(m) for m in (48, 52, 55, 60, 64)], 1.4))]) + 0
place(music, reverb(np.pad(fin, (0, SR)), 2.2, 0.3), LOGO, 0.55)
place(music, KICK, LOGO, 1.0); place(music, CRASH, LOGO, 0.4)
place(music, bass(mn(36), 1.0), LOGO, 0.6)
# muffled during the hero, opens at the dive
cut = int(T(120) * SR); fade = int(0.12 * SR)
muff = np.stack([bandpass(music[ch], 20, 650) for ch in range(2)]) * 0.9
w = np.clip((np.arange(N) - (cut - fade)) / fade, 0, 1)[None, :]
music = muff * (1 - w) + music * w
# riser into each drop
for at, ln in ((T(120), 1.6), (T(950), BAR)):
    r = sweep_noise(ln, 300, 7000); r *= np.linspace(0, 1, len(r)) ** 2.2
    place(music, r, at - ln, 0.25)
music[:, :int(0.3 * SR)] *= np.linspace(0, 1, int(0.3 * SR))
music[:, -int(1.5 * SR):] *= np.linspace(1, 0, int(1.5 * SR))
music = np.tanh(music * 1.4) / np.tanh(1.4)       # glue
print(f"pop beat: {240 / BAR:.2f} BPM, bar {BAR:.3f}s")

# ------------------------------------------------------------------ mix + write
def write(name, x):
    x = x / (np.abs(x).max() + 1e-9) * 0.89
    with wave.open(name, "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x.T * 32767).astype(np.int16).tobytes())
write("sfx.wav", sfx); write("music.wav", music)
mixed = sfx / (np.abs(sfx).max() + 1e-9) * 0.95 + music / (np.abs(music).max() + 1e-9) * 0.55
mixed = np.tanh(mixed * 1.2) / np.tanh(1.2)
write("mix.wav", mixed)
print(f"wrote sfx.wav, music.wav, mix.wav  ({DUR:.2f}s @ {SR} Hz)")

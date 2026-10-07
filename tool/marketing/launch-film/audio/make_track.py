"""An original pop beat for the DevNotch story film: 120 BPM, A minor (Am F C G).
Bars 1-3 sparse (the hook), drop on bar 4 ("Meet DevNotch."), groove to bar 12, calm from bar 13 (end card).
Writes audio/source/popbeat.wav, 17 bars (two spare to cut from)."""
import numpy as np, wave
SR, BPM, BARS = 48000, 120, 17
BEAT = 60 / BPM; BAR = BEAT * 4; S16 = BEAT / 4
N = int(BARS * BAR * SR); rng = np.random.default_rng(11)
out = np.zeros((2, N))
def env(n, a=0.002, d=0.1):
    t = np.arange(n) / SR; e = np.exp(-t / d); na = max(1, int(a * SR)); e[:na] *= np.linspace(0, 1, na); return e
def bandpass(x, lo, hi):
    X = np.fft.rfft(x); f = np.fft.rfftfreq(len(x), 1 / SR); X[(f < lo) | (f > hi)] = 0; return np.fft.irfft(X, len(x))
def place(snd, at, g=1.0, pan=0.0):
    i = int(round(at * SR)); s = snd[: max(0, N - i)] * g
    out[0, i:i + len(s)] += s * (1 - max(0, pan)); out[1, i:i + len(s)] += s * (1 + min(0, pan))
def saw(f, n, harm=10, bright=3.0):
    t = np.arange(n) / SR; return sum(np.sin(2 * np.pi * f * h * t + h) * np.exp(-h / bright) / h for h in range(1, harm + 1))
def mn(m): return 440 * 2 ** ((m - 69) / 12)
def kick():
    n = int(0.42 * SR); t = np.arange(n) / SR; f = 46 + 110 * np.exp(-t / 0.035)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * env(n, 0.001, 0.2) + 0.25 * bandpass(rng.standard_normal(n), 1500, 6000) * env(n, 0.0003, 0.004)
def clap():
    n = int(0.3 * SR); x = np.zeros(n); nz = bandpass(rng.standard_normal(n), 900, 7000)
    for o in (0, 0.009, 0.018, 0.027):
        i = int(o * SR); x[i:] += nz[: n - i] * env(n - i, 0.0005, 0.01 if o < 0.027 else 0.1)
    return x + np.sin(2 * np.pi * 190 * np.arange(n) / SR) * env(n, 0.001, 0.05) * 0.4
def hat(o=False):
    n = int((0.2 if o else 0.05) * SR); return bandpass(rng.standard_normal(n), 7000, 16000) * env(n, 0.0005, 0.06 if o else 0.012)
def pluck(fs, dec=0.22):
    n = int(dec * 3 * SR); return sum(saw(f * 2 ** (d / 12), n, 10, 2.6) * env(n, 0.002, dec) for f in fs for d in (-0.08, 0.08)) / len(fs)
def pad(fs, secs):
    n = int(secs * SR); t = np.arange(n) / SR; sh = np.minimum(1, t / 0.3) * np.minimum(1, (secs - t) / 0.4)
    return sum(saw(f * 2 ** (d / 12), n, 6, 1.8) for f in fs for d in (-0.1, 0, 0.1)) * sh / (len(fs) * 3)
def bass(f, dec=0.2): n = int(0.32 * SR); return saw(f, n, 6, 2.2) * env(n, 0.003, dec)
def lead(f, dec=0.26): n = int(dec * 3 * SR); return saw(f, n, 7, 2.4) * env(n, 0.004, dec)
def crash(): n = int(2.2 * SR); return bandpass(rng.standard_normal(n), 4500, 16000) * env(n, 0.002, 0.7)
PROG = [(57, 60, 64, 69), (53, 57, 60, 65), (48, 52, 55, 60), (55, 59, 62, 67)]; ROOT = [45, 41, 48, 43]
HOOK = [[(0, 76), (4, 74), (8, 72), (12, 69)], [(0, 72), (6, 69), (10, 72)], [(0, 67), (4, 72), (8, 76), (12, 79)], [(0, 74), (8, 71)]]
STAB = [0, 3, 6, 8, 11, 14]
K, C, H, OH, CR = kick(), clap(), hat(), hat(True), crash()
for b in range(BARS):
    t0 = b * BAR; bar = b + 1; ch = PROG[b % 4]; rt = ROOT[b % 4]
    hook, groove, calm = bar <= 3, 4 <= bar <= 12, bar >= 13
    if hook or calm:
        place(pad([mn(m) for m in ch], BAR + 0.3), t0, 0.5 if hook else 0.42)
    for st in range(16):
        tt = t0 + st * S16
        if groove:
            if st % 4 == 0: place(K, tt, 0.95)
            if st in (4, 12): place(C, tt, 0.5)
            place(H, tt, 0.15 if st % 2 else 0.08, 0.3)
            if st % 4 == 2: place(OH, tt, 0.09, -0.25); place(bass(mn(rt - 12)), tt, 0.55)
            if st in STAB: place(pluck([mn(m) for m in ch]), tt, 0.22, -0.15 if st % 2 else 0.15)
        elif hook:
            if st % 2 == 1: place(H, tt, 0.05, 0.3)
            if bar == 3 and st >= 8 and st % 2 == 0: place(C, tt, 0.08 + 0.05 * (st - 8))   # a small build into the drop
    if 8 <= bar <= 12:
        for st, m in HOOK[b % 4]: place(lead(mn(m)), t0 + st * S16, 0.18, 0.1)
place(CR, 3 * BAR, 0.35)                              # the drop, bar 4
r_n = int(BAR * SR); r = bandpass(rng.standard_normal(r_n), 800, 9000) * np.linspace(0, 1, r_n) ** 2.4
place(r, 2 * BAR, 0.18)                               # riser across bar 3
res = pad([mn(m) for m in (48, 52, 55, 60, 64)], 2.5 * BAR); place(res, 12 * BAR, 0.5)   # the end card resolves on C
ph = (np.arange(N) / SR) % BEAT; pump = 1 - 0.4 * np.exp(-ph / 0.07)
gm = np.zeros(N); gm[int(3 * BAR * SR):int(12 * BAR * SR)] = 1
out *= (1 - gm * (1 - pump))[None, :]
hook_end = int(3 * BAR * SR)
for c in range(2): out[c, :hook_end] = bandpass(out[c, :hook_end], 20, 2500)
out = np.tanh(out * 1.3) / np.tanh(1.3); out *= 0.9 / np.abs(out).max()
with wave.open("audio/source/popbeat.wav", "wb") as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes((out.T * 32767).astype(np.int16).tobytes())
print(f"popbeat.wav: {BARS} bars at {BPM} BPM, {N / SR:.2f}s")

# DevNotch — launch film

A 30-second story film (1920 × 1080, 60 fps) made with [motion-designer](https://github.com/kaventro/motion-designer).
Style: **Midnight**, dressed in DevNotch's teal. The accent means *now*. Every frame is a pure function of time.

## Beat map (120 BPM, 60 beats, 15 bars)

| Beat | Time | What happens |
|---|---|---|
| 1 | 0.15 s | "They promised *unlimited.*" A Claude ring appears and fills to 6%. |
| 5 | 2.0 s | "Then cut you off *mid-task.*" The ring burns to 100%; the usage-limit card slams in. |
| 9 | 4.0 s | "The numbers? *Scattered.*" Seven usage pages fly apart. |
| 13 | 6.0 s | **Drop.** "Meet *DevNotch.*" The rail drops from the top edge; the ring takes the first slot. |
| 17 | 8.0 s | "Every tool, *one rail.*" Seven rings draw their values. |
| 25 | 12.0 s | "Hover for the *details.*" Pointer to Claude, the card opens from the ring, bars fill, sessions land. |
| 33 | 16.0 s | "Every number, *sourced.*" API · Local · CLI, one card per beat. |
| 41 | 20.0 s | "Or keep it in the *menu bar.*" The label rolls Claude → Codex → Cursor → Copilot. |
| 49 | 24.0 s | End card. The ring lands in the logo's notch; wordmark, "Never cut off *mid-task.*", Download for macOS. |
| 58.5 | 28.75 s | Everything clears; the last frame equals the first. |

## Rebuild

```bash
SK=~/Developer/motion-designer/skills/motion-designer
python3 audio/make_track.py                                              # the original pop beat
python3 $SK/scripts/music_edit.py audio/source/popbeat.wav audio/grid.json --from-bar 1 --bars 15 --out audio/edit
node $SK/scripts/render.mjs cues src/index.html audio/cues.json
python3 $SK/scripts/sfx.py audio/cues.json --key "A minor" --music audio/edit.wav --music-gain 0.5 --out audio/mix
node $SK/scripts/check.mjs src/index.html
node $SK/scripts/render.mjs video src/index.html out/devnotch-launch.mp4 --audio audio/mix.m4a --scale 2 --deband
```

## Sources and rights
- Interface rebuilt from DevNotch's own code; glyphs from `Sources/Providers/GlyphOutline.swift`; logo from `assets/brand/`.
- Usage numbers, project names and times are invented.
- Music and sounds are original, synthesized for this film.

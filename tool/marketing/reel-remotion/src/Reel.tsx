import React from "react";
import {
  AbsoluteFill, Sequence, OffthreadVideo, Img, staticFile,
  useCurrentFrame, useVideoConfig, interpolate, interpolateColors, spring, Easing,
} from "remotion";
import GLYPHS from "./glyphs.json";
import { measureText } from "@remotion/layout-utils";

const TEAL = "#0d9488", LITE = "#5fdcc9", GLOW = "#14b8a6", INK = "#0A0A0B", MUTED = "rgba(10,10,11,.36)";
const OK = "#00E58A", WARN = "#D7FF2F", CRIT = "#FF5A1F";
const FONT = '-apple-system, "SF Pro Display", system-ui, sans-serif';
const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;
const G = GLYPHS as Record<string, string>;
const heat = (v: number) => (v >= 70 ? CRIT : v >= 45 ? WARN : OK);

/* ------------------------------------------------------------ timeline (30fps) */
// every cut lives here, so snapping to the music later is one table
const S = {
  hero:   { from: 0,    dur: 120 },
  reveal: { from: 120,  dur: 72 },
  claude: { from: 192,  dur: 78 },
  cursor: { from: 270,  dur: 71 },
  codex:  { from: 341,  dur: 72 },
  tools:  { from: 413,  dur: 75 },
  tour:   { from: 488,  dur: 90 },
  top:    { from: 578,  dur: 96 },
  drop:   { from: 674,  dur: 75 },
  menu:   { from: 749,  dur: 96 },
  words:  { from: 845,  dur: 105 },
  end:    { from: 950,  dur: 175 },
};
export const TOTAL = 1125;

/* ------------------------------------------------------------ primitives */
const Glyph: React.FC<{ name: string; size: number; color?: string; style?: React.CSSProperties }> = ({ name, size, color = "#fff", style }) =>
  name === "notch"
    ? <Img src={staticFile("menubar.svg")} style={{ width: size, height: size, filter: "invert(1)", ...style }} />
    : <svg viewBox="0 0 100 100" width={size} height={size} style={style}><path d={G[name]} fill={color} fillRule="evenodd" /></svg>;

const Ring: React.FC<{ size: number; value: number; progress: number; glyph: string; stroke?: number }> = ({ size, value, progress, glyph, stroke = 7 }) => {
  const r = 50 - stroke / 2 - 1, C = 2 * Math.PI * r;
  return (
    <div style={{ position: "relative", width: size, height: size }}>
      <svg viewBox="0 0 100 100" width={size} height={size} style={{ position: "absolute", inset: 0 }}>
        <circle cx="50" cy="50" r={r} fill="none" stroke="rgba(255,255,255,.14)" strokeWidth={stroke} />
        <circle cx="50" cy="50" r={r} fill="none" stroke={heat(value)} strokeWidth={stroke} strokeLinecap="round"
          strokeDasharray={C} strokeDashoffset={C * (1 - (value / 100) * progress)} transform="rotate(-90 50 50)" />
      </svg>
      <div style={{ position: "absolute", inset: 0, display: "grid", placeItems: "center" }}>
        <Glyph name={glyph} size={size * 0.42} />
      </div>
    </div>
  );
};

const GRAIN = `url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='220' height='220'><filter id='n'><feTurbulence type='fractalNoise' baseFrequency='.9' numOctaves='3'/></filter><rect width='220' height='220' filter='url(%23n)'/></svg>")`;

const Backdrop: React.FC = () => {
  const f = useCurrentFrame();
  const drift = Math.sin(f / 40) * 40;
  const warm = interpolateColors(f, [S.end.from + 20, S.end.from + 80], [TEAL, GLOW]);
  const cool = interpolateColors(f, [S.end.from + 20, S.end.from + 80], ["#93c5fd", "#99f6e4"]);
  return (
    <AbsoluteFill style={{ background: "#FFFFFF", overflow: "hidden" }}>
      <div style={{ position: "absolute", width: 1000, height: 1000, borderRadius: "50%", filter: "blur(140px)",
        background: warm, opacity: 0.14, left: -300 + drift, top: 760 - drift / 2 }} />
      <div style={{ position: "absolute", width: 760, height: 760, borderRadius: "50%", filter: "blur(140px)",
        background: cool, opacity: 0.18, right: -260 - drift, top: 260 + drift }} />
      <AbsoluteFill style={{ backgroundImage: GRAIN, opacity: 0.025 }} />
    </AbsoluteFill>
  );
};

const Scene: React.FC<{ dur: number; children: React.ReactNode; noOut?: boolean }> = ({ dur, children, noOut }) => {
  const f = useCurrentFrame();
  const inP = interpolate(f, [0, 10], [0, 1], { ...clamp, easing: Easing.out(Easing.cubic) });
  const outP = noOut ? 0 : interpolate(f, [dur - 8, dur], [0, 1], { ...clamp, easing: Easing.in(Easing.cubic) });
  return (
    <AbsoluteFill style={{ opacity: inP * (1 - outP), transform: `scale(${0.8 + 0.2 * inP + 0.45 * outP})`,
      filter: `blur(${16 * (1 - inP) + 20 * outP}px)` }}>{children}</AbsoluteFill>
  );
};

type Line = { text: string; color?: string };
const Kinetic: React.FC<{ lines: Line[]; top?: number; size?: number; delay?: number; center?: boolean }> = ({
  lines, top = 170, size = 112, delay = 0, center,
}) => {
  const f = useCurrentFrame(); const { fps } = useVideoConfig();
  let w = 0;
  return (
    <div style={{ position: "absolute", left: center ? 0 : 84, right: center ? 0 : undefined, top, textAlign: center ? "center" : "left",
      fontFamily: FONT, fontWeight: 800, fontSize: size, lineHeight: 1.02, letterSpacing: "-0.045em", color: INK }}>
      {lines.map((l, li) => (
        <div key={li} style={{ color: l.color ?? INK, whiteSpace: "nowrap" }}>
          {l.text.split(" ").map((word, wi) => {
            const p = spring({ frame: f - delay - (w++) * 3, fps, config: { damping: 18, stiffness: 170 } });
            return <span key={wi} style={{ display: "inline-block", marginRight: "0.24em", opacity: p,
              transform: `translateY(${(1 - p) * 60}px)`, filter: `blur(${(1 - p) * 10}px)` }}>{word}</span>;
          })}
        </div>
      ))}
    </div>
  );
};

const Caption: React.FC<{ tag: string; text: string; glyph?: string; delay?: number }> = ({ tag, text, glyph, delay = 10 }) => {
  const f = useCurrentFrame(); const { fps } = useVideoConfig();
  const p = spring({ frame: f - delay, fps, config: { damping: 200 } });
  const n = Math.round(interpolate(f, [delay + 4, delay + 4 + text.length * 0.9], [0, text.length], clamp));
  return (
    <div style={{ position: "absolute", left: 84, bottom: 150, display: "flex", alignItems: "center", gap: 18,
      padding: "14px 28px 14px 14px", borderRadius: 40, background: "#FFFFFF", boxShadow: "0 14px 44px rgba(10,20,30,.14)",
      border: "1px solid rgba(10,10,11,.06)", fontFamily: FONT, fontSize: 30, fontWeight: 500, color: INK,
      opacity: p, transform: `translateY(${(1 - p) * 30}px)` }}>
      <span style={{ display: "flex", alignItems: "center", gap: 10, background: TEAL, borderRadius: 26,
        padding: "10px 22px 10px 16px", fontSize: 26, fontWeight: 650 }}>
        {glyph && <Glyph name={glyph} size={26} />}{tag}
      </span>
      <span style={{ whiteSpace: "nowrap" }}>{text.slice(0, n)}<span style={{ opacity: 0 }}>{text.slice(n)}</span></span>
    </div>
  );
};

/* ------------------------------------------------------------ footage */
const Display3D: React.FC<{
  src: string; rate: number; dur: number; aspect: number;
  rotY: [number, number]; rotX: [number, number]; origin: string; width: number; left: number; top: number;
  zoom?: [number, number]; zoomAt?: string; zoomStart?: number;
}> = ({ src, rate, dur, aspect, rotY, rotX, origin, width, left, top, zoom = [1, 1.07], zoomAt = "50% 60%", zoomStart = 0 }) => {
  const f = useCurrentFrame(); const { fps } = useVideoConfig();
  const swing = spring({ frame: f, fps, config: { damping: 20, stiffness: 90 } });
  const push = 1;
  const cam = interpolate(f, [zoomStart, dur], zoom, { ...clamp, easing: Easing.inOut(Easing.cubic) });
  return (
    <div style={{ position: "absolute", inset: 0, maskImage: "linear-gradient(to bottom, transparent 0, transparent 400px, #000 520px)",
      WebkitMaskImage: "linear-gradient(to bottom, transparent 0, transparent 400px, #000 520px)" }}>
    <div style={{ position: "absolute", inset: 0, perspective: 1900, transform: `scale(${cam})`, transformOrigin: zoomAt }}>
      <div style={{ position: "absolute", left, top, width, height: width / aspect, padding: 14, borderRadius: 30,
        background: "linear-gradient(145deg,#2c2c30,#0b0b0d)", transformOrigin: origin,
        transform: `rotateY(${interpolate(swing, [0, 1], rotY)}deg) rotateX(${interpolate(swing, [0, 1], rotX)}deg) scale(${push})`,
        boxShadow: `0 60px 120px rgba(10,20,30,.30), 0 0 0 1px rgba(10,10,11,.08), -30px 30px 120px ${GLOW}33` }}>
        <OffthreadVideo src={staticFile(src)} playbackRate={rate} muted
          style={{ width: "100%", height: "100%", objectFit: "cover", borderRadius: 18, display: "block" }} />
      </div>
    </div>
    </div>
  );
};

const Punch: React.FC<{ src: string; rate: number; dur: number; ghost: string; aspect?: number; tilt?: number }> = ({
  src, rate, dur, ghost, aspect = 1, tilt = -1,
}) => {
  const f = useCurrentFrame(); const { fps } = useVideoConfig();
  const p = spring({ frame: f, fps, config: { damping: 16, stiffness: 120 } });
  const ry = interpolate(f, [0, dur], [12 * tilt, 5 * tilt], clamp);
  const h = 900 / aspect;
  return (
    <>
      <div style={{ position: "absolute", right: -40 + interpolate(f, [0, dur], [80, -40], clamp), top: 120, fontFamily: FONT,
        fontSize: 520, fontWeight: 900, letterSpacing: "-0.06em", lineHeight: 1, color: `${TEAL}14` }}>{ghost}</div>
      <div style={{ position: "absolute", inset: 0, perspective: 1800 }}>
        <div style={{ position: "absolute", left: 90, top: 600 + (900 - h) / 2, width: 900, height: h, borderRadius: 40, overflow: "hidden",
          transform: `rotateY(${ry}deg) rotateX(6deg) scale(${(1.18 - 0.18 * p) * interpolate(f, [8, dur], [1, 1.07], clamp)})`,
          opacity: Math.min(1, p * 1.6),
          boxShadow: `0 50px 110px rgba(10,20,30,.30), 0 0 0 1px rgba(10,10,11,.06), 0 0 100px ${GLOW}40` }}>
          <OffthreadVideo src={staticFile(src)} playbackRate={rate} muted
            style={{ width: "100%", height: "100%", display: "block", objectFit: "cover", filter: "contrast(1.06) saturate(1.1)" }} />
        </div>
      </div>
    </>
  );
};

/* ------------------------------------------------------------ hero: "Meet your [ ]" — spins, then lands */
const SPIN = [
  ["Claude", "claude"], ["Codex", "openai"], ["Cursor", "cursor"], ["Antigravity", "antigravity"],
  ["Copilot", "copilot"], ["OpenCode", "opencode"], ["Command Code", "commandcode"],
  ["Claude", "claude"], ["Codex", "openai"], ["Cursor", "cursor"], ["Antigravity", "antigravity"],
  ["Copilot", "copilot"], ["OpenCode", "opencode"], ["Notch.", "notch"],
];
const Hero: React.FC = () => {
  const f = useCurrentFrame(); const { fps } = useVideoConfig();
  const ITEM = 104, S0 = 16, S1 = 82, N = SPIN.length - 1;
  const ease = Easing.bezier(0.16, 0.6, 0.12, 1);          // fast, fast, then a long slow stop
  const at = (fr: number) => interpolate(fr, [S0, S1], [0, 1], { ...clamp, easing: ease }) * N;
  const pos = at(f), speed = Math.abs(at(f) - at(f - 1));
  const blur = Math.min(9, speed * 11);
  const land = spring({ frame: f - S1, fps, config: { damping: 9, stiffness: 190 } });
  const intro = spring({ frame: f, fps, config: { damping: 18, stiffness: 140 } });
  const dive = interpolate(f, [102, 120], [0, 1], { ...clamp, easing: Easing.in(Easing.cubic) });
  return (
    <AbsoluteFill style={{ fontFamily: FONT, color: INK, transform: `scale(${1 + dive * 5})`,
      transformOrigin: "682px 932px", opacity: 1 - interpolate(dive, [0.6, 1], [0, 1], clamp), filter: `blur(${dive * 6}px)` }}>
      <div style={{ position: "absolute", left: 70, top: 880, fontSize: 100, fontWeight: 800, letterSpacing: "-0.045em",
        opacity: intro, transform: `translateY(${(1 - intro) * 50}px)` }}>Meet your</div>
      <div style={{ position: "absolute", left: 540, top: 880 - ITEM * 2, height: ITEM * 5, width: 540, overflow: "hidden",
        maskImage: "linear-gradient(transparent, #000 32%, #000 68%, transparent)", WebkitMaskImage: "linear-gradient(transparent, #000 32%, #000 68%, transparent)",
        opacity: intro }}>
        <div style={{ transform: `translateY(${ITEM * 2 - pos * ITEM + 2}px)`, filter: `blur(${blur}px)` }}>
          {SPIN.map(([t, g], i) => {
            const d = Math.min(1, Math.abs(i - pos));
            const isLast = i === N;
            const pop = isLast && f > S1 - 4 ? 0.9 + 0.1 * land : 1;
            return (
              <div key={i} style={{ height: ITEM, display: "flex", alignItems: "center" }}>
                <div style={{ display: "flex", alignItems: "center", gap: 14, padding: "10px 30px 10px 18px", borderRadius: 999,
                  background: `rgba(13,148,136,${1 - d})`, fontSize: 58, fontWeight: 650, letterSpacing: "-0.03em",
                  color: interpolateColors(d, [0, 1], ["#ffffff", "#b3b8c0"]), transform: `scale(${(1 - d * 0.1) * pop})`, transformOrigin: "left center",
                  whiteSpace: "nowrap", boxShadow: d < 0.5 ? `0 12px 40px ${GLOW}55` : "none" }}>
                  <Glyph name={g} size={52} color={interpolateColors(d, [0, 1], ["#ffffff", "#b3b8c0"])}
                    style={{ filter: g === "notch" ? `invert(${1 - d * 0.3})` : undefined }} />{t}
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </AbsoluteFill>
  );
};

/* ------------------------------------------------------------ "7 tools." grid */
const TOOLS = [
  { g: "claude", v: 91 }, { g: "cursor", v: 12 }, { g: "openai", v: 86 }, { g: "antigravity", v: 52 },
  { g: "opencode", v: 30 }, { g: "commandcode", v: 64 }, { g: "copilot", v: 40 },
];
const ToolGrid: React.FC = () => {
  const f = useCurrentFrame(); const { fps } = useVideoConfig();
  const pos = (i: number) => i < 4 ? { x: 100 + i * 230, y: 760 } : { x: 215 + (i - 4) * 230, y: 1000 };
  return (
    <AbsoluteFill>
      <Kinetic lines={[{ text: "Seven tools." }, { text: "Every one you use.", color: TEAL }]} />
      {TOOLS.map((t, i) => {
        const p = spring({ frame: f - 8 - i * 4, fps, config: { damping: 12, stiffness: 160 } });
        const draw = interpolate(f, [16 + i * 4, 44 + i * 4], [0, 1], { ...clamp, easing: Easing.out(Easing.cubic) });
        const { x, y } = pos(i);
        return (
          <div key={t.g} style={{ position: "absolute", left: x, top: y + Math.sin((f + i * 9) / 11) * 8,
            transform: `scale(${p})`, opacity: Math.min(1, p * 1.4) }}>
            <div style={{ width: 190, height: 190, borderRadius: "50%", background: "#000", display: "grid", placeItems: "center",
              boxShadow: `0 24px 50px rgba(10,20,30,.25), 0 0 44px ${heat(t.v)}40` }}>
              <Ring size={150} value={t.v} progress={draw} glyph={t.g} stroke={7} />
            </div>
          </div>
        );
      })}
      <Caption tag="7 tools" text="Claude, Codex, Cursor, Copilot and more." delay={22} />
    </AbsoluteFill>
  );
};


/* ------------------------------------------------------------ menu bar: live label */
const LABELS = ["Claude 58%", "Codex 86%", "Cursor 0%", "Antigravity 0", "Copilot 0%", "OpenCode \u2014", "Claude 58%"];
const MB_FONT = { fontFamily: FONT, fontSize: 13.5, fontWeight: "500" as const };
const MenuBar: React.FC<{ dur: number }> = ({ dur }) => {
  const f = useCurrentFrame(); const { fps } = useVideoConfig();
  const K = 1.8, STEP = 11, START = 16;
  const raw = Math.max(0, (f - START) / STEP);
  const idx = Math.min(LABELS.length - 1, Math.floor(raw));
  const t = idx >= LABELS.length - 1 ? 1 : interpolate(raw - idx, [0, 0.55], [0, 1], { ...clamp, easing: Easing.out(Easing.cubic) });
  const prev = LABELS[Math.max(0, idx - (f >= START ? 0 : 0))];
  const cur = LABELS[Math.min(LABELS.length - 1, idx + (raw >= 0 && f >= START ? 1 : 0))] ?? prev;
  const from = LABELS[idx], to = LABELS[Math.min(LABELS.length - 1, idx + 1)];
  const w = (s: string) => measureText({ text: s, ...MB_FONT }).width;
  const labelW = f < START ? w(LABELS[0]) : interpolate(t, [0, 1], [w(from), w(to)]);
  const enter = spring({ frame: f, fps, config: { damping: 18, stiffness: 110 } });
  const cam = interpolate(f, [12, dur - 10], [1, 2.25], { ...clamp, easing: Easing.inOut(Easing.cubic) });
  const glow = interpolate(f, [20, 40], [0, 1], clamp);
  const stripW = 108 + 24 + 4 + labelW + 6 + 364;
  const left = 540 - (stripW * K) / 2, top = 840;
  const itemX = left + (108 + 12) * K, itemY = top + 16 * K;
  void prev; void cur;
  return (
    <AbsoluteFill>
      <div style={{ position: "absolute", inset: 0, transform: `scale(${cam})`, transformOrigin: `${itemX + 40}px ${itemY}px` }}>
        <div style={{ position: "absolute", inset: 0, perspective: 1600 }}>
          <div style={{ position: "absolute", left, top, width: stripW, height: 32, transform: `scale(${K}) rotateX(${(1 - enter) * 40}deg)`,
            transformOrigin: "0 0", opacity: enter }}>
            {/* the screen this menu bar belongs to */}
            <div style={{ position: "absolute", left: -10, top: -8, width: stripW + 20, height: 150, borderRadius: 14,
              background: "linear-gradient(180deg,#141416 0%,#0f0f10 22%,#2a2b2f 60%,#0b0b0c 100%)",
              boxShadow: `0 40px 90px rgba(10,20,30,.30), 0 0 0 1px rgba(10,10,11,.1), 0 0 90px ${GLOW}33` }} />
            <div style={{ position: "absolute", inset: 0, display: "flex", alignItems: "center", background: "#0f0f10", borderRadius: 3 }}>
              <Img src={staticFile("mb_left@4x.png")} style={{ height: 32, display: "block" }} />
              <div style={{ position: "relative", display: "flex", alignItems: "center", height: 32 }}>
                <div style={{ position: "absolute", left: -3, right: -4, top: 4, bottom: 4, borderRadius: 6,
                  background: `rgba(95,220,201,${0.28 * glow})`, boxShadow: `0 0 ${14 * glow}px ${LITE}` }} />
                <Img src={staticFile("mb_icon@4x.png")} style={{ height: 32, display: "block", position: "relative" }} />
                <div style={{ position: "relative", width: labelW + 4, height: 32, overflow: "hidden", marginLeft: 4, marginRight: 6 }}>
                  {f < START ? (
                    <span style={{ ...MB_FONT, position: "absolute", left: 0, top: 7, color: "rgba(255,255,255,.92)", whiteSpace: "nowrap" }}>{LABELS[0]}</span>
                  ) : (<>
                    <span style={{ ...MB_FONT, position: "absolute", left: 0, top: 7 - 20 * t, opacity: 1 - t, color: "rgba(255,255,255,.92)", whiteSpace: "nowrap" }}>{from}</span>
                    <span style={{ ...MB_FONT, position: "absolute", left: 0, top: 7 + 20 * (1 - t), opacity: t, color: "rgba(255,255,255,.92)", whiteSpace: "nowrap" }}>{to}</span>
                  </>)}
                </div>
              </div>
              <Img src={staticFile("mb_right@4x.png")} style={{ height: 32, display: "block" }} />
            </div>
          </div>
        </div>
      </div>
      <Kinetic lines={[{ text: "Right in your" }, { text: "menu bar.", color: TEAL }]} />
      <Caption tag="Menu bar" glyph="notch" text="Any tool you pick, one glance away." delay={12} />
    </AbsoluteFill>
  );
};


/* ------------------------------------------------------------ statements: one line hands off to the next */
const SAYINGS: Line[][] = [
  [{ text: "All in" }, { text: "one notch.", color: TEAL }],
  [{ text: "Every limit." }, { text: "Every reset.", color: TEAL }],
  [{ text: "Never cut off" }, { text: "mid-task.", color: TEAL }],
];
const Statements: React.FC = () => {
  const f = useCurrentFrame(); const { fps } = useVideoConfig();
  const SLOT = 35;
  return (
    <AbsoluteFill style={{ fontFamily: FONT }}>
      {SAYINGS.map((lines, k) => {
        const lf = f - k * SLOT;
        if (lf < -2 || lf > SLOT + 12) return null;
        const last = k === SAYINGS.length - 1;
        const out = last ? 0 : interpolate(lf, [SLOT - 9, SLOT + 3], [0, 1], { ...clamp, easing: Easing.in(Easing.cubic) });
        let w = 0;
        return (
          <div key={k} style={{ position: "absolute", inset: 0, display: "grid", placeItems: "center",
            transform: `translateY(${-out * 140}px) scale(${1 + out * 0.06})`, opacity: 1 - out, filter: `blur(${out * 16}px)` }}>
            <div style={{ textAlign: "center", fontSize: 134, fontWeight: 850, letterSpacing: "-0.05em", lineHeight: 1.0, color: INK }}>
              {lines.map((l, li) => (
                <div key={li} style={{ color: l.color ?? INK, whiteSpace: "nowrap" }}>
                  {l.text.split(" ").map((word, wi) => {
                    const p = spring({ frame: lf - (w++) * 3, fps, config: { damping: 17, stiffness: 170 } });
                    return <span key={wi} style={{ display: "inline-block", margin: "0 0.12em", opacity: p,
                      transform: `translateY(${(1 - p) * 90}px)`, filter: `blur(${(1 - p) * 12}px)` }}>{word}</span>;
                  })}
                </div>
              ))}
            </div>
          </div>
        );
      })}
    </AbsoluteFill>
  );
};

/* ------------------------------------------------------------ ending: rail → logo */
const RAIL = [
  { g: "claude", v: 91 }, { g: "cursor", v: 12 }, { g: "openai", v: 86 }, { g: "antigravity", v: 52 },
  { g: "opencode", v: 30 }, { g: "commandcode", v: 64 }, { g: "copilot", v: 40 },
];
const Ending: React.FC = () => {
  const f = useCurrentFrame(); const { fps } = useVideoConfig();
  // 0–18 "One rail." · 12–52 rail builds · 60–84 collapses · 78–104 logo · 96+ lockup
  const oneIn = spring({ frame: f, fps, config: { damping: 16, stiffness: 150 } });
  const oneOut = interpolate(f, [14, 22], [0, 1], clamp);
  const railIn = spring({ frame: f - 12, fps, config: { damping: 18, stiffness: 120 } });
  const collapse = interpolate(f, [60, 84], [0, 1], { ...clamp, easing: Easing.inOut(Easing.cubic) });
  const railFade = interpolate(f, [90, 102], [1, 0], clamp);
  const logo = interpolate(f, [80, 98], [0, 1], { ...clamp, easing: Easing.out(Easing.cubic) });
  const lift = interpolate(f, [98, 122], [0, 70], { ...clamp, easing: Easing.inOut(Easing.cubic) });
  const wipe = interpolate(f, [116, 138], [0, 1], { ...clamp, easing: Easing.out(Easing.cubic) });
  const btn = spring({ frame: f - 128, fps, config: { damping: 12, stiffness: 150 } });
  const shine = interpolate(f, [140, 160], [-40, 130], clamp);

  const SLOT = 118, W = 124, CY = 900;
  const fullH = RAIL.length * SLOT + 40;
  const railH = interpolate(collapse, [0, 1], [fullH * railIn, 120]);
  // logo 380px at (350,560): its notch ring sits at (663,740), ~81px across
  const cx = interpolate(collapse, [0, 1], [540, 668]);
  const cy = interpolate(collapse, [0, 1], [CY, 743]);
  const ringS = interpolate(collapse, [0, 1], [86, 81]);
  const float = Math.sin(f / 18) * 6 * interpolate(f, [104, 124], [0, 1], clamp);

  return (
    <AbsoluteFill style={{ fontFamily: FONT, color: INK }}>
      {/* "One rail." flash */}
      <div style={{ position: "absolute", inset: 0, display: "grid", placeItems: "center", fontSize: 190, fontWeight: 850,
        letterSpacing: "-0.055em", opacity: oneIn * (1 - oneOut), transform: `scale(${0.9 + 0.1 * oneIn + 0.15 * oneOut})`,
        filter: `blur(${oneOut * 16}px)` }}>
        <div style={{ textAlign: "center", lineHeight: 0.95 }}>One<br /><span style={{ color: TEAL }}>rail.</span></div>
      </div>

      {/* the rail assembles, then folds into one notch */}
      <div style={{ position: "absolute", left: cx - W / 2, top: cy - railH / 2, width: W, height: railH, borderRadius: 62,
        background: "#000", opacity: railIn * railFade, overflow: "hidden",
        boxShadow: `0 40px 90px rgba(10,20,30,.30), 0 0 80px ${GLOW}40` }}>
        {RAIL.map((r, i) => {
          const pop = spring({ frame: f - 20 - i * 4, fps, config: { damping: 12, stiffness: 170 } });
          const draw = interpolate(f, [26 + i * 4, 50 + i * 4], [0, 1], { ...clamp, easing: Easing.out(Easing.cubic) });
          const restY = 20 + i * SLOT + (SLOT - 86) / 2;
          const y = interpolate(collapse, [0, 1], [restY, (railH - ringS) / 2]);
          const keep = i === 0 ? 1 : 1 - collapse;
          return (
            <div key={r.g} style={{ position: "absolute", left: (W - ringS) / 2, top: y, opacity: pop * keep, transform: `scale(${pop})` }}>
              <Ring size={ringS} value={r.v} progress={draw} glyph={r.g} stroke={8} />
            </div>
          );
        })}
      </div>

      {/* the real logo — morphs in around the notch, then glides up to make room */}
      <div style={{ position: "absolute", left: 540 - 190, top: 560 + float - lift, width: 380, height: 380,
        opacity: logo, transform: `scale(${0.96 + 0.04 * logo})`, transformOrigin: "83% 47%",
        filter: `drop-shadow(0 34px 60px rgba(10,20,30,.28)) drop-shadow(0 0 60px ${GLOW}55)` }}>
        <Img src={staticFile("logo.png")} style={{ width: "100%", height: "100%" }} />
      </div>

      {/* wordmark rises letter by letter out of a mask */}
      <div style={{ position: "absolute", left: 0, right: 0, top: 960 - lift, display: "flex", justifyContent: "center",
        overflow: "hidden", height: 190, fontSize: 150, fontWeight: 850, letterSpacing: "-0.055em", lineHeight: 1.2 }}>
        {"DevNotch".split("").map((ch, i) => {
          const q = spring({ frame: f - 100 - i * 2.5, fps, config: { damping: 15, stiffness: 150 } });
          return <span key={i} style={{ display: "inline-block", transform: `translateY(${(1 - q) * 115}%)`,
            filter: `blur(${(1 - q) * 8}px)`, opacity: Math.min(1, q * 2) }}>{ch}</span>;
        })}
      </div>

      {/* tagline wipes on */}
      <div style={{ position: "absolute", left: 0, right: 0, top: 1150 - lift, textAlign: "center", fontSize: 40, fontWeight: 500,
        color: "rgba(10,10,11,.52)", clipPath: `inset(-10% ${100 - 100 * wipe}% -10% 0)`,
        transform: `translateX(${(1 - wipe) * -30}px)` }}>Your AI usage. Always in view.</div>

      {/* button pops, then a light sweeps across it */}
      <div style={{ position: "absolute", left: 0, right: 0, top: 1262 - lift, display: "flex", justifyContent: "center",
        opacity: btn, transform: `scale(${0.7 + 0.3 * btn})` }}>
        <div style={{ position: "relative", overflow: "hidden", background: TEAL, color: "#FFFFFF", borderRadius: 999,
          padding: "22px 46px", fontSize: 36, fontWeight: 650, boxShadow: `0 20px 60px ${GLOW}77` }}>
          Download for macOS
          <div style={{ position: "absolute", top: 0, bottom: 0, width: 120, left: `${shine}%`,
            background: "linear-gradient(90deg, transparent, rgba(255,255,255,.55), transparent)", transform: "skewX(-20deg)" }} />
        </div>
      </div>
    </AbsoluteFill>
  );
};

/* ------------------------------------------------------------ the edit */
export const Reel: React.FC = () => (
  <AbsoluteFill>
    <Backdrop />

    <Sequence from={S.hero.from} durationInFrames={S.hero.dur}><Scene dur={S.hero.dur} noOut><Hero /></Scene></Sequence>

    <Sequence from={S.reveal.from} durationInFrames={S.reveal.dur}>
      <Scene dur={S.reveal.dur}>
        <Display3D src="reveal.mp4" rate={0.892} dur={S.reveal.dur} aspect={1000 / 900} rotY={[46, 24]} rotX={[10, 7]}
          origin="0% 50%" width={1240} left={70} top={560} zoom={[1, 1.75]} zoomAt="12% 58%" zoomStart={16} />
        <Kinetic lines={[{ text: "Tucked into the edge." }, { text: "Out on hover.", color: MUTED }]} size={100} />
      </Scene>
    </Sequence>

    <Sequence from={S.claude.from} durationInFrames={S.claude.dur}>
      <Scene dur={S.claude.dur}>
        <Punch src="claude.mp4" rate={0.285} dur={S.claude.dur} ghost="58%" />
        <Kinetic lines={[{ text: "Claude." }, { text: "Live, to the second.", color: TEAL }]} />
        <Caption tag="Claude" glyph="claude" text="Session, weekly limit, every open terminal." />
      </Scene>
    </Sequence>

    <Sequence from={S.cursor.from} durationInFrames={S.cursor.dur}>
      <Scene dur={S.cursor.dur}>
        <Punch src="cursor.mp4" rate={1} dur={S.cursor.dur} ghost="100%" aspect={600 / 380} tilt={1} />
        <Kinetic lines={[{ text: "Cursor." }, { text: "100% left. For now.", color: TEAL }]} />
        <Caption tag="Cursor" glyph="cursor" text="Knows when the month resets." />
      </Scene>
    </Sequence>

    <Sequence from={S.codex.from} durationInFrames={S.codex.dur}>
      <Scene dur={S.codex.dur}>
        <Punch src="codex.mp4" rate={0.3375} dur={S.codex.dur} ghost="86%" />
        <Kinetic lines={[{ text: "Codex." }, { text: "Tokens & streaks.", color: TEAL }]} />
        <Caption tag="Codex" glyph="openai" text="Read straight from Codex's own records." />
      </Scene>
    </Sequence>

    <Sequence from={S.tools.from} durationInFrames={S.tools.dur}><Scene dur={S.tools.dur}><ToolGrid /></Scene></Sequence>

    <Sequence from={S.tour.from} durationInFrames={S.tour.dur}>
      <Scene dur={S.tour.dur}>
        <Display3D src="tour.mp4" rate={1} dur={S.tour.dur} aspect={1000 / 900} rotY={[30, 22]} rotX={[8, 6]}
          origin="0% 50%" width={1240} left={70} top={560} zoom={[1.35, 1.9]} zoomAt="14% 70%" />
        <Kinetic lines={[{ text: "Hover. Glance." }, { text: "Move on.", color: TEAL }]} />
        <Caption tag="Edge rail" text="Every card, one flick of the cursor." delay={6} />
      </Scene>
    </Sequence>

    <Sequence from={S.top.from} durationInFrames={S.top.dur}>
      <Scene dur={S.top.dur}>
        <Display3D src="top.mp4" rate={1.25} dur={S.top.dur} aspect={720 / 520} rotY={[-26, -12]} rotX={[22, 12]}
          origin="50% 0%" width={1000} left={40} top={640} zoom={[1, 1.65]} zoomAt="46% 40%" zoomStart={10} />
        <Kinetic lines={[{ text: "Or dock it up top." }, { text: "Same rings. Same cards.", color: MUTED }]} size={86} />
        <Caption tag="Top edge" text="Your call, per screen." />
      </Scene>
    </Sequence>

    <Sequence from={S.drop.from} durationInFrames={S.drop.dur}>
      <Scene dur={S.drop.dur}>
        <Punch src="topclaude.mp4" rate={0.64} dur={S.drop.dur} ghost="91%" aspect={560 / 440} tilt={1} />
        <Kinetic lines={[{ text: "Cards drop" }, { text: "straight down.", color: TEAL }]} />
        <Caption tag="Claude" glyph="claude" text="Sessions, limits, resets — at a glance." />
      </Scene>
    </Sequence>

    <Sequence from={S.menu.from} durationInFrames={S.menu.dur}><Scene dur={S.menu.dur}><MenuBar dur={S.menu.dur} /></Scene></Sequence>

    <Sequence from={S.words.from} durationInFrames={S.words.dur}><Scene dur={S.words.dur}><Statements /></Scene></Sequence>

    <Sequence from={S.end.from} durationInFrames={S.end.dur}><Scene dur={S.end.dur} noOut><Ending /></Scene></Sequence>
  </AbsoluteFill>
);

film({ W: 1920, H: 1080, BPM: 120, BEATS: 60 });

const APP = { name: "DevNotch", url: "github.com/Adebayodamilola20/Flux", cta: "Download for macOS",
  line: "Never cut off *mid-task.*", facts: ["7 AI tools", "macOS 15 or later", "nothing to sign in to"] };
// the rail, in its real order; the numbers are made up
const TOOLS = [
  { g: "claude", name: "Claude", v: 58 }, { g: "cursor", name: "Cursor", v: 12 }, { g: "openai", name: "Codex", v: 86 },
  { g: "antigravity", name: "Antigravity", v: 34 }, { g: "opencode", name: "OpenCode", v: 21 },
  { g: "commandcode", name: "Command Code", v: 47 }, { g: "copilot", name: "Copilot", v: 5 },
];
const CHIPS = ["claude /usage", "ChatGPT settings", "Cursor dashboard", "agy /usage", "OpenCode sessions", "Command Code", "Copilot settings"];
const CHIP_AT = [[1140, 250, -9], [1520, 330, 7], [1090, 470, 5], [1480, 560, -6], [1170, 690, -4], [1560, 780, 9], [1250, 880, 6]];
const LEFT = { x: 40, y: 84, w: 620, h: 912 };
const RIGHT = { x: 680, y: 84, w: 1200, h: 912 };
const K = {};
const heat = (v) => (v >= 70 ? "#FF5A1F" : v >= 45 ? "#D7FF2F" : "#00E58A");
const mixHex = (a, b, p) => { const h = (s, i) => parseInt(s.slice(1 + i * 2, 3 + i * 2), 16); return "#" + [0, 1, 2].map((i) => Math.round(lerp(h(a, i), h(b, i), p)).toString(16).padStart(2, "0")).join(""); };

// ---------------------------------------------------------------- DevNotch's own pieces
const glyph = (g, size, color = "#fff") => `<svg viewBox="0 0 100 100" width="${size}" height="${size}" style="display:block;flex:none"><path d="${GLYPH[g]}" fill="${color}" fill-rule="evenodd"/></svg>`;
const RR = 44, CIRC = 2 * Math.PI * RR;
const dnRing = (key, size, g, sw = 8) => `<div class="abs" data-k="${key}" style="width:${size}px;height:${size}px">
  <svg class="abs" style="left:0;top:0" viewBox="0 0 100 100" width="${size}" height="${size}"><circle cx="50" cy="50" r="${RR}" fill="none" stroke="rgba(255,255,255,.14)" stroke-width="${sw}"/>
  <circle data-k="${key}a" cx="50" cy="50" r="${RR}" fill="none" stroke-width="${sw}" stroke-linecap="round" transform="rotate(-90 50 50)" stroke-dasharray="${CIRC.toFixed(2)} ${CIRC.toFixed(2)}"/></svg>
  <div class="abs center" style="left:0;top:0;width:${size}px;height:${size}px">${g ? glyph(g, size * 0.42) : ""}</div></div>`;
function ringSet(key, frac, color) {
  const a = $[key + "a"];
  a.style.strokeDashoffset = (CIRC * (1 - clamp(frac))).toFixed(2);
  a.style.stroke = color;
  a.style.opacity = frac < 0.004 ? "0" : "1";
}
// the rail on the top edge: 7 slots, a ring and its number in each
const SLOT = 150, RING = 96, RAIL_W = TOOLS.length * SLOT + 60, RAIL_H = 190;
const rail = (key) => `<div class="abs rail" data-k="${key}" style="left:0;top:0;width:${RAIL_W}px;height:${RAIL_H}px;border-radius:0 0 56px 56px">
  ${TOOLS.map((tool, i) => `<div class="abs" style="left:${30 + i * SLOT + (SLOT - RING) / 2}px;top:24px">${dnRing(key + "r" + i, RING, tool.g)}</div>
    <div class="abs t" data-k="${key}p${i}" style="left:${30 + i * SLOT}px;top:132px;width:${SLOT}px;text-align:center;font-size:30px;font-weight:700;font-variant-numeric:tabular-nums"></div>`).join("")}</div>`;
function railAt(key, t, t0, stagger = 0.22) {
  TOOLS.forEach((tool, i) => {
    const p = t0 == null ? 1 : prog(t, t0 + i * stagger, 0.7, E.out);
    ringSet(key + "r" + i, (tool.v / 100) * p, heat(tool.v));
    $[key + "p" + i].textContent = t0 != null && t < t0 + i * stagger ? "" : `${Math.round(tool.v * p)}%`;
  });
}
const pointer = (key) => `<svg class="abs" data-k="${key}" width="44" height="54" viewBox="0 0 22 27" style="left:0;top:0;filter:drop-shadow(0 3px 6px rgba(0,0,0,.5))"><path d="M2 2 L2 21 L7 16.5 L10.5 24.5 L13.6 23.2 L10.2 15.4 L17 15.4 Z" fill="#fff" stroke="#000" stroke-width="1.4" stroke-linejoin="round"/></svg>`;
const row = (x, y, w, left, right, rightCss = "") => `<div class="abs row" style="left:${x}px;top:${y}px;width:${w}px;justify-content:space-between">${left}<span class="t" style="${rightCss}">${right}</span></div>`;

// ---------------------------------------------------------------- build
function build(stage) {
  Object.assign(K, { h1: B(1) + 0.15, h2: B(5), h3: B(9), meet: B(13), f1: B(17), f2: B(25), f3: B(33), f4: B(41), end: B(49), out: B(58.5) });
  const cardX = 30 + (SLOT - 560) / 2 + SLOT / 2 + 30, cardY = RAIL_H + 30;          // under the Claude ring, inside the panel
  const PROV = [
    { tool: TOOLS[0], grade: "API", how: "live from Anthropic", bg: "var(--accentDeep)", fg: "#fff", bd: "var(--accentDeep)" },
    { tool: TOOLS[2], grade: "Local", how: "recorded by Codex", bg: "transparent", fg: "var(--ink)", bd: "rgba(242,244,248,.35)" },
    { tool: TOOLS[3], grade: "CLI", how: "read from its /usage panel", bg: "transparent", fg: "var(--ink2)", bd: "rgba(242,244,248,.2)" },
  ];

  stage.innerHTML = `
    ${scene("hookScene", "var(--bg)", `
      <div class="abs" style="left:150px;top:330px">${headline("h1", "They promised\n*unlimited.*", { size: 120 })}</div>
      <div class="abs" style="left:150px;top:330px">${headline("h2", "Then cut you off\n*mid-task.*", { size: 120 })}</div>
      <div class="abs" style="left:150px;top:330px">${headline("h3", "The numbers?\n*Scattered.*", { size: 120 })}</div>
      <div class="abs hl-center" style="left:0;top:470px;width:1920px">${headline("meet", "Meet *DevNotch.*", { size: 150 })}</div>
      <div class="abs dn-card" data-k="limit" style="left:1010px;top:700px;width:800px;height:176px;padding:34px 40px;font-family:var(--mono);font-size:26px;line-height:52px">
        <div style="color:var(--ink2)">✻ Refactoring billing-service…</div>
        <div style="color:#FF5A1F">⎿ Usage limit reached · resets in 4h 12m</div></div>
      ${CHIPS.map((c, i) => `<div class="abs row pill" data-k="chip${i}" style="left:0;top:0;height:64px;padding:0 26px 0 16px;gap:14px;background:var(--card2);border:1px solid var(--hair);font-size:26px;color:var(--ink2);white-space:nowrap">
        ${glyph(TOOLS[i].g, 30, "#9AA3B2")}${c}<span style="color:var(--ink3);font-variant-numeric:tabular-nums">?%</span></div>`).join("")}
      <div class="abs" data-k="arrival" style="left:${(1920 - RAIL_W) / 2}px;top:0">${rail("ar")}</div>`)}

    ${scene("f1", "var(--field1)", `
      ${panel("f1L", LEFT, "var(--panel)", `<div class="abs" style="left:48px;top:110px">${headline("f1h", "Every tool,\n*one rail.*", { size: 84 })}</div>`)}
      ${panel("f1R", RIGHT, "var(--panel)", `<div class="abs" data-k="f1rail" style="left:${(1200 - RAIL_W) / 2}px;top:0">${rail("r1")}</div>
`)}`)}

    ${scene("f2", "var(--field2)", `
      ${panel("f2L", LEFT, "var(--panel)", `<div class="abs" style="left:48px;top:110px">${headline("f2h", "Hover for\nthe *details.*", { size: 84 })}</div>`)}
      ${panel("f2R", RIGHT, "var(--panel)", `<div class="abs" style="left:${(1200 - RAIL_W) / 2}px;top:0">${rail("r2")}</div>
        <div class="abs dn-card" data-k="usage" style="overflow:hidden">
          <div data-k="usageIn" class="abs" style="left:0;top:0;width:560px;height:520px">
            <div class="abs row" style="left:34px;top:30px;gap:14px">${glyph("claude", 34)}<span class="t" style="font-size:34px;font-weight:700">Claude Usage</span></div>
            ${row(34, 100, 492, `<span class="t" style="font-size:24px;font-weight:600">Current session</span>`, "Resets in 1h 48m", "font-size:21px;color:var(--ink3)")}
            <div class="abs bar-track" style="left:34px;top:144px;width:492px;height:10px"><div data-k="bar1" style="height:100%;background:#D7FF2F;border-radius:5px"></div></div>
            <div class="abs mask" style="left:34px;top:168px;width:420px;height:32px"><div data-k="use1" class="abs" style="left:0;top:0;width:420px;height:32px"></div></div>
            ${row(34, 226, 492, `<span class="t" style="font-size:24px;font-weight:600">This week</span>`, "Resets Thu 11:00", "font-size:21px;color:var(--ink3)")}
            <div class="abs bar-track" style="left:34px;top:270px;width:492px;height:10px"><div data-k="bar2" style="height:100%;background:#00E58A;border-radius:5px"></div></div>
            <div class="abs mask" style="left:34px;top:294px;width:420px;height:32px"><div data-k="use2" class="abs" style="left:0;top:0;width:420px;height:32px"></div></div>
            <div class="abs" style="left:34px;top:350px;width:492px;height:1px;background:rgba(255,255,255,.08)"></div>
            <div class="abs" data-k="sess0" style="left:34px;top:370px;width:492px;height:60px">
              ${row(0, 0, 492, `<span class="t" style="font-size:24px;font-weight:600">billing-service</span>`, "idle · 2 min", "font-size:21px;color:var(--ink3)")}
              <span class="abs t" style="left:0;top:32px;font-size:20px;color:var(--ink3)">Terminal</span></div>
            <div class="abs" data-k="sess1" style="left:34px;top:440px;width:492px;height:60px">
              ${row(0, 0, 492, `<span class="t" style="font-size:24px;font-weight:600">landing-page</span>`, "● working", "font-size:21px;color:var(--accent)")}
              <span class="abs t" style="left:0;top:32px;font-size:20px;color:var(--ink3)">VS Code</span></div></div></div>
        ${pointer("ptr")}`)}`)}

    ${scene("f3", "var(--field3)", `
      ${panel("f3L", LEFT, "var(--panel)", `<div class="abs" style="left:48px;top:110px">${headline("f3h", "Every number,\n*sourced.*", { size: 84 })}</div>`)}
      ${panel("f3R", RIGHT, "var(--panel)", PROV.map((p, i) => card("prov" + i, { x: 80, y: 110 + i * 240, w: 1040, h: 200 }, `
          <div class="abs" style="left:34px;top:36px">${dnRing("pr" + i, 128, p.tool.g, 9)}</div>
          <div class="abs t" style="left:196px;top:44px;font-size:44px;font-weight:700">${p.tool.name}</div>
          <div class="abs row pill" data-k="pill${i}" style="left:196px;top:112px;height:48px;padding:0 22px;gap:12px;background:${p.bg};border:2px solid ${p.bd};color:${p.fg};font-size:22px">
            <b>${p.grade}</b><span style="font-weight:500">${p.how}</span></div>
          <div class="abs t" data-k="pv${i}" style="right:44px;top:56px;font-size:84px;font-weight:750;letter-spacing:-.03em;font-variant-numeric:tabular-nums"></div>`)).join(""))}`)}

    ${scene("f4", "var(--field4)", `
      ${panel("f4L", LEFT, "var(--panel)", `<div class="abs" style="left:48px;top:110px">${headline("f4h", "Or keep it in\nthe *menu bar.*", { size: 84 })}</div>`)}
      ${panel("f4R", RIGHT, "var(--panel)", `<div class="abs" data-k="mbWrap" style="left:0;top:0;width:1200px;height:912px;transform-origin:1140px 412px">
          <div class="abs" style="left:40px;top:370px;width:1120px;height:84px;border-radius:18px;background:#0F0F10;border:1px solid rgba(255,255,255,.07)">
            <div class="abs row" style="left:0;top:0;height:84px;width:1120px;padding:0 34px;gap:34px;color:#fff">
              <span class="t" style="font-size:30px;font-weight:700"></span>
              <div class="row" style="margin-left:auto;gap:34px;font-size:30px;font-weight:500">
                <div class="row" data-k="mbItem" style="gap:12px;height:56px;padding:0 14px;border-radius:12px">
                  <span style="display:block;width:34px;height:34px;color:#fff">${MB_ICON}</span>
                  <div class="mask" style="position:relative;height:44px;width:230px"><div data-k="mbRoll" class="abs" style="left:0;top:4px;width:230px;height:40px"></div></div></div>
                <svg width="34" height="26" viewBox="0 0 34 26"><path d="M17 23 L12 18 A7 7 0 0 1 22 18 Z M7 13 A14 14 0 0 1 27 13 L24.5 15.5 A10.5 10.5 0 0 0 9.5 15.5 Z M2 8 A21 21 0 0 1 32 8 L29.5 10.5 A17.5 17.5 0 0 0 4.5 10.5 Z" fill="#fff"/></svg>
                <svg width="44" height="22" viewBox="0 0 44 22"><rect x="1" y="1" width="38" height="20" rx="6" fill="none" stroke="#fff" stroke-opacity=".5" stroke-width="2"/><rect x="4" y="4" width="26" height="14" rx="3" fill="#fff"/><rect x="40.5" y="7.5" width="2.5" height="7" rx="1.2" fill="#fff" fill-opacity=".5"/></svg>
                <svg width="28" height="28" viewBox="0 0 28 28"><circle cx="12" cy="12" r="8.5" fill="none" stroke="#fff" stroke-width="3"/><path d="M18.5 18.5 L25 25" stroke="#fff" stroke-width="3" stroke-linecap="round"/></svg>
                <span class="t" style="font-variant-numeric:tabular-nums">Mon 28 Sep&nbsp;&nbsp;9:41</span></div></div></div></div>`)}`)}

    ${scene("endScene", "var(--bg)", `
      <div class="abs row" data-k="lockup" style="left:0;top:300px;width:1920px;justify-content:center;gap:40px">
        <img data-k="icon" src="${ASSETS.img.logo}" style="width:190px;height:190px;display:block">
        <div class="mask" style="height:184px"><div data-k="wordmark" class="t" style="font-size:160px;font-weight:750;letter-spacing:-.045em">${APP.name}</div></div></div>
      <div class="abs hl-center" style="left:0;top:548px;width:1920px">${headline("tag", APP.line, { size: 76, color: "var(--ink2)", weight: 650 })}</div>
      <div class="abs row" style="left:0;top:700px;width:1920px;justify-content:center;gap:40px">
        <div class="center pill" data-k="cta" style="height:84px;padding:0 48px;background:var(--accentDeep);color:#fff;font-size:32px">${APP.cta}</div>
        <div class="row" style="font-family:var(--mono);font-size:30px;color:var(--ink2);min-width:640px">${[...APP.url].map((ch, i) => `<span data-k="url${i}">${ch}</span>`).join("")}</div></div>
      <div class="abs kit-mono" data-k="facts" style="left:0;top:930px;width:1920px;text-align:center;font-size:24px">${APP.facts.join("&nbsp;&nbsp;·&nbsp;&nbsp;")}</div>`)}

    <div class="abs" data-k="relay" style="left:0;top:0">${dnRing("rl", 100, "claude", 8)}</div>
    <div class="abs t" data-k="relayPct" style="left:0;top:0;width:320px;text-align:center;font-family:var(--mono);font-size:30px;color:var(--ink2);font-variant-numeric:tabular-nums"></div>`;
  collect(stage);
  K.use1 = roller($.use1, "font-size:21px;color:var(--ink2)");
  K.use2 = roller($.use2, "font-size:21px;color:var(--ink2)");
  K.menu = roller($.mbRoll, "font-size:30px;font-weight:500;color:#fff");
  K.card = { x: cardX, y: cardY };
  // where the logo's own ring sits, so the relay ring can land in it
  const ib = $.icon.getBoundingClientRect(), sb = stage.getBoundingClientRect(), k = FILM.W / sb.width;
  K.logoRing = { x: (ib.left - sb.left + ib.width * 0.825) * k, y: (ib.top - sb.top + ib.height * 0.475) * k, d: ib.width * k * 0.21 };
}

// ---------------------------------------------------------------- the relay ring: promise → used up → first slot → the logo
function relayAt(t) {
  const SLOT0 = { x: (1920 - RAIL_W) / 2 + 30 + (SLOT - RING) / 2 + RING / 2, y: 24 + RING / 2 };
  const HOOK = { x: 1430, y: 440 };
  let x = HOOK.x, y = HOOK.y, d = 260, on = false, frac = 0, color = "#00E58A", pct = "";
  const born = clamp(spring(t, K.h1 + 0.35, 0.5, 0.8), 0, 1.0);
  if (t >= K.h1 + 0.35 && t < K.meet + 0.5) {
    on = true;
    d = 260 * born;
    const promise = prog(t, K.h1 + 0.6, 0.6, E.out) * 0.06;
    const burn = prog(t, K.h2 + 0.35, 0.9, E.inOut);
    frac = promise + (1 - promise) * burn;
    color = burn < 0.5 ? mixHex("#00E58A", "#D7FF2F", burn * 2) : mixHex("#D7FF2F", "#FF5A1F", burn * 2 - 1);
    pct = t >= K.h1 + 0.6 && t < K.h2 + 1.1 ? `${Math.round(frac * 100)}% used` : "";   // steps aside as the limit card lands
    const shrink = prog(t, K.h3, 0.35, E.in);                   // gone as the dashboards scatter…
    const fly = prog(t, K.meet, 0.5, E.smooth);                 // …then back to take the first slot
    d = lerp(d * (1 - 0.7 * shrink), RING, fly);
    x = lerp(HOOK.x, SLOT0.x, fly);
    y = lerp(HOOK.y + 40 * shrink, SLOT0.y + (1 - arrivalAt(t)) * -260, fly);
    if (shrink >= 1 && fly <= 0) on = false;
    frac *= 1 - fly;
  }
  if (t >= K.end + 0.55 && t < K.end + 1.55) {                 // after the wipe: it lands in the logo's ring
    on = true;
    const born2 = clamp(spring(t, K.end + 0.55, 0.4, 0.8), 0, 1.05);
    const f = prog(t, K.end + 0.75, 0.55, E.smooth);
    x = lerp(960, K.logoRing.x, f); y = lerp(560, K.logoRing.y, f); d = lerp(160 * born2, K.logoRing.d, f);
    frac = prog(t, K.end + 0.55, 0.4, E.out); color = "#5FDCC9";
    $.relay.style.opacity = (1 - prog(t, K.end + 1.25, 0.3)).toFixed(3);
  } else $.relay.style.opacity = "1";
  show($.relay, on && d > 1);
  setT($.relay, `translate(${(x - 50).toFixed(2)}px,${(y - 50).toFixed(2)}px) scale(${(d / 100).toFixed(4)})`);
  ringSet("rl", frac, color);
  show($.relayPct, pct !== "");
  $.relayPct.textContent = pct;
  setT($.relayPct, `translate(${(HOOK.x - 160).toFixed(0)}px,${(HOOK.y + 175).toFixed(0)}px)`);
}
const arrivalAt = (t) => clamp(spring(t, K.meet, 0.55, 0.86), 0, 1.03);

// ---------------------------------------------------------------- apply
function apply(t) {
  // hook
  sceneAt("hookScene", t, -1, K.f1 + 0.6);
  headlineAt("h1", t, K.h1, K.h2 - 0.3);
  headlineAt("h2", t, K.h2, K.h3 - 0.3);
  headlineAt("h3", t, K.h3, K.meet - 0.3);
  headlineAt("meet", t, K.meet + 0.35, K.f1 - 0.1);
  const slam = clamp(spring(t, K.h2 + 1.1, 0.34, 0.62), 0, 1.1), leaveL = prog(t, K.h3, 0.3, E.in);
  show($.limit, t >= K.h2 + 1.1 && leaveL < 1);
  $.limit.style.opacity = (1 - leaveL).toFixed(3);
  setT($.limit, `translate(${(Math.sin((t - K.h2 - 1.1) * 60) * 14 * Math.max(0, 1 - (t - K.h2 - 1.1) / 0.35) * (t > K.h2 + 1.1 ? 1 : 0)).toFixed(2)}px,${((1 - slam) * 60 + 30 * leaveL).toFixed(2)}px) scale(${(0.9 + 0.1 * clamp(slam)).toFixed(4)})`);
  CHIPS.forEach((_, i) => {
    const [cx, cy, rot] = CHIP_AT[i];
    const p = clamp(spring(t, K.h3 + 0.25 + i * 0.07, 0.5, 0.72), 0, 1.08), gone = prog(t, K.meet - 0.35, 0.3, E.in);
    const el = $["chip" + i];
    show(el, t >= K.h3 + 0.25 + i * 0.07 && gone < 1);
    const fx = lerp(1430, cx, p) + gone * (cx - 1000) * 1.4, fy = lerp(470, cy, p) + gone * (cy - 540) * 1.4;
    setT(el, `translate(${(fx - 170).toFixed(2)}px,${(fy - 32).toFixed(2)}px) rotate(${(rot * p).toFixed(2)}deg) scale(${(0.6 + 0.4 * clamp(p)).toFixed(4)})`);
    el.style.opacity = (1 - gone).toFixed(3);
  });
  const arr = arrivalAt(t), arrOut = prog(t, K.f1 - 0.2, 0.35, E.in);
  show($.arrival, t >= K.meet);
  setT($.arrival, `translateY(${((1 - arr) * -260 - arrOut * 260).toFixed(2)}px)`);
  railAt("ar", t, 1e9);
  relayAt(t);

  // f1: every tool, one rail
  sceneAt("f1", t, K.f1, K.f2 + 0.6);
  driftAt($.f1L, t, K.f1); driftAt($.f1R, t, K.f1, 160);
  headlineAt("f1h", t, K.f1 + 0.3);
  setT($.f1rail, `translateY(${((1 - clamp(spring(t, K.f1 + 0.55, 0.5, 0.86), 0, 1.02)) * -230).toFixed(2)}px)`);
  railAt("r1", t, B(19));

  // f2: hover for the details
  sceneAt("f2", t, K.f2, K.f3 + 0.6);
  driftAt($.f2L, t, K.f2); driftAt($.f2R, t, K.f2, 160);
  headlineAt("f2h", t, K.f2 + 0.3);
  railAt("r2", t, null);
  const ring0 = { x: (1200 - RAIL_W) / 2 + 30 + SLOT / 2, y: 24 + RING / 2 };
  const pm = prog(t, K.f2 + 0.55, 0.5, E.smooth);
  show($.ptr, t >= K.f2 + 0.45);
  setT($.ptr, `translate(${lerp(760, ring0.x + 8, pm).toFixed(2)}px,${lerp(640, ring0.y + 12, pm).toFixed(2)}px) scale(${press(t, B(26.1), 0.86).toFixed(4)})`);
  setT($["r2r0"], `scale(${(1 + 0.12 * pulse(t, B(26.1), 0.35)).toFixed(4)})`);
  const open = prog(t, B(26.4), 0.45, E.inOut);
  const from = { x: ring0.x - 40, y: RAIL_H - 6, w: 80, h: 10, r: 5 };
  const to = { x: ring0.x - 90, y: RAIL_H + 26, w: 560, h: 520, r: 26 };
  show($.usage, t >= B(26.4));
  rectCss($.usage, mixRect(from, to, open));
  const inn = clamp(spring(t, B(26.4) + 0.42, 0.45, 0.88), 0, 1.02);
  $.usageIn.style.opacity = clamp(inn * 1.4).toFixed(3);
  setT($.usageIn, `translateY(${((1 - inn) * 18).toFixed(2)}px)`);
  $.bar1.style.width = (58 * prog(t, B(28), 0.7, E.out)).toFixed(2) + "%";
  $.bar2.style.width = (23 * prog(t, B(28.5), 0.7, E.out)).toFixed(2) + "%";
  roll(K.use1, t, [{ t: B(26.4) + 0.45, v: "0% used" }, { t: B(28) + 0.35, v: "58% used · 42% left" }]);
  roll(K.use2, t, [{ t: B(26.4) + 0.45, v: "0% used" }, { t: B(28.5) + 0.35, v: "23% used · 77% left" }]);
  ["sess0", "sess1"].forEach((k, i) => {
    const p = clamp(spring(t, B(29.5 + i * 0.6), 0.45, 0.86), 0, 1.02);
    $[k].style.opacity = clamp(p * 1.4).toFixed(3);
    setT($[k], `translateY(${((1 - p) * 22).toFixed(2)}px)`);
  });

  // f3: every number, sourced
  sceneAt("f3", t, K.f3, K.f4 + 0.6);
  driftAt($.f3L, t, K.f3); driftAt($.f3R, t, K.f3, 160);
  headlineAt("f3h", t, K.f3 + 0.3);
  [0, 2, 3].forEach((ti, i) => {
    const at = B(35 + i * 0.75);
    cardAt("prov" + i, t, at);
    const p = prog(t, at + 0.2, 0.7, E.out), v = TOOLS[ti].v;
    ringSet("pr" + i, (v / 100) * p, heat(v));
    $["pv" + i].textContent = `${Math.round(v * p)}%`;
    const pill = clamp(spring(t, at + 0.45, 0.4, 0.7), 0, 1.1);
    setT($["pill" + i], `scale(${pill.toFixed(4)})`);
    $["pill" + i].style.transformOrigin = "0 50%";
  });

  // f4: the menu bar
  sceneAt("f4", t, K.f4, K.end + 0.6);
  driftAt($.f4L, t, K.f4); driftAt($.f4R, t, K.f4, 160);
  headlineAt("f4h", t, K.f4 + 0.3);
  setT($.mbWrap, `scale(${track(t, 1, [{ t: B(42), d: 1.1, to: 1.28, e: E.smooth }, { t: B(44), d: 4, to: 1.33, e: E.linear }]).toFixed(4)})`);
  roll(K.menu, t, [{ t: K.f4 + 0.5, v: "Claude 58%" }, { t: B(43), v: "Codex 86%" }, { t: B(44), v: "Cursor 12%" }, { t: B(45), v: "Copilot 5%" }, { t: B(46), v: "Claude 58%" }]);
  const hi = Math.max(pulse(t, B(43), 0.5), pulse(t, B(44), 0.5), pulse(t, B(45), 0.5), pulse(t, B(46), 0.5));
  $.mbItem.style.background = `rgba(95,220,201,${(0.1 + 0.22 * hi).toFixed(3)})`;

  // end card
  sceneAt("endScene", t, K.end);
  const clear = prog(t, K.out, 0.45, E.in);
  const iconP = prog(t, K.end + 1.1, 0.5, E.out);
  $.icon.style.opacity = (iconP * (1 - clear)).toFixed(3);
  setT($.icon, `scale(${(0.9 + 0.1 * iconP).toFixed(4)})`);
  $.icon.style.transformOrigin = "82.5% 47.5%";
  setT($.wordmark, `translateY(${(((1 - clamp(spring(t, K.end + 1.3, 0.5, 0.86), 0, 1.02)) + clear) * 105).toFixed(2)}%)`);
  headlineAt("tag", t, B(52), K.out);
  const cta = clamp(spring(t, B(54), 0.42, 0.74), 0, 1.08) * (1 - clear);
  setT($.cta, `scale(${cta.toFixed(4)})`);
  [...APP.url].forEach((_, i) => show($["url" + i], t >= B(54.6) + i * 0.03 && clear < 0.5));
  $.facts.style.opacity = (prog(t, B(56), 0.5) * (1 - clear)).toFixed(3);
}

// ---------------------------------------------------------------- sounds on the actions
function cues() {
  const wipe = (t) => ["whoosh", t - 0.05, { pan: 0.5 }];
  return [
    ...headlineCues("h1", K.h1), ["pop", K.h1 + 0.35, { note: 5 }],
    ...headlineCues("h2", K.h2), ...[0, 1, 2, 3, 4, 5].map((i) => ["blip", K.h2 + 0.35 + i * 0.15, { note: 2 + i }]), ["thud", K.h2 + 1.1], ["click", K.h2 + 1.12, { gain: 2 }],
    ...headlineCues("h3", K.h3), ...CHIPS.map((_, i) => ["pop", K.h3 + 0.25 + i * 0.07, { note: 3 + (i % 4), gain: -3 }]),
    ["whoosh", K.meet - 0.35, { pan: -0.3 }], ["thud", K.meet + 0.1], ...headlineCues("meet", K.meet + 0.35),
    wipe(K.f1), ...headlineCues("f1h", K.f1 + 0.3), ["thud", K.f1 + 0.6], ...TOOLS.map((_, i) => ["blip", B(19) + i * 0.22, { note: 3 + i }]),
    wipe(K.f2), ...headlineCues("f2h", K.f2 + 0.3), ["click", B(26.1)], ["whoosh", B(26.4), { gain: -6, pan: -0.2 }], ["thud", B(26.4) + 0.4, { gain: -3 }],
    ["blip", B(28), { note: 6 }], ["blip", B(28.5), { note: 4 }], ["pop", B(29.5), { note: 7 }], ["pop", B(30.1), { note: 9 }],
    wipe(K.f3), ...headlineCues("f3h", K.f3 + 0.3), ...[0, 1, 2].map((i) => ["thud", B(35 + i * 0.75)]), ...[0, 1, 2].map((i) => ["pop", B(35 + i * 0.75) + 0.45, { note: 7 - i }]),
    wipe(K.f4), ...headlineCues("f4h", K.f4 + 0.3), ...[43, 44, 45, 46].map((b) => ["tick", B(b), { gain: 3 }]),
    wipe(K.end), ["pop", K.end + 0.6, { note: 5 }], ["chime", K.end + 1.15], ["thud", K.end + 1.35, { gain: -3 }], ...headlineCues("tag", B(52)), ["pop", B(54), { note: 9 }],
    ...[...APP.url].map((_, i) => ["tick", B(54.6) + i * 0.03, { gain: -6 }]),
  ];
}

"""Generate the DevNotch hero shot as a layered, Figma-importable SVG.

Run via ./make.sh (which also renders the PNGs). Everything you'd want to
change lives in CONFIG below.
"""
import base64, math

# ============================== CONFIG ==============================
W, H = 1600, 1000        # artboard

# camera: where the screen's top-left corner lands, how far it's turned,
# and how far in we're zoomed. Bigger SCALE = tighter crop, bigger UI.
ORIGIN_X, ORIGIN_Y = 615, -130
TILT   = 8               # degrees clockwise; samples sit nearer 15-20
SCALE  = 1.58

OUT = "DevNotch — Hero Shot.svg"
# ====================================================================

SW, SH = 1240, 800          # screen, local coords
R_SCREEN = 26

INTER = "Inter, 'SF Pro Text', -apple-system, 'Helvetica Neue', Arial, sans-serif"
MONO  = "'Roboto Mono', 'SF Mono', Menlo, monospace"

wp = base64.b64encode(open("wallpaper.jpg","rb").read()).decode()

# ---------------- rail geometry ----------------
RAIL_W   = 46
RAIL_R   = 28.5
SLOT_H   = 66
PAD      = 28
RAIL_H   = PAD*2 + SLOT_H*3          # 254
RAIL_Y   = (SH - RAIL_H)/2           # 273
CX       = RAIL_W/2                  # 23
RING_R   = 16
STROKE   = 2.8

slots = [
    ("Claude",      73, "#FF5A1F", "#D97757"),
    ("Codex",       21, "#00E58A", "#10A37F"),
    ("Antigravity", 52, "#D7FF2F", "#4285F4"),
]

def arc(cx, cy, r, pct):
    """clockwise arc from 12 o'clock"""
    a = math.radians(-90 + pct/100*360)
    x, y = cx + r*math.cos(a), cy + r*math.sin(a)
    large = 1 if pct > 50 else 0
    return f"M {cx:.2f} {cy-r:.2f} A {r} {r} 0 {large} 1 {x:.3f} {y:.3f}"

slot_svg = []
for i, (name, pct, arc_col, tool_col) in enumerate(slots):
    sy = RAIL_Y + PAD + i*SLOT_H
    cy = sy + 25.5
    base = sy + 25.5
    slot_svg.append(f'''  <g id="Slot-{name}" data-name="Slot-{name}">
    <circle cx="{CX}" cy="{cy}" r="{RING_R}" fill="none" stroke="#FFFFFF" stroke-opacity="0.14" stroke-width="{STROKE}"/>
    <path id="Slot-{name}-Arc" d="{arc(CX, cy, RING_R, pct)}" fill="none" stroke="{arc_col}" stroke-width="{STROKE}" stroke-linecap="round"/>
    <rect id="Slot-{name}-Glyph" x="{CX-5.5}" y="{cy-5.5}" width="11" height="11" rx="3" fill="{tool_col}"/>
    <text id="Slot-{name}-Value" x="{CX}" y="{base+28:.1f}" font-family="{INTER}" font-size="12" font-weight="700" fill="#FFFFFF" text-anchor="middle" style="font-variant-numeric:tabular-nums">{pct}%</text>
  </g>''')

# ---------------- settings cog ----------------
COG_CY = RAIL_Y + RAIL_H + 31        # 558
teeth = []
for k in range(8):
    teeth.append(f'<rect x="{CX-1.5:.1f}" y="{COG_CY-8.6:.1f}" width="3" height="3.6" rx="1.2" fill="#FFFFFF" fill-opacity="0.62" transform="rotate({k*45} {CX} {COG_CY})"/>')
cog = "\n      ".join(teeth)

# ---------------- usage card ----------------
CARD_X, CARD_Y, CARD_W, CARD_H, CARD_R = 68, 245, 218, 162, 14
IX  = CARD_X + 11            # 85
IW  = CARD_W - 22            # 196
IR  = IX + IW                # 281
TAIL_CY = RAIL_Y + PAD + 25.5   # 326.5

def window(gid, label, pct, fill, used, resets, y):
    lab_base = y + 9
    bar_y    = y + 18
    txt_base = y + 36
    return f'''  <g id="{gid}" data-name="{gid}">
    <text x="{IX}" y="{lab_base}" font-family="{INTER}" font-size="11" font-weight="600" fill="#FFFFFF" fill-opacity="0.92">{label}</text>
    <rect x="{IX}" y="{bar_y}" width="{IW}" height="4" rx="2" fill="#FFFFFF" fill-opacity="0.16"/>
    <rect x="{IX}" y="{bar_y}" width="{IW*pct/100:.2f}" height="4" rx="2" fill="{fill}"/>
    <text x="{IX}" y="{txt_base}" font-family="{INTER}" font-size="10" font-weight="500" fill="#FFFFFF" fill-opacity="0.60" style="font-variant-numeric:tabular-nums">{used}</text>
    <text x="{IR}" y="{txt_base}" font-family="{INTER}" font-size="10" font-weight="500" fill="#FFFFFF" fill-opacity="0.60" text-anchor="end" style="font-variant-numeric:tabular-nums">{resets}</text>
  </g>'''

svg = f'''<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="{W}" height="{H}" viewBox="0 0 {W} {H}">
<defs>
  <clipPath id="screenClip"><rect x="0" y="0" width="{SW}" height="{SH}" rx="{R_SCREEN}"/></clipPath>
  <radialGradient id="spill" cx="0.5" cy="0.5" r="0.5">
    <stop offset="0" stop-color="#5B3BE8" stop-opacity="0.70"/>
    <stop offset="0.55" stop-color="#2B2FA8" stop-opacity="0.28"/>
    <stop offset="1" stop-color="#0B0D12" stop-opacity="0"/>
  </radialGradient>
  <linearGradient id="backdrop" x1="0" y1="0" x2="0.6" y2="1">
    <stop offset="0" stop-color="#12131A"/>
    <stop offset="0.55" stop-color="#0C0D13"/>
    <stop offset="1" stop-color="#07080C"/>
  </linearGradient>
  <linearGradient id="menuTint" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.14"/>
    <stop offset="1" stop-color="#FFFFFF" stop-opacity="0.05"/>
  </linearGradient>
  <linearGradient id="bezel" x1="0" y1="0" x2="0.4" y2="1">
    <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.55"/>
    <stop offset="0.5" stop-color="#FFFFFF" stop-opacity="0.10"/>
    <stop offset="1" stop-color="#FFFFFF" stop-opacity="0.28"/>
  </linearGradient>
  <radialGradient id="shadowCore" cx="0.5" cy="0.5" r="0.5">
    <stop offset="0"    stop-color="#000000" stop-opacity="0.92"/>
    <stop offset="0.42" stop-color="#000000" stop-opacity="0.80"/>
    <stop offset="0.66" stop-color="#000000" stop-opacity="0.42"/>
    <stop offset="0.85" stop-color="#000000" stop-opacity="0.13"/>
    <stop offset="1"    stop-color="#000000" stop-opacity="0"/>
  </radialGradient>
  <radialGradient id="shadowContact" cx="0.5" cy="0.5" r="0.5">
    <stop offset="0"    stop-color="#000000" stop-opacity="0.78"/>
    <stop offset="0.6"  stop-color="#000000" stop-opacity="0.30"/>
    <stop offset="1"    stop-color="#000000" stop-opacity="0"/>
  </radialGradient>
</defs>

<g id="Backdrop" data-name="Backdrop">
  <rect width="{W}" height="{H}" fill="url(#backdrop)"/>
  <ellipse cx="820" cy="440" rx="680" ry="500" fill="url(#spill)" transform="rotate({TILT} 820 440)"/>
</g>

<g id="Shadow" data-name="Shadow" transform="rotate({TILT} 700 460)">
  <ellipse cx="700" cy="460" rx="640" ry="580" fill="url(#shadowCore)"/>
  <ellipse cx="600" cy="840" rx="460" ry="240" fill="url(#shadowContact)" opacity="0.55"/>
</g>

<g id="Screen" data-name="Screen" transform="translate({ORIGIN_X},{ORIGIN_Y}) rotate({TILT}) scale({SCALE})">
  <g clip-path="url(#screenClip)">

    <image id="Wallpaper" data-name="Wallpaper" x="0" y="0" width="{SW}" height="{SH}" preserveAspectRatio="xMidYMid slice" xlink:href="data:image/jpeg;base64,{wp}"/>

    <g id="MenuBar" data-name="MenuBar">
      <rect x="0" y="0" width="{SW}" height="28" fill="url(#menuTint)"/>
      <rect x="1044" y="9" width="18" height="11" rx="3.5" fill="#FFFFFF" fill-opacity="0.78"/>
      <rect x="1070" y="9" width="13" height="11" rx="3.5" fill="#FFFFFF" fill-opacity="0.78"/>
      <text x="1206" y="18.5" font-family="{INTER}" font-size="12" font-weight="500" fill="#FFFFFF" text-anchor="end" style="font-variant-numeric:tabular-nums">Thu 27 Aug 11.22</text>
    </g>

    <g id="Rail" data-name="Rail">
      <path d="M 0 {RAIL_Y} H {RAIL_W-RAIL_R} A {RAIL_R} {RAIL_R} 0 0 1 {RAIL_W} {RAIL_Y+RAIL_R} V {RAIL_Y+RAIL_H-RAIL_R} A {RAIL_R} {RAIL_R} 0 0 1 {RAIL_W-RAIL_R} {RAIL_Y+RAIL_H} H 0 Z" fill="#000000"/>
    </g>

{chr(10).join(slot_svg)}

    <g id="SettingsButton" data-name="SettingsButton">
      <circle cx="{CX}" cy="{COG_CY}" r="17" fill="#000000"/>
      {cog}
      <circle cx="{CX}" cy="{COG_CY}" r="4.6" fill="none" stroke="#FFFFFF" stroke-opacity="0.62" stroke-width="2.1"/>
    </g>

    <g id="UsageCard" data-name="UsageCard">
      <path d="M {CARD_X} {TAIL_CY-9} L {CARD_X-12} {TAIL_CY} L {CARD_X} {TAIL_CY+9} Z" fill="#050506"/>
      <rect x="{CARD_X}" y="{CARD_Y}" width="{CARD_W}" height="{CARD_H}" rx="{CARD_R}" fill="#050506"/>

      <g id="Card-Header" data-name="Card-Header">
        <rect x="{IX}" y="257.5" width="11" height="11" rx="3" fill="#D97757"/>
        <text x="{IX+18}" y="267.5" font-family="{INTER}" font-size="13" font-weight="700" fill="#FFFFFF">Claude Usage</text>
      </g>

{window("Window-CurrentSession", "Current session", 73, "#FF5A1F", "73% Used", "Resets in 51 min", 281)}

{window("Window-AllModels", "All models", 7, "#00E58A", "7% Used", "Resets Thu 12:00 AM", 329)}

      <g id="Card-Provenance" data-name="Card-Provenance">
        <rect x="{IX}" y="377" width="{IW}" height="1" fill="#FFFFFF" fill-opacity="0.08"/>
        <text x="{IX}" y="394" font-family="{MONO}" font-size="9.5" font-weight="400" fill="#FFFFFF" fill-opacity="0.50">Live from Anthropic</text>
      </g>
    </g>

  </g>
  <rect x="0.5" y="0.5" width="{SW-1}" height="{SH-1}" rx="{R_SCREEN}" fill="none" stroke="url(#bezel)" stroke-width="1"/>
</g>
</svg>
'''
open(OUT,"w").write(svg)
print(f"wrote {OUT}  ({len(svg)//1024} KB)")

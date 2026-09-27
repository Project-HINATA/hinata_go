#!/usr/bin/env python3
"""Generate the StoreVisit Live Activity preview sheet.

Outputs (repo root):
  dynamic-island-preview.svg   vector source of truth
  dynamic-island-preview.png   rasterised with headless Chrome, if available

Geometry follows iPhone 17 Pro per Apple HIG: screen 393pt wide, Dynamic
Island 371pt wide, corner radius 44pt, lock-screen margin 14pt. The expanded
height budget is 84-160pt; every state below stays inside it.

Layout contract encoded here (from the 2026-09-27 sketch):
  * the camera is an avoidance zone INSIDE the island, at the top center
  * event details (name / minutes left / wall-clock time) sit UNDER the camera
  * the ring spans the camera band AND the event band on the left, and its
    bottom edge lines up with the bottom of the last event line
  * the bill amount sits at the top right, with supporting lines beneath it

Coordinate conventions: everything inside a mockup is written in points and
scaled by `pt()`; everything at canvas level (headers, captions, legend) is
written in canvas pixels and must NOT be scaled.

Usage:
  python3 tool/generate_live_activity_preview.py
"""

from __future__ import annotations

import math
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT_SVG = ROOT / "dynamic-island-preview.svg"
OUT_PNG = ROOT / "dynamic-island-preview.png"

S = 1.9  # canvas pixels per point


def pt(v: float) -> float:
    """Points -> canvas pixels."""
    return round(v * S, 2)


def px_font(v: float) -> float:
    """Point-sized type at canvas level."""
    return round(v * S, 1)


FONT = (
    "-apple-system,'SF Pro Text','SF Pro Display','PingFang SC',"
    "'Helvetica Neue',sans-serif"
)
MONO = "'SF Mono',ui-monospace,Menlo,monospace"

WALL_A, WALL_B = "#1b2036", "#2a2140"
ISLAND = "#000000"
CAMERA = "#08080b"
LOCK_CARD = "#14141a"
PRIMARY = "#ffffff"
SECONDARY = "#9a9aa2"
DIM = "#63636d"
RULE = "#ffffff"

GREEN = "#30D158"
BLUE = "#0A84FF"
ORANGE = "#FF9F0A"
GRAY = "#8E8E93"
# Colour is used for grouping, not decoration (HIG: strong colours emphasise
# relationships between elements). State accent covers the "now" cluster; a fixed
# amber marks the "how much headroom is left" cluster, independent of state.
AMBER = "#FFB020"
SHOP_NAME = "晴日游戏厅"

CANVAS_W, CANVAS_H = 1660.0, 2450.0
MARGIN = 80.0

ISLAND_W = 371.0
ISLAND_R = 44.0
CAM_W, CAM_H, CAM_TOP = 125.0, 37.0, 6.0
# HIG: keep a generous, uniform inset and never let content crowd the 44pt
# corner curve. The ring's TOP inset is forced equal to its LEFT inset.
MARGIN = 24.0
REV = "rev 15 · 2026-09-27"
CTR_X = 118.0
TRAIL_X = ISLAND_W - MARGIN
FOOT_X = MARGIN

out: list[str] = []


def esc(s: str) -> str:
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


# -------------------------------------------------------- point-space API --


def t(x, y, s, size, fill, anchor=None, weight=None, mono=False):
    a = f' text-anchor="{anchor}"' if anchor else ""
    w = f' font-weight="{weight}"' if weight else ""
    f = f' font-family="{MONO}"' if mono else ""
    return (
        f'<text x="{pt(x)}" y="{pt(y)}" font-size="{pt(size)}" fill="{fill}"'
        f'{a}{w}{f}>{esc(s)}</text>'
    )


def ring(cx, cy, d, frac, color, sw=7.0):
    """Progress ring: translucent track plus an accent dash from 12 o'clock."""
    x, y, dd, s = pt(cx), pt(cy), pt(d), pt(sw)
    r = dd / 2 - s / 2
    circ = 2 * math.pi * r
    return (
        f'<circle cx="{x}" cy="{y}" r="{r:.2f}" fill="none" stroke="#ffffff"'
        f' stroke-opacity="0.14" stroke-width="{s}"/>'
        f'<circle cx="{x}" cy="{y}" r="{r:.2f}" fill="none" stroke="{color}"'
        f' stroke-width="{s}" stroke-linecap="round"'
        f' stroke-dasharray="{circ * frac:.2f} {circ:.2f}"'
        f' transform="rotate(-90 {x} {y})"/>'
    )


def camera(region_w=ISLAND_W, top=CAM_TOP, h=CAM_H, annotate=False):
    """The sensor housing. On device it is invisible; here it is a very dark
    pill so the avoidance zone stays legible, outlined and labelled once."""
    x = (region_w - CAM_W) / 2
    rx = pt(h / 2)
    zone = (
        f'<rect x="{pt(x)}" y="{pt(top)}" width="{pt(CAM_W)}" height="{pt(h)}"'
        f' rx="{rx}" fill="{CAMERA}"/>'
    )
    if not annotate:
        return zone
    return (
        zone
        + f'<rect x="{pt(x)}" y="{pt(top)}" width="{pt(CAM_W)}" height="{pt(h)}"'
        f' rx="{rx}" fill="none" stroke="{RULE}" stroke-opacity="0.3"'
        f' stroke-width="1" stroke-dasharray="6 5"/>'
        + f'<line x1="{pt(region_w / 2)}" y1="{pt(top - 5)}"'
        f' x2="{pt(region_w / 2)}" y2="{pt(top - 1)}" stroke="{RULE}"'
        f' stroke-opacity="0.3" stroke-width="1"/>'
    )


def guide(x1, x2, y):
    return (
        f'<line x1="{pt(x1)}" y1="{pt(y)}" x2="{pt(x2)}" y2="{pt(y)}"'
        f' stroke="{RULE}" stroke-opacity="0.24" stroke-width="1"'
        f' stroke-dasharray="7 6"/>'
    )


def dim_h(x1, x2, y, label):
    """Horizontal dimension line with arrowheads at both ends."""
    return (
        f'<line x1="{pt(x1)}" y1="{pt(y)}" x2="{pt(x2)}" y2="{pt(y)}"'
        f' stroke="{RULE}" stroke-opacity="0.55" stroke-width="1"'
        f' marker-start="url(#dim)" marker-end="url(#dim)"/>'
        + t((x1 + x2) / 2, y - 4, label, 8, SECONDARY, anchor="middle")
    )


def dim_v(x, y1, y2, label):
    return (
        f'<line x1="{pt(x)}" y1="{pt(y1)}" x2="{pt(x)}" y2="{pt(y2)}"'
        f' stroke="{RULE}" stroke-opacity="0.55" stroke-width="1"'
        f' marker-start="url(#dim)" marker-end="url(#dim)"/>'
        + t(x + 5, y2 - 3, label, 8, SECONDARY)
    )


def tline_right(x, y, parts):
    """Right-aligned line whose spans may carry different sizes (priority)."""
    spans = []
    for i, (s, size, color, gap) in enumerate(parts):
        dx = f' dx="{pt(gap)}"' if i and gap else ""
        spans.append(
            f'<tspan{dx} font-size="{pt(size)}" fill="{color}">{esc(s)}</tspan>'
        )
    return f'<text x="{pt(x)}" y="{pt(y)}" text-anchor="end">' + "".join(spans) + "</text>"


def tline_center(x, y, parts, color):
    spans = "".join(
        f'<tspan font-size="{pt(sz)}" fill="{color}">{esc(txt)}</tspan>'
        for txt, sz in parts
    )
    return f'<text x="{pt(x)}" y="{pt(y)}" text-anchor="middle">{spans}</text>'


def glyph_line_right(x, y, groups, gap=18.0):
    """A right-aligned row of (glyph, text) groups, each glyph seating its text.

    `groups` is [(glyph_kind, text, size), ...]; the row's right edge lands on `x`.
    """
    widths = []
    total = 0.0
    for _, txt, size in groups:
        w = size * 1.1 + 5 + est_width(txt, size)
        widths.append(w)
        total += w
    total += gap * (len(groups) - 1)
    parts = []
    cursor = x - total
    for (kind, txt, size), w in zip(groups, widths):
        parts.append(glyph(kind, cursor + size * 0.55, y - size * 0.32,
                           size * 1.1, SECONDARY))
        parts.append(t(cursor + size * 1.1 + 5, y, txt, size, SECONDARY))
        cursor += w + gap
    return "".join(parts)


def resolve(color, st):
    """`"accent"` resolves to the state colour at draw time."""
    return st["accent"] if color == "accent" else color


def est_width(s, size):
    """Rough advance width in points, good enough to seat a glyph before text."""
    w = 0.0
    for ch in s:
        if ord(ch) > 0x2E80:
            w += size
        elif ch in " ·":
            w += size * 0.34
        elif ch in "0123456789:.–-":
            w += size * 0.57
        else:
            w += size * 0.55
    return w


def glyph(kind, cx, cy, s, color, frac=0.3):
    """Label glyphs that replace the Chinese words for elapsed / entry.

    `timer` stands in for 在场时间, `in` for 入店时间, `bar` for 距封顶 (a
    proportion bar beats any icon at conveying 'how much is left').
    """
    w = max(1.4, pt(s * 0.11))
    c = pt(cx), pt(cy), pt(s)
    X, Y, S = c
    if kind == "timer":
        r = S * 0.34
        return (
            f'<circle cx="{X}" cy="{Y + S * 0.05:.2f}" r="{r:.2f}" fill="none"'
            f' stroke="{color}" stroke-width="{w}"/>'
            f'<line x1="{X}" y1="{Y - S * 0.42:.2f}" x2="{X}"'
            f' y2="{Y - S * 0.2:.2f}" stroke="{color}" stroke-width="{w}"'
            f' stroke-linecap="round"/>'
            f'<line x1="{X}" y1="{Y + S * 0.05:.2f}" x2="{X + S * 0.17:.2f}"'
            f' y2="{Y - S * 0.11:.2f}" stroke="{color}" stroke-width="{w}"'
            f' stroke-linecap="round"/>'
        )
    if kind == "in":
        # Tracing of SF Symbols `figure.walk.arrival`: a wall/door edge with a
        # walking figure stepping into it. The app renders the real symbol; this
        # path only mirrors its shape for the spec sheet.
        bx = X - S * 0.30                      # wall line
        hx, hy, hr = X + 0.035 * S, Y - S * 0.295, S * 0.105
        neck = (hx - S * 0.005, hy + hr)
        hip = (X + 0.045 * S, Y + S * 0.055)
        stroke = (f'stroke="{color}" stroke-width="{w}" stroke-linecap="round"'
                  f' stroke-linejoin="round" fill="none"')
        return (
            f'<line x1="{bx:.2f}" y1="{Y - S * 0.46:.2f}" x2="{bx:.2f}"'
            f' y2="{Y + S * 0.46:.2f}" stroke="{color}"'
            f' stroke-width="{w * 0.85:.2f}" stroke-linecap="round"/>'
            f'<circle cx="{hx:.2f}" cy="{hy:.2f}" r="{hr:.2f}" fill="{color}"/>'
            f'<path d="M{neck[0]:.2f} {neck[1]:.2f} L{hip[0]:.2f} {hip[1]:.2f}" {stroke}/>'
            f'<path d="M{hip[0]:.2f} {hip[1]:.2f} L{X - S * 0.155:.2f} {Y + S * 0.43:.2f}" {stroke}/>'
            f'<path d="M{hip[0]:.2f} {hip[1]:.2f} L{X + S * 0.245:.2f} {Y + S * 0.43:.2f}" {stroke}/>'
            f'<path d="M{neck[0] + S * 0.01:.2f} {neck[1] + S * 0.075:.2f}'
            f' L{X - S * 0.145:.2f} {Y + S * 0.005:.2f}" {stroke}/>'
            f'<path d="M{neck[0] + S * 0.01:.2f} {neck[1] + S * 0.075:.2f}'
            f' L{X + S * 0.185:.2f} {Y - S * 0.055:.2f}" {stroke}/>'
        )

    # kind == "bar": `cy` is the vertical centre of the track.
    bw, bh = S * 1.05, pt(s * 0.4)
    track = (
        f'<rect x="{X - bw / 2:.2f}" y="{Y - bh / 2:.2f}" width="{bw:.2f}"'
        f' height="{bh:.2f}" rx="{bh / 2:.2f}" fill="#ffffff" fill-opacity="0.18"/>'
    )
    if frac <= 0:
        return track
    return track + (
        f'<rect x="{X - bw / 2:.2f}" y="{Y - bh / 2:.2f}" width="{bw * frac:.2f}"'
        f' height="{bh:.2f}" rx="{bh / 2:.2f}" fill="{color}"/>'
    )


def rounded(x, y, w, h, rx=None, fill=ISLAND):
    rx = h / 2 if rx is None else rx
    return (
        f'<rect x="{pt(x)}" y="{pt(y)}" width="{pt(w)}" height="{pt(h)}"'
        f' rx="{pt(rx)}" fill="{fill}"/>'
    )


# ------------------------------------------------------ canvas-space API ---


def ctext(x, y, s, size, fill, anchor=None, weight=None):
    a = f' text-anchor="{anchor}"' if anchor else ""
    w = f' font-weight="{weight}"' if weight else ""
    return (
        f'<text x="{x}" y="{y}" font-size="{px_font(size)}" fill="{fill}"'
        f'{a}{w}>{esc(s)}</text>'
    )


def caption(cx, y, s):
    out.append(ctext(cx, y, s, 10.5, DIM, anchor="middle"))


def lcaption(x, y, s):
    out.append(ctext(x, y, s, 10.5, DIM))


def section(y, label):
    out.append(ctext(MARGIN, y, label, 11, SECONDARY, weight="600"))
    out.append(
        f'<line x1="{MARGIN}" y1="{y + 14}" x2="{CANVAS_W - MARGIN}" y2="{y + 14}"'
        f' stroke="{RULE}" stroke-opacity="0.12" stroke-width="1"/>'
    )


# ---------------------------------------------------------- presentations ---


def expanded(x, y, st):
    h = st["h"]
    g = [f'<g transform="translate({x},{y})">']
    g.append(rounded(0, 0, ISLAND_W, h, rx=ISLAND_R))
    g.append(camera(ISLAND_W, st.get("cam_top", CAM_TOP),
                    annotate=st.get("annotate", False)))
    if st.get("annotate"):
        top = st.get("cam_top", CAM_TOP)
        g.append(
            f'<line x1="{pt(ISLAND_W / 2)}" y1="{pt(-3)}" x2="{pt(ISLAND_W / 2)}"'
            f' y2="{pt(top)}" stroke="{RULE}" stroke-opacity="0.3" stroke-width="1"'
            f' stroke-dasharray="4 4"/>'
        )
        g.append(t(ISLAND_W / 2, -5, "摄像头避让区（内容绕排）", 9, DIM, anchor="middle"))
    g.append(ring(st.get("ring_cx", MARGIN + st["ring_d"] / 2), st["ring_cy"],
                  st["ring_d"], st["ring_frac"], st["accent"]))
    if st.get("ring_label"):
        rcx = st.get("ring_cx", MARGIN + st["ring_d"] / 2)
        top = max(sz for _, sz in st["ring_label"])
        g.append(tline_center(rcx, st["ring_cy"] + top * 0.36, st["ring_label"],
                              st["accent"]))
    if st.get("pad_dims"):
        rcx = st.get("ring_cx", MARGIN + st["ring_d"] / 2)
        g.append(dim_h(0, MARGIN, st["ring_cy"], f"{MARGIN:g}"))
        g.append(dim_v(rcx, 0, MARGIN, f"{MARGIN:g}"))
        g.append(dim_h(TRAIL_X, ISLAND_W, MARGIN, f"{MARGIN:g}"))
        g.append(dim_v(TRAIL_X - 26, 0, MARGIN, f"{MARGIN:g}"))
    if st.get("align_guide"):
        g.append(guide(MARGIN, CTR_X + 108, st["ring_cy"] + st["ring_d"] / 2))
    for line in st["center"]:
        g.append(t(CTR_X, line["y"], line["t"], line["s"], resolve(line["c"], st),
                   weight=line.get("w")))
    for line in st["trail"]:
        if line.get("parts"):
            g.append(tline_right(TRAIL_X, line["y"], line["parts"]))
            continue
        color = resolve(line["c"], st)
        if line.get("glyph"):
            size = line["s"]
            gx = TRAIL_X - est_width(line["t"], size) - 5 - size / 2
            g.append(glyph(line["glyph"], gx, line["y"] - size * 0.32, size * 1.1,
                           color, frac=st.get("bar", 0.3)))
        g.append(t(TRAIL_X, line["y"], line["t"], line["s"], color,
                   anchor="end", weight=line.get("w")))
    if st.get("low"):
        y, groups = st["low"]
        g.append(glyph_line_right(TRAIL_X, y, groups))
    if st.get("shop"):
        # Shop name anchored to the bottom-left inset: its bottom edge sits 24pt
        # off the left edge and 24pt off the island's bottom.
        g.append(t(FOOT_X, st["shop"], SHOP_NAME, 17, SECONDARY))

    g.append("</g>")
    out.append("".join(g))


STATES = [
    # Two bands. The upper band hugs the camera (ring | event | amount) and all
    # three columns bottom out on the same line; the lower band is one footer row.
    # Heights sit inside Apple's 84-160pt budget; the full billing state uses the
    # whole 160pt so the island keeps the standard 371x160 (2.3:1) proportion.
    dict(
        h=160.0, accent=GREEN, ring_frac=0.72, ring_cx=62.5, ring_cy=62.5, ring_d=77.0,
        cam_top=6.0, align_guide=True, annotate=True, pad_dims=True, bar=0.28,
        ring_label=[("24:37", 18)],
        center=[
            dict(y=62, t="下次计费", s=18, c=SECONDARY),
            dict(y=98, t="13:24", s=24, c="accent", w=600),
        ],
        trail=[
            dict(y=52, parts=[("计价", 20, SECONDARY, 0), ("60", 40, PRIMARY, 9)]),
            dict(y=98, glyph="bar", t="27.50", s=17, c=AMBER),
        ],
        low=(132.0, [("in", "11:55", 15), ("timer", "1小时23分", 17)]),
        shop=132,
        cap="扩展式 · 计费中（371×160pt，比例 2.3:1，用满 HIG 高度上限）",
    ),
    dict(
        h=160.0, accent=GREEN, ring_frac=1.0, ring_cx=62.5, ring_cy=62.5, ring_d=77.0,
        cam_top=6.0, bar=0.0,
        ring_label=[("58:12", 18)],
        center=[
            dict(y=62, t="规则切换", s=18, c=SECONDARY),
            dict(y=98, t="14:15", s=24, c="accent", w=600),
        ],
        trail=[
            dict(y=52, parts=[("计价", 20, SECONDARY, 0), ("45", 40, PRIMARY, 9)]),
            dict(y=98, glyph="bar", t="已达上限", s=17, c=AMBER),
        ],
        low=(132.0, [("in", "10:15", 15), ("timer", "3小时02分", 17)]),
        shop=132,
        cap="扩展式 · 已封顶（环满且刻度条空，环心改显示距规则切换）",
    ),
    dict(
        h=160.0, accent=BLUE, ring_frac=0.45, ring_cx=62.5, ring_cy=62.5, ring_d=77.0,
        cam_top=6.0, bar=0.45,
        ring_label=[("11:08", 18)],
        center=[
            dict(y=62, t="恢复计费", s=18, c=SECONDARY),
            dict(y=98, t="15:00", s=24, c="accent", w=600),
        ],
        trail=[
            dict(y=52, parts=[("计价", 20, SECONDARY, 0), ("38", 40, PRIMARY, 9)]),
            dict(y=98, glyph="bar", t="非营业时段", s=17, c=AMBER),
        ],
        low=(132.0, [("in", "09:46", 15), ("timer", "5小时03分", 17)]),
        shop=132,
        cap="扩展式 · 暂停中（非营业时段，金额冻结）",
    ),
    dict(
        h=148.0, accent=ORANGE, ring_frac=1.0, ring_cx=58.5, ring_cy=58.5, ring_d=69.0,
        cam_top=6.0, bar=0.0,
        ring_label=[("待付", 17)],
        center=[
            dict(y=58, t="待支付", s=18, c=SECONDARY),
            dict(y=90, t="已完成计费", s=22, c=PRIMARY, w=600),
        ],
        trail=[
            dict(y=49, parts=[("应付", 18, SECONDARY, 0), ("45", 36, PRIMARY, 9)]),
            dict(y=90, t="已结束计费", s=17, c=SECONDARY),
        ],
        low=(118.0, [("in", "11:54", 15), ("timer", "2小时23分", 17)]),
        shop=118,
        cap="扩展式 · 待结账（高度收缩到 148pt）",
    ),
    dict(
        h=136.0, accent=GRAY, ring_frac=1.0, ring_cx=54.5, ring_cy=54.5, ring_d=61.0,
        cam_top=6.0, bar=0.0,
        ring_label=[("已付", 17)],
        center=[
            dict(y=56, t="已结算", s=17, c=SECONDARY),
            dict(y=82, t="已完成计费", s=22, c=PRIMARY, w=600),
        ],
        trail=[
            dict(y=48, parts=[("结算", 17, SECONDARY, 0), ("45", 34, PRIMARY, 9)]),
            dict(y=82, t="已结束计费", s=17, c=SECONDARY),
        ],
        low=(106.0, [("in", "11:54", 15), ("timer", "2小时23分", 17)]),
        shop=106,
        cap="扩展式 · 已结算（高度收到 136pt，60 秒后收起）",
    ),
]


def compact(x, y, accent, frac, amount):
    """The ring sits concentric with the capsule's end cap: its centre matches
    the cap centre, so it keeps an identical inset on the left, top and bottom."""
    h = 36.67
    cap = h / 2
    g = [f'<g transform="translate({x},{y})">']
    g.append(rounded(0, 0, 230.0, h))
    g.append(camera(230.0, 0.0, h))
    g.append(ring(cap, cap, 22.0, frac, accent, sw=3.0))
    g.append(t(216.0, cap + 5.2, amount, 15, accent, anchor="end", weight=600))
    g.append("</g>")
    out.append("".join(g))


COMPACTS = [
    (GREEN, 0.72, "60", "紧凑式 · 计费中（状态环 | 金额，两极同色）"),
    (ORANGE, 1.0, "45", "紧凑式 · 待结账"),
    (BLUE, 0.45, "38", "紧凑式 · 暂停中"),
    (GRAY, 1.0, "45", "紧凑式 · 已结算"),
]


def minimal(cx, cy, accent, value):
    """`cx` / `cy` are canvas pixels; the contents are point-space."""
    d = 36.67
    r = pt(d / 2)
    out.append(
        f'<g transform="translate({round(cx - r, 2)},{round(cy - r, 2)})">'
        f'<circle cx="{r}" cy="{r}" r="{r}" fill="{ISLAND}"/>'
        f'{t(d / 2, d / 2 + 5.2, value, 15, accent, anchor="middle", weight=600)}'
        f"</g>"
    )


def lock_screen(x, y, accent, frac):
    """Same grid and the same concentric inset as the expanded island."""
    h = 160.0
    m = MARGIN
    g = [f'<g transform="translate({x},{y})">']
    g.append(rounded(0, 0, ISLAND_W, h, rx=38, fill=LOCK_CARD))
    g.append(ring(m + 38.5, 62.5, 77.0, frac, accent))
    g.append(tline_center(m + 38.5, 62.5 + 18 * 0.36, [("24:37", 18)], accent))
    for line in [
        dict(y=62, t="下次计费", s=18, c=SECONDARY),
        dict(y=98, t="13:24", s=24, c=accent, w=600),
    ]:
        g.append(t(CTR_X, line["y"], line["t"], line["s"], line["c"], weight=line.get("w")))
    g.append(tline_right(ISLAND_W - m, 52,
                         [("计价", 20, SECONDARY, 0), ("60", 40, PRIMARY, 9)]))
    for line in [dict(y=98, glyph="bar", t="27.50", s=17)]:
        size = line["s"]
        gx = ISLAND_W - m - est_width(line["t"], size) - 5 - size / 2
        g.append(glyph(line["glyph"], gx, line["y"] - size * 0.32, size * 1.1, AMBER))
        g.append(t(ISLAND_W - m, line["y"], line["t"], size, AMBER, anchor="end"))
    g.append(glyph_line_right(ISLAND_W - m, 132.0,
                              [("in", "11:55", 15), ("timer", "1小时23分", 17)]))
    g.append(t(m, 132.0, SHOP_NAME, 17, SECONDARY))
    g.append("</g>")
    out.append("".join(g))


# ------------------------------------------------------------------ build --

COL1, COL2 = MARGIN, 880.0
CW = pt(ISLAND_W)

out.append(
    f'<svg xmlns="http://www.w3.org/2000/svg" width="{CANVAS_W}" height="{CANVAS_H}"'
    f' viewBox="0 0 {CANVAS_W} {CANVAS_H}" font-family="{FONT}">'
)
out.append(
    '<defs><linearGradient id="wall" x1="0" y1="0" x2="1" y2="1">'
    f'<stop offset="0" stop-color="{WALL_A}"/><stop offset="1" stop-color="{WALL_B}"/>'
    '</linearGradient>'
    '<marker id="dim" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="5"'
    ' markerHeight="5" orient="auto-start-reverse">'
    '<path d="M2 1L8 5L2 9" fill="none" stroke="context-stroke" stroke-width="1.6"'
    ' stroke-linecap="round" stroke-linejoin="round"/></marker></defs>'
)
out.append(f'<rect width="{CANVAS_W}" height="{CANVAS_H}" fill="url(#wall)"/>')

out.append(ctext(MARGIN, 58, "StoreVisit 实时活动 · 设计规范", 19, PRIMARY, weight="600"))
out.append(ctext(
    MARGIN, 84,
    "iPhone 17 Pro 几何 · 岛宽 371pt · 圆角 44pt · 摄像头避让区 125×37pt · 四边同心边距 24pt",
    11, SECONDARY,
))
out.append(ctext(
    MARGIN, 106,
    "环 上边距 = 左边距 · 金额 上边距 = 右边距 · 剩余分钟嵌在环心 · 事件信息贴环"
    " · 色彩按信息分组（状态色 / 额度琥珀）",
    11, SECONDARY,
))
out.append(ctext(
    MARGIN, 128,
    "扩展式高度 136–160pt（HIG 规范 84–160pt）；计费中态用满 160pt，"
    "即标准展开尺寸 371×160pt，比例 2.3:1",
    11, SECONDARY,
))
out.append(ctext(1500, 58, REV, 11, DIM, anchor="end"))

section(160, "扩展式 EXPANDED")
expanded(COL1, 205, STATES[0])
caption(COL1 + CW / 2, 552, STATES[0]["cap"])
expanded(COL2, 205, STATES[1])
caption(COL2 + CW / 2, 552, STATES[1]["cap"])
expanded(COL1, 600, STATES[2])
caption(COL1 + CW / 2, 947, STATES[2]["cap"])
expanded(COL2, 600, STATES[3])
caption(COL2 + CW / 2, 947, STATES[3]["cap"])
expanded(COL1, 995, STATES[4])
caption(COL1 + CW / 2, 1292, STATES[4]["cap"])

section(1345, "紧凑式 COMPACT")
compact(COL1, 1390, *COMPACTS[0][:3])
caption(COL1 + pt(115), 1505, COMPACTS[0][3])
compact(COL2, 1390, *COMPACTS[1][:3])
caption(COL2 + pt(115), 1505, COMPACTS[1][3])
compact(COL1, 1535, *COMPACTS[2][:3])
caption(COL1 + pt(115), 1650, COMPACTS[2][3])
compact(COL2, 1535, *COMPACTS[3][:3])
caption(COL2 + pt(115), 1650, COMPACTS[3][3])

section(1695, "极简式 MINIMAL")
minimal(COL1 + pt(18.3), 1760, GREEN, "60")
minimal(COL1 + pt(18.3) + pt(74), 1760, ORANGE, "45")
lcaption(MARGIN, 1832, "极简式 · 用金额替代静态图标（左：计费中 60 / 右：待结账 45）")

section(1878, "锁屏 LOCK SCREEN")
lock_screen(COL1, 1922, GREEN, 0.72)
caption(COL1 + CW / 2, 2268, "锁屏 · 计费中（同一套 24pt 栅格，与扩展式完全对齐）")

legend_y = 2315
out.append(ctext(
    MARGIN, legend_y,
    "色彩按信息分组（HIG：用醒目的颜色强调元素之间的关系）· 状态色 → 环 / 环心分钟 / 事件时刻 / 关键线"
    " · 琥珀 → 额度条与距封顶 · 其余一律 primary / secondary", 11, SECONDARY,
))
for i, (color, name) in enumerate(
    [(GREEN, "计费中 #30D158"), (BLUE, "暂停中 #0A84FF"), (ORANGE, "待结账 #FF9F0A"),
     (GRAY, "已结算 #8E8E93"), (AMBER, "额度 #FFB020")]
):
    x = MARGIN + i * 210
    y = legend_y + 24
    out.append(f'<rect x="{x}" y="{y - 11}" width="14" height="14" rx="3" fill="{color}"/>')
    out.append(ctext(x + 22, y, name, 11, SECONDARY))
out.append(ctext(
    MARGIN, legend_y + 50,
    "图形语义 · 在场 = timer · 入店 = figure.walk.arrival · 距封顶 = 刻度条（用比例而非文字表达）"
    " · 数值为 dummy 数据",
    11, SECONDARY,
))
out.append(ctext(
    MARGIN, legend_y + 76,
    "字号 · 金额 34–40pt / 事件时刻 22–24pt / 环心计时 18pt / 计价标签 17–20pt"
    " / 事件名称 17–18pt / 在场与店名 17pt / 距封顶与入店 15–17pt",
    11, SECONDARY,
))
out.append("</svg>")

svg = "".join(out)
OUT_SVG.write_text(svg, encoding="utf-8")
print(f"wrote {OUT_SVG.relative_to(ROOT)} ({len(svg)} bytes)")

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
if Path(CHROME).exists():
    # Headless Chrome writes the screenshot but never exits on macOS, so poll
    # for the file and then terminate it instead of waiting on the process.
    tmp_svg = Path("/tmp/wb-live-activity-preview.svg")
    tmp_png = Path("/tmp/wb-live-activity-preview.png")
    tmp_svg.write_text(svg, encoding="utf-8")
    tmp_png.unlink(missing_ok=True)
    proc = subprocess.Popen(
        [
            CHROME, "--headless=new", "--no-sandbox", "--disable-gpu",
            "--hide-scrollbars", "--user-data-dir=/tmp/wb-chrome-preview",
            "--force-device-scale-factor=1.5",
            f"--window-size={int(CANVAS_W)},{int(CANVAS_H)}",
            f"--screenshot={tmp_png}", tmp_svg.as_uri(),
        ],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    deadline = time.time() + 120
    while time.time() < deadline and not tmp_png.exists():
        time.sleep(0.4)
    time.sleep(1.0)
    proc.terminate()
    try:
        proc.wait(timeout=10)
    except subprocess.TimeoutExpired:
        proc.kill()
    if tmp_png.exists():
        OUT_PNG.write_bytes(tmp_png.read_bytes())
        print(f"wrote {OUT_PNG.relative_to(ROOT)}")
    else:
        print("Chrome produced no screenshot; SVG only")
else:
    print("no Chrome found; SVG only")

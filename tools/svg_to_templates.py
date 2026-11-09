#!/usr/bin/env python3
"""Converts Origami Simulator example crease patterns (MIT, Amanda Ghassaei) into PaperVerse template files.

Origami Simulator SVG conventions: red = mountain, blue = valley, black = boundary, yellow = facet (flat),
green = cut, stroke opacity = fold angle as a fraction of 180 degrees.

python tools/svg_to_templates.py <OrigamiSimulator/assets> apps/paperverse/templates
Each output JSON holds an OVCreasePattern dict: {"outline": [[x, y], ...], "segments": [[x1, y1, x2, y2, A, deg], ...]}
in FOLD coordinates (unit square, y up).
"""
import json
import math
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

SELECTION = {
    # file: (id, title, description, suggested fold percent)
    "SimpleFolds/simpleVertex.svg": ("simple_vertex", "Single Vertex", "Four creases meeting at one point: the atom of origami.", 0.9),
    "SimpleFolds/mapfold.svg": ("map_fold", "Map Fold", "Accordion pleats in two directions.", 0.95),
    "Bases/waterbombBase.svg": ("waterbomb_base", "Waterbomb Base", "Traditional base for balloons and frogs.", 0.95),
    "Bases/squareBase.svg": ("square_base", "Square Base", "The preliminary fold that starts the crane.", 0.95),
    "Bases/birdBase.svg": ("bird_base", "Bird Base", "Petal folds on a square base: the crane's skeleton.", 0.95),
    "Bases/pinwheelBase.svg": ("pinwheel_base", "Pinwheel", "Four flaps spinning around a square.", 0.95),
    "Bases/frogBase.svg": ("frog_base", "Frog Base", "A dense base with sixteen points.", 0.9),
    "SimpleFolds/brochurefold.svg": ("brochure", "Brochure Fold", "Two parallel folds, like a letter in an envelope.", 0.95),
    "Origami/singlesquaretwist.svg": ("square_twist", "Square Twist", "A twist fold that rotates the center square.", 0.85),
}

COLORS = {
    "ff0000": "M", "0000ff": "V", "000000": "B", "ffff00": "F", "00ff00": "C",
}


def color_of(el, style):
    c = el.get("stroke") or style.get("stroke")
    if not c:
        return None
    c = c.strip().lower().lstrip("#")
    if len(c) == 3:
        c = "".join(ch * 2 for ch in c)
    return COLORS.get(c)


def parse_style(el):
    out = {}
    for part in (el.get("style") or "").split(";"):
        if ":" in part:
            k, v = part.split(":", 1)
            out[k.strip()] = v.strip()
    return out


def opacity_of(el, style):
    for key in ("opacity", "stroke-opacity"):
        v = el.get(key) or style.get(key)
        if v is not None:
            return float(v)
    return 1.0


def path_points(d):
    """Supports the absolute/relative M, L, H, V, Z commands used by the example files."""
    toks = re.findall(r"[MLHVZmlhvz]|-?\d*\.?\d+(?:e-?\d+)?", d)
    pts, cur, start, cmd, i = [], (0.0, 0.0), (0.0, 0.0), "M", 0
    polylines = []
    while i < len(toks):
        t = toks[i]
        if re.match(r"[MLHVZmlhvz]", t):
            cmd = t
            i += 1
            if cmd in "Zz":
                if pts:
                    pts.append(start)
                    polylines.append(pts)
                    pts = []
                cur = start
            continue
        if cmd in "Mm":
            x, y = float(toks[i]), float(toks[i + 1])
            i += 2
            cur = (cur[0] + x, cur[1] + y) if cmd == "m" else (x, y)
            if pts:
                polylines.append(pts)
            pts = [cur]
            start = cur
            cmd = "l" if cmd == "m" else "L"
        elif cmd in "Ll":
            x, y = float(toks[i]), float(toks[i + 1])
            i += 2
            cur = (cur[0] + x, cur[1] + y) if cmd == "l" else (x, y)
            pts.append(cur)
        elif cmd in "Hh":
            x = float(toks[i])
            i += 1
            cur = (cur[0] + x, cur[1]) if cmd == "h" else (x, cur[1])
            pts.append(cur)
        elif cmd in "Vv":
            y = float(toks[i])
            i += 1
            cur = (cur[0], cur[1] + y) if cmd == "v" else (cur[0], y)
            pts.append(cur)
        else:
            i += 1
    if pts:
        polylines.append(pts)
    return polylines


def convert(svg_path):
    root = ET.parse(svg_path).getroot()
    segs = []
    for el in root.iter():
        tag = el.tag.split("}")[-1]
        style = parse_style(el)
        a = color_of(el, style)
        if a is None:
            continue
        op = opacity_of(el, style)
        lines = []
        if tag == "line":
            lines.append(((float(el.get("x1", 0)), float(el.get("y1", 0))), (float(el.get("x2", 0)), float(el.get("y2", 0)))))
        elif tag == "rect":
            x, y = float(el.get("x", 0)), float(el.get("y", 0))
            w, h = float(el.get("width")), float(el.get("height"))
            pts = [(x, y), (x + w, y), (x + w, y + h), (x, y + h), (x, y)]
            lines += list(zip(pts, pts[1:]))
        elif tag in ("polyline", "polygon"):
            nums = [float(n) for n in re.findall(r"-?\d*\.?\d+(?:e-?\d+)?", el.get("points", ""))]
            pts = list(zip(nums[0::2], nums[1::2]))
            if tag == "polygon" and pts:
                pts.append(pts[0])
            lines += list(zip(pts, pts[1:]))
        elif tag == "path":
            for pl in path_points(el.get("d", "")):
                lines += list(zip(pl, pl[1:]))
        for p, q in lines:
            if math.dist(p, q) > 1e-6:
                segs.append((p, q, a, op))
    xs = [c for s in segs for c in (s[0][0], s[1][0])]
    ys = [c for s in segs for c in (s[0][1], s[1][1])]
    minx, maxx, miny, maxy = min(xs), max(xs), min(ys), max(ys)
    size = max(maxx - minx, maxy - miny)

    def norm(p):
        # SVG y points down; FOLD y points up.
        return (round((p[0] - minx) / size, 6), round((maxy - p[1]) / size, 6))

    boundary = [(norm(p), norm(q)) for p, q, a, _ in segs if a == "B"]
    outline = order_loop(boundary)
    out_segs = []
    for p, q, a, op in segs:
        if a == "B":
            continue
        angle = 0.0
        if a == "M":
            angle = -180.0 * op
        elif a == "V":
            angle = 180.0 * op
        P, Q = norm(p), norm(q)
        out_segs.append([P[0], P[1], Q[0], Q[1], a, round(angle, 3)])
    return outline, out_segs


def order_loop(edges):
    if not edges:
        return [[0, 0], [1, 0], [1, 1], [0, 1]]

    def key(p):
        return (round(p[0], 3), round(p[1], 3))

    adj, pos = {}, {}
    for p, q in edges:
        kp, kq = key(p), key(q)
        if kp == kq:
            continue
        pos.setdefault(kp, p)
        pos.setdefault(kq, q)
        adj.setdefault(kp, set()).add(kq)
        adj.setdefault(kq, set()).add(kp)
    start = min(adj)
    loop, prev, cur = [start], None, start
    for _ in range(len(adj) + 1):
        nxt = [n for n in adj[cur] if n != prev]
        if not nxt:
            break
        if prev is None:
            nxt = sorted(nxt)[:1]
        if nxt[0] == start:
            break
        prev, cur = cur, nxt[0]
        loop.append(cur)
    loop = [pos[k] for k in loop]
    # Drop collinear points, enforce CCW.
    area = sum(loop[i][0] * loop[(i + 1) % len(loop)][1] - loop[(i + 1) % len(loop)][0] * loop[i][1] for i in range(len(loop)))
    if area < 0:
        loop.reverse()
    simple = []
    n = len(loop)
    for i in range(n):
        a, b, c = loop[i - 1], loop[i], loop[(i + 1) % n]
        if abs((b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0])) > 1e-9:
            simple.append([b[0], b[1]])
    return simple


def main():
    src, dst = Path(sys.argv[1]), Path(sys.argv[2])
    dst.mkdir(parents=True, exist_ok=True)
    index = []
    for rel, (tid, title, desc, pct) in SELECTION.items():
        outline, segs = convert(src / rel)
        data = {
            "id": tid, "title": title, "description": desc, "fold_percent": pct,
            "source": "Origami Simulator examples by Amanda Ghassaei (MIT License): " + rel,
            "pattern": {"outline": outline, "segments": segs},
        }
        (dst / f"{tid}.json").write_text(json.dumps(data, indent=1))
        counts = {}
        for s in segs:
            counts[s[4]] = counts.get(s[4], 0) + 1
        print(f"{tid:20s} outline={len(outline)} segments={len(segs)} {counts}")
        index.append(tid)
    (dst / "index.json").write_text(json.dumps(index))


if __name__ == "__main__":
    main()

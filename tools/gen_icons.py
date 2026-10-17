"""Генератор иконок ImpoMento для веба и приложения.

Запуск: python tools/gen_icons.py
Пишет:
  guest-pwa/src/app/iconData.ts              пути для веба
  host-app/lib/core/widgets/brand_icon_data.dart   те же фирменные и линейные иконки + таблица оптического выравнивания Material

Что делает:
1. Фирменные иконки (искра, кольцо объектива, квадрат бренда) и единый набор линейных иконок
   на сетке 24, обводка 1.8, скругления круглые, один оптический размер.
2. Material-глифы берутся из шрифта Flutter и приводятся к одному оптическому размеру
   (самая длинная сторона 19 из 24), иначе «скачать» выглядит мельче «настроек».
"""
import json
import math
import re
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")
ROOT = Path(__file__).resolve().parent.parent
FLUTTER = Path("D:/dev/flutter")
K = 0.5523
TARGET = 19.0  # длинная сторона Material-глифа в сетке 24


def f(v):
    s = ("%.2f" % v).rstrip("0").rstrip(".")
    return s if s not in ("-0", "") else "0"


def rrect(x1, y1, x2, y2, r):
    return (f"M{f(x1+r)} {f(y1)}H{f(x2-r)}Q{f(x2)} {f(y1)} {f(x2)} {f(y1+r)}V{f(y2-r)}"
            f"Q{f(x2)} {f(y2)} {f(x2-r)} {f(y2)}H{f(x1+r)}Q{f(x1)} {f(y2)} {f(x1)} {f(y2-r)}"
            f"V{f(y1+r)}Q{f(x1)} {f(y1)} {f(x1+r)} {f(y1)}Z")


def circle(cx, cy, r):
    k = K * r
    return (f"M{f(cx)} {f(cy-r)}C{f(cx+k)} {f(cy-r)} {f(cx+r)} {f(cy-k)} {f(cx+r)} {f(cy)}"
            f"C{f(cx+r)} {f(cy+k)} {f(cx+k)} {f(cy+r)} {f(cx)} {f(cy+r)}"
            f"C{f(cx-k)} {f(cy+r)} {f(cx-r)} {f(cy+k)} {f(cx-r)} {f(cy)}"
            f"C{f(cx-r)} {f(cy-k)} {f(cx-k)} {f(cy-r)} {f(cx)} {f(cy-r)}Z")


def spark(cx, cy, r, k=0.2):
    a = k * r
    return (f"M{f(cx)} {f(cy-r)}Q{f(cx+a)} {f(cy-a)} {f(cx+r)} {f(cy)}"
            f"Q{f(cx+a)} {f(cy+a)} {f(cx)} {f(cy+r)}"
            f"Q{f(cx-a)} {f(cy+a)} {f(cx-r)} {f(cy)}"
            f"Q{f(cx-a)} {f(cy-a)} {f(cx)} {f(cy-r)}Z")


def arc(cx, cy, r, a0, a1, move=True):
    """Дуга окружности кубическими кривыми. Углы в градусах, по часовой стрелке (ось y вниз)."""
    n = max(1, math.ceil(abs(a1 - a0) / 90))
    step = math.radians((a1 - a0) / n)
    out = []
    t = math.radians(a0)
    p0 = (cx + r * math.cos(t), cy + r * math.sin(t))
    if move:
        out.append(f"M{f(p0[0])} {f(p0[1])}")
    for _ in range(n):
        t1 = t + step
        k = 4 / 3 * math.tan((t1 - t) / 4)
        c1 = (cx + r * (math.cos(t) - k * math.sin(t)), cy + r * (math.sin(t) + k * math.cos(t)))
        c2 = (cx + r * (math.cos(t1) + k * math.sin(t1)), cy + r * (math.sin(t1) - k * math.cos(t1)))
        p1 = (cx + r * math.cos(t1), cy + r * math.sin(t1))
        out.append(f"C{f(c1[0])} {f(c1[1])} {f(c2[0])} {f(c2[1])} {f(p1[0])} {f(p1[1])}")
        t = t1
    return "".join(out)


def arrow_head(px, py, tx, ty, size=3.4, spread=38):
    """Наконечник стрелки в точке (px,py), направление движения (tx,ty)."""
    ang = math.atan2(ty, tx)
    a1 = ang + math.pi - math.radians(spread)
    a2 = ang + math.pi + math.radians(spread)
    return (f"M{f(px + size*math.cos(a1))} {f(py + size*math.sin(a1))}L{f(px)} {f(py)}"
            f"L{f(px + size*math.cos(a2))} {f(py + size*math.sin(a2))}")


# ---------- Фирменные иконки ----------
brand = {
    "event": [
        ("stroke", rrect(3.5, 3.5, 20.5, 20.5, 6.2)),
        ("accent", spark(12, 10.4, 4.6)),
        ("ink", circle(8.3, 16.6, 1.05) + circle(12, 16.6, 1.05) + circle(15.7, 16.6, 1.05)),
    ],
    "solo": [
        ("stroke", circle(12, 12, 8.8)),
        ("soft", circle(12, 12, 5.9)),
        ("accent", spark(12, 12, 4.3)),
    ],
    "mini": [
        ("stroke", rrect(3.2, 9.2, 16.2, 21.2, 3.2)),
        ("stroke", "M6.6 6.3V6.2Q6.6 3.6 9.2 3.6H16.6Q19.2 3.6 19.2 6.2V13.2Q19.2 15.8 16.6 15.8"),
        ("accent", spark(9.7, 15.2, 3.3)),
    ],
    "cover": [
        ("stroke", rrect(2.8, 3.8, 21.2, 20.4, 4.8)),
        ("accent", circle(10.4, 10.2, 2.6)),
        ("stroke", "M5.6 17.4C6.4 14.4 8.2 13.4 10.4 13.4C12.6 13.4 14.4 14.4 15.2 17.4"),
        ("accent", spark(17.6, 7.4, 2.7)),
    ],
    "gallery": [
        ("stroke", rrect(2.8, 3.8, 21.2, 20.4, 4.8)),
        ("accent", circle(12, 10.2, 2.9)),
        ("stroke", "M6.4 18.2C7.2 14.8 9.4 13.6 12 13.6C14.6 13.6 16.8 14.8 17.6 18.2"),
    ],
    # «Плюс»: значок-квадрат бренда с белой искрой и плюсом в углу.
    "plus": [
        ("badge", rrect(2.5, 2.5, 21.5, 21.5, 6.6)),
        ("white", spark(10.9, 13.1, 5.9, 0.2)),
        ("whiteStroke", "M18.3 5.4V9.4M16.3 7.4H20.3"),
    ],
}

# ---------- Единый набор линейных иконок (сетка 24, обводка 1.8) ----------
line = {
    "download": [("stroke", "M12 3.5V14.5M7.4 10.2L12 14.8L16.6 10.2M3.8 15.5V18.2Q3.8 20.3 5.9 20.3H18.1Q20.2 20.3 20.2 18.2V15.5")],
    "share": [("stroke", "M12 3.5V14.2M7.9 7.6L12 3.5L16.1 7.6M8.2 10.2H6.6Q4.4 10.2 4.4 12.4V18.1Q4.4 20.3 6.6 20.3H17.4Q19.6 20.3 19.6 18.1V12.4Q19.6 10.2 17.4 10.2H15.8")],
    "rotate": [("stroke", arc(12, 12.4, 7.6, 130, 395) + arrow_head(
        12 + 7.6 * math.cos(math.radians(395)), 12.4 + 7.6 * math.sin(math.radians(395)),
        -math.sin(math.radians(395)), math.cos(math.radians(395)), size=3.6))],
    "trash": [("stroke", "M4.3 7H19.7M9.4 7V5.3Q9.4 3.9 10.8 3.9H13.2Q14.6 3.9 14.6 5.3V7M6.2 7L7.1 18.6Q7.2 20.3 8.9 20.3H15.1Q16.8 20.3 16.9 18.6L17.8 7M10 10.8V16.4M14 10.8V16.4")],
    "qr": [
        ("stroke", rrect(3.6, 3.6, 10.4, 10.4, 1.6) + rrect(13.6, 3.6, 20.4, 10.4, 1.6) + rrect(3.6, 13.6, 10.4, 20.4, 1.6)),
        ("ink", rrect(6.1, 6.1, 7.9, 7.9, 0.4) + rrect(16.1, 6.1, 17.9, 7.9, 0.4) + rrect(6.1, 16.1, 7.9, 17.9, 0.4)
         + rrect(13.6, 13.6, 15.4, 15.4, 0.4) + rrect(18.6, 13.6, 20.4, 15.4, 0.4) + rrect(16.1, 16.1, 17.9, 17.9, 0.4)
         + rrect(13.6, 18.6, 15.4, 20.4, 0.4) + rrect(18.6, 18.6, 20.4, 20.4, 0.4)),
    ],
    "camera": [("stroke", rrect(3.4, 7.2, 20.6, 20, 3.2) + "M8.3 7.2L9.5 5Q9.8 4.4 10.5 4.4H13.5Q14.2 4.4 14.5 5L15.7 7.2" + circle(12, 13.7, 3.5))],
    "book": [("stroke", "M12 6.6V19.6M12 6.6Q9.4 4.9 5.6 5.1Q4 5.2 4 6.8V17.6Q4 19.2 5.6 19.1Q9.4 18.9 12 19.6Q14.6 18.9 18.4 19.1Q20 19.2 20 17.6V6.8Q20 5.2 18.4 5.1Q14.6 4.9 12 6.6Z")],
    "people": [("stroke", circle(9, 8.2, 3.1) + "M3.6 19.8Q3.6 14.6 9 14.6Q14.4 14.6 14.4 19.8M15.6 5.4Q17.9 5.2 18.9 7.2Q19.9 9.4 18.3 11.1Q17.6 11.8 16.7 12M17 14.7Q20.4 15.1 20.4 19.8")],
    "mail": [("stroke", rrect(3.4, 5.4, 20.6, 18.6, 2.8) + "M4.6 7.6L12 13.1L19.4 7.6")],
    "clock": [("stroke", circle(12, 12, 8.6) + "M12 7.4V12.2L15.2 14.1")],
    "tune": [("stroke", "M4 8H6.7M11.3 8H20M4 16H12.7M17.3 16H20" + circle(9, 8, 2.3) + circle(15, 16, 2.3))],
    "calendar": [("stroke", rrect(3.8, 5.4, 20.2, 20.2, 2.8) + "M3.8 10.2H20.2M8.4 3.4V7M15.6 3.4V7")],
    "search": [("stroke", circle(10.6, 10.6, 6.6) + "M15.4 15.4L20.2 20.2")],
    "person": [("stroke", circle(12, 8.4, 3.6) + "M4.8 20Q4.8 14.5 12 14.5Q19.2 14.5 19.2 20")],
    "unlock": [("stroke", rrect(5.2, 10.8, 18.8, 20.4, 2.8) + "M8.6 10.8V8.2Q8.6 3.8 12.4 3.8Q15.4 3.8 16 6.4")],
    "add": [("stroke", "M12 4.8V19.2M4.8 12H19.2")],
    "check": [("stroke", "M4.8 12.6L9.6 17.4L19.2 6.8")],
    "film": [("stroke", rrect(3.6, 4.2, 20.4, 19.8, 2.6) + "M8 4.2V19.8M16 4.2V19.8M3.6 9H8M3.6 12H8M3.6 15H8M16 9H20.4M16 12H20.4M16 15H20.4")],
    "copy": [("stroke", rrect(8.6, 8.6, 19.6, 19.6, 2.4) + "M15.4 8.6V6.8Q15.4 4.4 13 4.4H6.8Q4.4 4.4 4.4 6.8V13Q4.4 15.4 6.8 15.4H8.6")],
    "logout": [("stroke", "M9.4 20H6.6Q4.4 20 4.4 17.8V6.2Q4.4 4 6.6 4H9.4M15.2 7.6L19.6 12L15.2 16.4M19.6 12H9.8")],
    "lock": [("stroke", rrect(5.2, 10.8, 18.8, 20.4, 2.8) + "M8.6 10.8V8.2Q8.6 3.8 12 3.8Q15.4 3.8 15.4 8.2V10.8")],
    "link": [("stroke", "M10.2 13.8Q8.4 12 10.2 10.2L13 7.4Q14.8 5.6 16.6 7.4Q18.4 9.2 16.6 11L15.4 12.2M13.8 10.2Q15.6 12 13.8 13.8L11 16.6Q9.2 18.4 7.4 16.6Q5.6 14.8 7.4 13L8.6 11.8")],
    "close": [("stroke", "M6.2 6.2L17.8 17.8M17.8 6.2L6.2 17.8")],
    "back": [("stroke", "M14.8 5.2L8 12L14.8 18.8")],
    "next": [("stroke", "M9.2 5.2L16 12L9.2 18.8")],
    "people_add": [("stroke", circle(9, 8.2, 3.1) + "M3.6 19.8Q3.6 14.6 9 14.6Q12 14.6 13.6 16.2M17 11V17M14 14H20")],
}

icons = {**brand, **line}

# ---------- Material-глифы, выровненные по оптическому размеру ----------
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

fonts = FLUTTER / "bin/cache/artifacts/material_fonts"
font = TTFont(fonts / "materialicons-regular.otf")
cmap = font.getBestCmap()
gs = font.getGlyphSet()
codes = {}
for l in (fonts / "codepoints").read_text().splitlines():
    n, c = l.split()
    codes[n] = int(c, 16)
UNITS = 24 / 512

want = {  # имя в вебе -> имя в шрифте
    "chevron_left": "chevron_left_baseline", "chevron_right": "chevron_right_baseline", "close": "close_baseline", "add": "add_baseline",
    "auto_stories": "auto_stories_baseline", "auto_stories_outlined": "auto_stories_outlined",
    "camera_roll": "camera_roll_baseline", "camera_roll_outlined": "camera_roll_outlined",
    "account_circle": "account_circle_baseline", "account_circle_outlined": "account_circle_outlined",
    "search": "search_baseline", "qr_code_2": "qr_code_2_baseline", "ios_share": "ios_share_baseline",
    "copy_outlined": "content_copy_outlined", "tune_outlined": "tune_outlined",
    "calendar_today_outlined": "calendar_today_outlined", "camera_alt_outlined": "camera_alt_outlined",
    "people_outline": "people_outline_baseline", "download_outlined": "download_outlined", "delete_outline": "delete_outline_baseline",
    "mail_outline": "mail_outline_baseline", "lock_open_outlined": "lock_open_outlined", "lock_outline": "lock_outline_baseline",
    "link": "link_baseline", "logout": "logout_baseline", "arrow_back": "arrow_back_baseline", "person_outline": "person_outline_baseline",
    "photo_library_outlined": "photo_library_outlined", "check": "check_baseline", "refresh": "refresh_baseline",
    "rotate_right": "rotate_right_baseline", "add_photo_alternate_outlined": "add_photo_alternate_outlined",
}


def norm_glyph(name):
    g = cmap[codes[name]]
    bp = BoundsPen(gs)
    gs[g].draw(bp)
    x0, y0, x1, y1 = bp.bounds
    # в сетке 24 (ось y вниз)
    gx0, gx1 = x0 * UNITS, x1 * UNITS
    gy0, gy1 = 24 - y1 * UNITS, 24 - y0 * UNITS
    w, h = gx1 - gx0, gy1 - gy0
    s = TARGET / max(w, h)
    cx, cy = (gx0 + gx1) / 2, (gy0 + gy1) / 2
    return g, s, cx, cy


def norm_path(name):
    g, s, cx, cy = norm_glyph(name)
    sp = SVGPathPen(gs, ntos=lambda v: ("%.2f" % v).rstrip("0").rstrip("."))
    # x' = 12 + s*(x*U - cx); y' = 12 + s*((24 - y*U) - cy)
    a = s * UNITS
    tp = TransformPen(sp, (a, 0, 0, -a, 12 - s * cx, 12 + s * (24 - cy)))
    gs[g].draw(tp)
    return sp.getCommands()


material = {key: norm_path(fname) for key, fname in want.items() if fname in codes}

# ---------- Таблица оптического выравнивания для Flutter (по codePoint) ----------
icons_dart = (FLUTTER / "packages/flutter/lib/src/material/icons.dart").read_text(encoding="utf-8")
cp_by_name = {m.group(1): int(m.group(2), 16) for m in re.finditer(r"static const IconData (\w+) = IconData\(0x([0-9a-fA-F]+)", icons_dart)}
used = set()
for p in (ROOT / "host-app/lib").rglob("*.dart"):
    used |= set(re.findall(r"Icons\.([a-z0-9_]+)", p.read_text(encoding="utf-8", errors="ignore")))
norm_rows = []
for n in sorted(used):
    cp = cp_by_name.get(n)
    if cp is None or cp not in cmap:
        continue
    g = cmap[cp]
    bp = BoundsPen(gs)
    gs[g].draw(bp)
    if not bp.bounds:
        continue
    x0, y0, x1, y1 = bp.bounds
    gx0, gx1 = x0 * UNITS, x1 * UNITS
    gy0, gy1 = 24 - y1 * UNITS, 24 - y0 * UNITS
    w, h = gx1 - gx0, gy1 - gy0
    s = TARGET / max(w, h)
    cx, cy = (gx0 + gx1) / 2, (gy0 + gy1) / 2
    norm_rows.append((cp, round(s, 3), round(-(s * (cx - 12)) / 24, 4), round(-(s * (cy - 12)) / 24, 4)))

# ---------- TypeScript ----------
kinds = "'stroke' | 'soft' | 'accent' | 'ink' | 'badge' | 'white' | 'whiteStroke'"
names = " | ".join(f"'{n}'" for n in icons)
ts = [
    "// Сгенерировано tools/gen_icons.py. Не править руками.",
    "// materialPaths: глифы Material (как в приложении), выровненные по оптическому размеру.",
    "// brandIcons: фирменные значки ImpoMento и единый набор линейных иконок (обводка 1.8, сетка 24).",
    "export const materialPaths = " + json.dumps(material, ensure_ascii=False, indent=2) + " as const", "",
    f"export type BrandLayer = {{ kind: {kinds}; d: string }}",
    f"export type BrandIconName = {names}",
    "export const brandIcons: Record<BrandIconName, BrandLayer[]> = " +
    json.dumps({n: [{"kind": k, "d": d} for k, d in ls] for n, ls in icons.items()}, ensure_ascii=False, indent=2), "",
]
(ROOT / "guest-pwa/src/app/iconData.ts").write_text("\n".join(ts), encoding="utf-8")

# ---------- Dart ----------
dart = ["// Сгенерировано tools/gen_icons.py. Не править руками.",
        "// Фирменные и линейные иконки ImpoMento: те же пути, что в вебе (guest-pwa/src/app/iconData.ts).",
        "const brandIconData = <String, List<(String, String)>>{"]
for n, ls in icons.items():
    dart.append(f"  '{n}': [")
    for k, d in ls:
        dart.append(f"    ('{k}', '{d}'),")
    dart.append("  ],")
dart.append("};")
dart.append("")
dart.append("/// Оптическое выравнивание Material-иконок: codePoint -> [масштаб, сдвиг x, сдвиг y] (доли размера).")
dart.append("const kIconNorm = <int, List<double>>{")
for cp, s, dx, dy in norm_rows:
    dart.append(f"  0x{cp:x}: [{s}, {dx}, {dy}],")
dart.append("};")
(ROOT / "host-app/lib/core/widgets/brand_icon_data.dart").write_text("\n".join(dart) + "\n", encoding="utf-8")

json.dump(icons, open(Path(__file__).with_name("icons_preview.json"), "w", encoding="utf-8"), ensure_ascii=False)
json.dump(material, open(Path(__file__).with_name("material_preview.json"), "w", encoding="utf-8"), ensure_ascii=False)
print("icons:", len(icons), "material:", len(material), "flutter norm:", len(norm_rows))

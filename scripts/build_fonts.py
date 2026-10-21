"""Build the EzWoW Font Changer font set from OFL fonts.

Each output keeps a pretty base font's own letters and fills everything it
lacks from Noto fonts, so chat never shows boxes:
  * "complete" fonts get every Han character (Chinese / Japanese kanji).
  * the others get the 8,836 Han characters in everyday use (GB2312 +
    Big5 level 1) to stay small, plus accents, Greek, Cyrillic, kana,
    CJK punctuation and symbols.

Usage: put the source files named in SOURCES / BUILDS in the current folder
(google/fonts ofl/*, orioncactus/pretendard static/alternative), then run
    python build_fonts.py <output dir>
It also writes FontCoverage.lua for the addon's font test window.
"""
import os, sys
from fontTools.ttLib import TTFont
from fontTools.ttLib.scaleUpem import scale_upem
from fontTools import subset
from fontTools.varLib import instancer
from fontTools.merge import Merger, Options as MergeOptions

OUT = sys.argv[1] if len(sys.argv) > 1 else "out"
os.makedirs(OUT, exist_ok=True)

def rng(*pairs):
    s = set()
    for a, b in pairs: s.update(range(a, b + 1))
    return s

LATIN_GAPS = rng((0x20, 0x7E), (0xA0, 0x24F), (0x250, 0x36F), (0x370, 0x3FF), (0x400, 0x52F),
                 (0x1E00, 0x1FFF), (0x2000, 0x2BFF))
CJK_MISC = rng((0x2E80, 0x2FDF), (0x3000, 0x33FF), (0xFE30, 0xFE4F), (0xFF00, 0xFFEF), (0x31F0, 0x31FF))
HAN = rng((0x3400, 0x4DBF), (0x4E00, 0x9FFF), (0xF900, 0xFAFF))
def common_han():
    """Han in everyday use: GB2312 (Simplified) + Big5 level 1 (Traditional), 8,836 characters."""
    chars = set()
    for hi in range(0xB0, 0xF8):
        for lo in range(0xA1, 0xFF):
            try: chars.add(ord(bytes([hi, lo]).decode("gb2312")))
            except UnicodeDecodeError: pass
    for hi in range(0xA4, 0xC7):
        for lo in list(range(0x40, 0x7F)) + list(range(0xA1, 0xFF)):
            if (hi, lo) > (0xC6, 0x7E): continue
            try: chars.add(ord(bytes([hi, lo]).decode("big5")))
            except UnicodeDecodeError: pass
    return {c for c in chars if 0x4E00 <= c <= 0x9FFF}
HAN_COMMON = common_han()
HANGUL = rng((0x1100, 0x11FF), (0x3130, 0x318F), (0xA960, 0xA97F), (0xAC00, 0xD7A3), (0xD7B0, 0xD7FF))
SYMBOLS = rng((0x2000, 0x2BFF))

SOURCES = {
    "notosans": ("notosans_NotoSans[wdth,wght].ttf", {"wght": 500, "wdth": 100}),
    "notokr":   ("notosanskr_NotoSansKR[wght].ttf", {"wght": 500}),
    "notosc":   ("notosanssc_NotoSansSC[wght].ttf", {"wght": 500}),
    "symbols":  ("notosanssymbols_NotoSansSymbols[wght].ttf", {"wght": 500}),
    "symbols2": ("notosanssymbols2_NotoSansSymbols2-Regular.ttf", None),
}
# file, family name, style, weight, base source, complete (with Han)?
BUILDS = [
    ("EzWoW-WorldSans-Medium.ttf", "EzWoW World Sans", "Medium", 500, "Pretendard-Medium.ttf", True),
    ("EzWoW-SansBold.ttf",         "EzWoW Sans Bold", "Bold", 600, "Pretendard-SemiBold.ttf", False),
    ("EzWoW-RoundGothic.ttf",      "EzWoW Round Gothic", "Medium", 500, "gothica1_GothicA1-Medium.ttf", False),
    ("EzWoW-SoftDodum.ttf",        "EzWoW Soft Dodum", "Regular", 400, "gowundodum_GowunDodum-Regular.ttf", False),
    ("EzWoW-Gothic.ttf",           "EzWoW Gothic", "Regular", 400, "NanumGothic-Regular.ttf", False),
    ("EzWoW-Myeongjo.ttf",         "EzWoW Myeongjo", "Regular", 400, "NanumMyeongjo-Regular.ttf", False),
    ("EzWoW-NeatSans.ttf",         "EzWoW Neat Sans", "Medium", 500, "base_SUIT.ttf", False),
    ("EzWoW-TechSans.ttf",         "EzWoW Tech Sans", "Medium", 500, "base_PlexKR.ttf", False),
    ("EzWoW-Jua.ttf",              "EzWoW Jua", "Regular", 600, "base_Jua.ttf", False),
    ("EzWoW-DoHyeon.ttf",          "EzWoW Do Hyeon", "Regular", 600, "base_DoHyeon.ttf", False),
    ("EzWoW-BlackHanSans.ttf",     "EzWoW Black Han Sans", "Regular", 900, "base_BlackHanSans.ttf", False),
    ("EzWoW-PenScript.ttf",        "EzWoW Pen Script", "Regular", 400, "base_NanumPen.ttf", False),
    ("EzWoW-Gaegu.ttf",            "EzWoW Gaegu", "Regular", 300, "base_Gaegu.ttf", False),
    ("EzWoW-SongMyung.ttf",        "EzWoW Song Myung", "Regular", 400, "base_SongMyung.ttf", False),
    ("EzWoW-Pixel.ttf",            "EzWoW Pixel", "Regular", 400, "base_Galmuri11.ttf", False),
    ("EzWoW-Paperlogy.ttf",        "EzWoW Paperlogy", "Medium", 500, "base_Paperlogy-5Medium.ttf", False),
    ("EzWoW-Gugi.ttf",             "EzWoW Gugi", "Regular", 600, "base_Gugi.ttf", False),
    ("EzWoW-Diphylleia.ttf",       "EzWoW Diphylleia", "Regular", 400, "base_Diphylleia.ttf", False),
    ("EzWoW-SingleDay.ttf",        "EzWoW Single Day", "Regular", 500, "base_SingleDay.ttf", False),
    ("EzWoW-YeonSung.ttf",         "EzWoW Yeon Sung", "Regular", 500, "base_YeonSung.ttf", False),
    ("EzWoW-PoorStory.ttf",        "EzWoW Poor Story", "Regular", 400, "base_PoorStory.ttf", False),
    ("EzWoW-Stylish.ttf",          "EzWoW Stylish", "Regular", 500, "base_Stylish.ttf", False),
]
ONLY = set(sys.argv[2:])   # optional: build just these output files
# dropped while subsetting; variation tables must survive until the weight is instanced
SUBSET_DROP = ["GSUB", "GPOS", "GDEF", "STAT", "vhea", "vmtx", "VORG", "meta", "DSIG", "BASE",
               "kern", "morx", "feat", "hdmx", "LTSH", "VDMX"]
DROP = SUBSET_DROP + ["MVAR", "HVAR", "gvar", "fvar", "avar", "cvar"]

def piece(path, axes, codes, upem, out):
    font = TTFont(path)
    opts = subset.Options()
    opts.layout_features = []
    opts.hinting = False
    opts.notdef_outline = True
    opts.name_IDs = ["*"]
    opts.drop_tables += SUBSET_DROP
    sub = subset.Subsetter(opts)
    sub.populate(unicodes=sorted(codes))
    sub.subset(font)
    if axes and "fvar" in font:
        font = instancer.instantiateVariableFont(font, axes)
    for tag in DROP:
        if tag in font: del font[tag]
    if font["head"].unitsPerEm != upem:
        scale_upem(font, upem)
    font.save(out)
    return out

COVERAGE_TESTS = {
    "korean": rng((0xAC00, 0xD7A3)),
    "latin": rng((0x41, 0x5A), (0x61, 0x7A), (0xC0, 0x17F)) - {0xD7, 0xF7},
    "cyrillic": rng((0x410, 0x44F)) | {0x401, 0x451},
    "greek": rng((0x391, 0x3A1), (0x3A3, 0x3A9), (0x3B1, 0x3C9)),
    "chinese": HAN_COMMON,
    "japanese": rng((0x3041, 0x3096), (0x30A1, 0x30FA)),
    "symbols": {ord(c) for c in "★☆♥♡♪♫→←↑↓✓✔✗※●○◆◇■□▲△▼▽…‘’“”«»€£¥©®™°±×÷"},
}
coverage = {}
for out_name, family, style, weight, base_path, complete in BUILDS:
    target = os.path.join(OUT, out_name)
    if ONLY and out_name not in ONLY and os.path.exists(target):
        cmap = set(TTFont(target, lazy=True).getBestCmap())
        coverage[out_name] = {k: round(len(v & cmap) / len(v), 3) for k, v in COVERAGE_TESTS.items()}
        continue
    base = TTFont(base_path)
    upem = base["head"].unitsPerEm
    taken = set(base.getBestCmap())
    if not complete:
        taken -= HAN - HAN_COMMON   # keep the base's own everyday Han, drop rare ones to stay small
    parts = [piece(base_path, None, taken, upem, "pc_base.ttf")]
    plan = [("notosans", LATIN_GAPS), ("notokr", HANGUL), ("notosc", CJK_MISC | (HAN if complete else HAN_COMMON)),
            ("symbols", SYMBOLS), ("symbols2", SYMBOLS), ("notosc", SYMBOLS)]
    for index, (key, wanted) in enumerate(plan):
        path, axes = SOURCES[key]
        have = set(TTFont(path, lazy=True).getBestCmap())
        codes = (have & wanted) - taken
        if not codes: continue
        taken |= codes
        # fill-in letters use the base font's weight so they don't look bolder or thinner
        fill_axes = {**axes, "wght": weight} if axes and "wght" in axes else axes
        parts.append(piece(path, fill_axes, codes, upem, f"pc_{index}.ttf"))
    merged = Merger(options=MergeOptions(drop_tables=["vhea", "vmtx"])).merge(parts)
    # keep the base font's line metrics so text sits where the base designed it
    for table, fields in (("hhea", ("ascent", "descent", "lineGap")),
                          ("OS/2", ("sTypoAscender", "sTypoDescender", "sTypoLineGap", "usWinAscent", "usWinDescent"))):
        for field in fields:
            setattr(merged[table], field, getattr(base[table], field))
    merged["OS/2"].usWeightClass = weight
    name = merged["name"]
    name.names = [r for r in name.names if r.nameID in (13, 14)]
    # OFL: keep the original copyright notices inside the modified font itself
    base_copyright = (base["name"].getDebugName(0) or "").strip()
    copyright_notice = (f"{base_copyright} Modified by EzWoW: letters added from Noto Sans fonts "
                        "(Copyright 2022 The Noto Project Authors; Copyright 2014-2021 Adobe, with Reserved "
                        "Font Name 'Source'). Licensed under the SIL Open Font License 1.1; see LICENSE-EzWoWFonts.txt.")
    for nid, value in {0: copyright_notice, 1: family, 2: "Regular",
                       3: f"{family}; EzWoW", 4: family, 5: "Version 1.000", 6: family.replace(" ", ""),
                       13: "This Font Software is licensed under the SIL Open Font License, Version 1.1.",
                       14: "https://openfontlicense.org"}.items():
        name.setName(value, nid, 3, 1, 0x409)
    merged.save(target)
    cmap = set(TTFont(target, lazy=True).getBestCmap())
    coverage[out_name] = {k: round(len(v & cmap) / len(v), 3) for k, v in COVERAGE_TESTS.items()}
    print(out_name, os.path.getsize(target) // 1024, "KB", merged["maxp"].numGlyphs, "glyphs", coverage[out_name])

with open(os.path.join(OUT, "FontCoverage.lua"), "w", encoding="utf-8") as fh:
    fh.write("--===========================================================================\n"
             "-- EzWoW - Font Changer\n"
             "-- Data/FontCoverage.lua : Share of each test alphabet a bundled font contains\n"
             "-- (generated by scripts/build_fonts.py - do not edit by hand)\n"
             "--===========================================================================\n"
             "local _, ns = ...\n\nns.FONT_COVERAGE = {\n")
    for out_name, cov in coverage.items():
        items = ", ".join(f"{k} = {v}" for k, v in cov.items())
        fh.write(f'    ["{out_name}"] = {{ {items} }},\n')
    fh.write("}\n")

"""EzWoW Font Maker - build your own WoW font from free (SIL OFL) fonts.

Pick a font for each language (Latin, Hangul, Cyrillic/Greek, kana, Han,
symbols); the program merges them into one .ttf that never shows boxes,
checks every source is OFL-licensed, refuses names that use a source's
Reserved Font Name, keeps the original copyright notices, and writes the
license file next to the font. A test panel draws every language before
and after building. Output can go straight to Interface/AddOns/EzWoW-MyFonts
for EzWoW - Font Changer.

Needs Python 3.9+ with:  pip install fonttools pillow
"""
import json
import os
import queue
import re
import subprocess
import sys
import threading
import traceback
import urllib.request
from pathlib import Path

import tkinter as tk
from tkinter import filedialog, messagebox, ttk

APP_TITLE = "EzWoW Font Maker"
APP_DIR = Path(os.environ.get("LOCALAPPDATA") or (Path.home() / ".config")) / "EzWoW-FontMaker"
CACHE_DIR = APP_DIR / "cache"
SETTINGS_FILE = APP_DIR / "settings.json"

# --------------------------------------------------------------------------
# Dependencies
# --------------------------------------------------------------------------
def ensure_dependencies():
    try:
        import fontTools  # noqa: F401
        from PIL import Image, ImageTk  # noqa: F401
        return True
    except ImportError:
        root = tk.Tk()
        root.withdraw()
        ok = messagebox.askyesno(APP_TITLE, "글꼴을 다루는 파이썬 모듈(fonttools, pillow)이 필요합니다.\n지금 설치할까요?\n\n"
                                 "Python modules fonttools and pillow are required. Install now?")
        if ok:
            result = subprocess.run([sys.executable, "-m", "pip", "install", "--user", "fonttools", "pillow"],
                                    capture_output=True, text=True)
            if result.returncode == 0:
                messagebox.showinfo(APP_TITLE, "설치했습니다. 프로그램을 다시 실행해 주세요.")
            else:
                messagebox.showerror(APP_TITLE, "설치 실패:\n" + result.stderr[-800:])
        root.destroy()
        return False

# --------------------------------------------------------------------------
# Font catalog (all SIL Open Font License 1.1)
# --------------------------------------------------------------------------
G = "https://raw.githubusercontent.com/google/fonts/main/ofl/"
R = "https://raw.githubusercontent.com/"
PRETENDARD = R + "orioncactus/pretendard/main/packages/pretendard/dist/public/static/alternative/Pretendard-{}.ttf"
SUIT = R + "sun-typeface/SUIT/main/fonts/static/ttf/SUIT-{}.ttf"

def static(fmt, *weights):
    return {w: fmt.format(w) for w in weights}

# key: name, group, files (weight label -> url) or var (url, wght range, fixed axes), license url
CATALOG = {
    "pretendard":   {"name": "Pretendard", "group": "한글", "files": static(PRETENDARD, "Regular", "Medium", "SemiBold", "Bold"),
                     "license": R + "orioncactus/pretendard/main/LICENSE"},
    "suit":         {"name": "SUIT", "group": "한글", "files": static(SUIT, "Regular", "Medium", "SemiBold", "Bold"),
                     "license": R + "sun-typeface/SUIT/main/LICENSE"},
    "gothica1":     {"name": "Gothic A1", "group": "한글", "files": static(G + "gothica1/GothicA1-{}.ttf", "Regular", "Medium", "Bold"),
                     "license": G + "gothica1/OFL.txt"},
    "plexkr":       {"name": "IBM Plex Sans KR", "group": "한글", "files": static(G + "ibmplexsanskr/IBMPlexSansKR-{}.ttf", "Regular", "Medium", "Bold"),
                     "license": G + "ibmplexsanskr/OFL.txt"},
    "nanumgothic":  {"name": "나눔고딕", "group": "한글", "files": static(G + "nanumgothic/NanumGothic-{}.ttf", "Regular", "Bold", "ExtraBold"),
                     "license": G + "nanumgothic/OFL.txt"},
    "nanummyeongjo": {"name": "나눔명조", "group": "한글", "files": static(G + "nanummyeongjo/NanumMyeongjo-{}.ttf", "Regular", "Bold"),
                     "license": G + "nanummyeongjo/OFL.txt"},
    "gowundodum":   {"name": "고운돋움", "group": "한글", "files": static(G + "gowundodum/GowunDodum-{}.ttf", "Regular"),
                     "license": G + "gowundodum/OFL.txt"},
    "gowunbatang":  {"name": "고운바탕", "group": "한글", "files": static(G + "gowunbatang/GowunBatang-{}.ttf", "Regular", "Bold"),
                     "license": G + "gowunbatang/OFL.txt"},
    "songmyung":    {"name": "송명", "group": "한글", "files": static(G + "songmyung/SongMyung-{}.ttf", "Regular"),
                     "license": G + "songmyung/OFL.txt"},
    "jua":          {"name": "주아", "group": "한글", "files": static(G + "jua/Jua-{}.ttf", "Regular"),
                     "license": G + "jua/OFL.txt"},
    "dohyeon":      {"name": "도현", "group": "한글", "files": static(G + "dohyeon/DoHyeon-{}.ttf", "Regular"),
                     "license": G + "dohyeon/OFL.txt"},
    "blackhansans": {"name": "검은고딕 (Black Han Sans)", "group": "한글", "files": static(G + "blackhansans/BlackHanSans-{}.ttf", "Regular"),
                     "license": G + "blackhansans/OFL.txt"},
    "dongle":       {"name": "동글", "group": "한글", "files": static(G + "dongle/Dongle-{}.ttf", "Regular", "Bold"),
                     "license": G + "dongle/OFL.txt"},
    "nanumpen":     {"name": "나눔손글씨 펜", "group": "한글", "files": static(G + "nanumpenscript/NanumPenScript-{}.ttf", "Regular"),
                     "license": G + "nanumpenscript/OFL.txt"},
    "gaegu":        {"name": "개구", "group": "한글", "files": static(G + "gaegu/Gaegu-{}.ttf", "Light", "Regular", "Bold"),
                     "license": G + "gaegu/OFL.txt"},
    "galmuri11":    {"name": "갈무리11 (픽셀)", "group": "한글", "files": static(R + "quiple/galmuri/main/dist/Galmuri11{}.ttf", "", "-Bold"),
                     "license": R + "quiple/galmuri/main/ofl.md"},
    "notosanskr":   {"name": "Noto Sans KR", "group": "Noto", "var": G + "notosanskr/NotoSansKR%5Bwght%5D.ttf", "wght": (100, 900),
                     "license": G + "notosanskr/OFL.txt"},
    "notoserifkr":  {"name": "Noto Serif KR", "group": "Noto", "var": G + "notoserifkr/NotoSerifKR%5Bwght%5D.ttf", "wght": (200, 900),
                     "license": G + "notoserifkr/OFL.txt"},
    "inter":        {"name": "Inter", "group": "영문", "var": G + "inter/Inter%5Bopsz,wght%5D.ttf", "wght": (100, 900), "fixed": {"opsz": 14},
                     "license": G + "inter/OFL.txt"},
    "nunito":       {"name": "Nunito", "group": "영문", "var": G + "nunito/Nunito%5Bwght%5D.ttf", "wght": (200, 1000),
                     "license": G + "nunito/OFL.txt"},
    "montserrat":   {"name": "Montserrat", "group": "영문", "var": G + "montserrat/Montserrat%5Bwght%5D.ttf", "wght": (100, 900),
                     "license": G + "montserrat/OFL.txt"},
    "roboto":       {"name": "Roboto", "group": "영문", "var": G + "roboto/Roboto%5Bwdth,wght%5D.ttf", "wght": (100, 900), "fixed": {"wdth": 100},
                     "license": G + "roboto/OFL.txt"},
    "cinzel":       {"name": "Cinzel (판타지 대문자)", "group": "영문", "var": G + "cinzel/Cinzel%5Bwght%5D.ttf", "wght": (400, 900),
                     "license": G + "cinzel/OFL.txt"},
    "notosans":     {"name": "Noto Sans", "group": "Noto", "var": G + "notosans/NotoSans%5Bwdth,wght%5D.ttf", "wght": (100, 900), "fixed": {"wdth": 100},
                     "license": G + "notosans/OFL.txt"},
    "notoserif":    {"name": "Noto Serif", "group": "Noto", "var": G + "notoserif/NotoSerif%5Bwdth,wght%5D.ttf", "wght": (100, 900), "fixed": {"wdth": 100},
                     "license": G + "notoserif/OFL.txt"},
    "notosansjp":   {"name": "Noto Sans JP", "group": "Noto", "var": G + "notosansjp/NotoSansJP%5Bwght%5D.ttf", "wght": (100, 900),
                     "license": G + "notosansjp/OFL.txt"},
    "notosanssc":   {"name": "Noto Sans SC (간체 한자)", "group": "Noto", "var": G + "notosanssc/NotoSansSC%5Bwght%5D.ttf", "wght": (100, 900),
                     "license": G + "notosanssc/OFL.txt"},
    "notosanstc":   {"name": "Noto Sans TC (번체 한자)", "group": "Noto", "var": G + "notosanstc/NotoSansTC%5Bwght%5D.ttf", "wght": (100, 900),
                     "license": G + "notosanstc/OFL.txt"},
    "symbols":      {"name": "Noto Sans Symbols", "group": "Noto", "var": G + "notosanssymbols/NotoSansSymbols%5Bwght%5D.ttf", "wght": (100, 900),
                     "license": G + "notosanssymbols/OFL.txt"},
    "symbols2":     {"name": "Noto Sans Symbols 2", "group": "Noto", "files": {"Regular": G + "notosanssymbols2/NotoSansSymbols2-Regular.ttf"},
                     "license": G + "notosanssymbols2/OFL.txt"},
}

WEIGHT_NUMBER = {"Thin": 100, "ExtraLight": 200, "Light": 300, "Regular": 400, "": 400, "Medium": 500,
                 "SemiBold": 600, "-Bold": 700, "Bold": 700, "ExtraBold": 800, "Black": 900}

def rng(*pairs):
    out = set()
    for a, b in pairs:
        out.update(range(a, b + 1))
    return out

# Each language: its code points, sample text, default font, Noto fills
CATEGORIES = [
    {"key": "latin", "label": "영어·유럽 문자", "codes": rng((0x20, 0x7E), (0xA0, 0x24F), (0x1E00, 0x1EFF), (0x2000, 0x206F), (0x20A0, 0x20CF)),
     "sample": "Hello Ŝtěfän Ørjåsæter ÀÉÎÕÜß 0123456789", "default": ("pretendard", "Medium"), "fill": ["notosans"]},
    {"key": "hangul", "label": "한글", "codes": rng((0x1100, 0x11FF), (0x3130, 0x318F), (0xA960, 0xA97F), (0xAC00, 0xD7A3), (0xD7B0, 0xD7FF)),
     "sample": "다람쥐 헌 쳇바퀴에 타고파 · 대족장 드랄 뷁똠", "default": ("pretendard", "Medium"), "fill": ["notosanskr"]},
    {"key": "cyrgreek", "label": "러시아·그리스 문자", "codes": rng((0x370, 0x3FF), (0x400, 0x52F), (0x1F00, 0x1FFF)),
     "sample": "Дмитрий: Привет! Ξεσκεπάζω αβγ", "default": ("pretendard", "Medium"), "fill": ["notosans"]},
    {"key": "kana", "label": "일본어 가나·전각", "codes": rng((0x3000, 0x303F), (0x3040, 0x30FF), (0x31F0, 0x31FF), (0xFF00, 0xFFEF)),
     "sample": "さくら カタカナ こんにちは 「ＡＢＣ」", "default": ("notosansjp", "500"), "fill": ["notosansjp", "notosanssc"]},
    {"key": "han", "label": "한자 (중국어)", "codes": rng((0x2E80, 0x2FDF), (0x3200, 0x33FF), (0x3400, 0x4DBF), (0x4E00, 0x9FFF), (0xF900, 0xFAFF)),
     "sample": "小龍女 大家好 一起刷副本吗 臺灣 謝謝", "default": ("notosanssc", "500"), "fill": ["notosanssc", "notosanstc"], "optional": True},
    {"key": "symbols", "label": "기호", "codes": rng((0x2070, 0x2BFF)),
     "sample": "★☆♥♡♪→←✓※●◆■▲…«»€©™", "default": ("auto", ""), "fill": ["symbols", "symbols2", "notosans", "notosanssc"]},
]
CAT_BY_KEY = {c["key"]: c for c in CATEGORIES}

COVERAGE_TESTS = [
    ("한국어", rng((0xAC00, 0xD7A3))),
    ("영어·유럽", rng((0x41, 0x5A), (0x61, 0x7A), (0xC0, 0x17F)) - {0xD7, 0xF7}),
    ("러시아어", rng((0x410, 0x44F)) | {0x401, 0x451}),
    ("그리스어", rng((0x391, 0x3A1), (0x3A3, 0x3A9), (0x3B1, 0x3C9))),
    ("중국어", rng((0x4E00, 0x9FA5))),
    ("일본어", rng((0x3041, 0x3096), (0x30A1, 0x30FA))),
    ("기호", {ord(c) for c in "★☆♥♡♪♫→←↑↓✓✔✗※●○◆◇■□▲△▼▽…‘’“”«»€£¥©®™°±×÷"}),
]
AUTO_LABEL = "자동 (Noto로 채우기)"
FILE_LABEL = "파일에서 선택..."

# --------------------------------------------------------------------------
# Sources: download, license, reserved names
# --------------------------------------------------------------------------
def download(url, dest, log):
    dest = Path(dest)
    if dest.exists() and dest.stat().st_size > 0:
        return dest
    dest.parent.mkdir(parents=True, exist_ok=True)
    log(f"내려받는 중: {url.rsplit('/', 1)[-1].replace('%5B', '[').replace('%5D', ']')}")
    request = urllib.request.Request(url, headers={"User-Agent": "EzWoW-FontMaker"})
    with urllib.request.urlopen(request, timeout=120) as response, open(str(dest) + ".part", "wb") as fh:
        while True:
            chunk = response.read(1 << 16)
            if not chunk:
                break
            fh.write(chunk)
    os.replace(str(dest) + ".part", dest)
    return dest

def extract_reserved_names(text):
    """Names after 'with Reserved Font Name' in a copyright line (not the OFL body text)."""
    header = re.split(r"This Font Software is licensed|SIL OPEN FONT LICENSE", text or "", flags=re.I)[0]
    names = []
    for match in re.finditer(r"with\s+Reserved\s+Font\s+Names?\s*(.*?)(?:\.\s|\.$|\n\s*\n|$)", header, re.I | re.S):
        for part in re.split(r",|\band\b|\n", match.group(1)):
            part = part.strip().strip("'\"“”‘’ ").strip()
            if part and len(part) < 60 and part.lower() not in (n.lower() for n in names):
                names.append(part)
    return names

OFL_PATTERN = re.compile(r"open\s+font\s+license|scripts\.sil\.org/ofl|openfontlicense", re.I)

class Source:
    """One font file plus everything the license asks us to carry along."""
    def __init__(self, path, display, axes=None, weight=400, license_text="", copyright_text=""):
        self.path = str(path)
        self.display = display
        self.axes = axes or {}
        self.weight = weight
        self.license_text = license_text
        self.copyright = copyright_text
        self.reserved = extract_reserved_names(copyright_text + "\n\n" + license_text)
        self._cmap = None

    @property
    def cmap(self):
        if self._cmap is None:
            from fontTools.ttLib import TTFont
            self._cmap = set(TTFont(self.path, lazy=True).getBestCmap() or {})
        return self._cmap

def catalog_weights(key):
    entry = CATALOG[key]
    if "files" in entry:
        return list(entry["files"])
    low, high = entry["wght"]
    return [str(w) for w in range(100, 1000, 100) if low <= w <= high]

def weight_label_text(label):
    return {"": "Regular", "-Bold": "Bold"}.get(label, label)

def load_catalog_source(key, weight_label, log):
    from fontTools.ttLib import TTFont
    entry = CATALOG[key]
    lic_path = download(entry["license"], CACHE_DIR / key / "LICENSE.txt", log)
    if "files" in entry:
        label = weight_label if weight_label in entry["files"] else next(iter(entry["files"]))
        url = entry["files"][label]
        path = download(url, CACHE_DIR / key / url.rsplit("/", 1)[-1], log)
        axes, weight = None, WEIGHT_NUMBER.get(label, 400)
        display = f"{entry['name']} {weight_label_text(label)}"
    else:
        url = entry["var"]
        name = url.rsplit("/", 1)[-1].replace("%5B", "[").replace("%5D", "]")
        path = download(url, CACHE_DIR / key / name, log)
        low, high = entry["wght"]
        weight = min(high, max(low, int(weight_label) if str(weight_label).isdigit() else 400))
        axes = dict(entry.get("fixed", {}), wght=weight)
        display = f"{entry['name']} {weight}"
    license_text = Path(lic_path).read_text(encoding="utf-8", errors="replace")
    copyright_text = TTFont(path, lazy=True)["name"].getDebugName(0) or ""
    return Source(path, display, axes, weight, license_text, copyright_text)

def check_user_font(path):
    """(ok, message, Source) for a font file the player picked."""
    from fontTools.ttLib import TTFont
    try:
        font = TTFont(path, lazy=True)
    except Exception as error:
        return False, f"글꼴 파일을 열 수 없어요: {error}", None
    if "glyf" not in font:
        return False, "TrueType(.ttf) 윤곽선 글꼴만 쓸 수 있어요 (CFF 기반 .otf는 와우에서 깨질 수 있음).", None
    name = font["name"]
    license_text = "\n".join(filter(None, [name.getDebugName(13), name.getDebugName(14)]))
    folder = Path(path).parent
    for candidate in ("OFL.txt", "OFL.md", "LICENSE", "LICENSE.txt", "license.txt", "ofl.md"):
        file = folder / candidate
        if file.exists():
            license_text += "\n" + file.read_text(encoding="utf-8", errors="replace")
    if not OFL_PATTERN.search(license_text):
        return False, ("이 글꼴은 SIL Open Font License(OFL)인지 확인되지 않아 쓸 수 없어요.\n"
                       "무료 글꼴이라도 수정·재배포가 금지된 경우가 많습니다. OFL 글꼴이면 같은 폴더에 OFL.txt를 두세요."), None
    if font["OS/2"].fsType & 0x0002:
        return False, "이 글꼴은 임베딩 제한(Restricted)이 걸려 있어 쓸 수 없어요.", None
    weight = getattr(font["OS/2"], "usWeightClass", 400) or 400
    display = (name.getDebugName(4) or Path(path).stem)
    axes = {"wght": 400} if "fvar" in font else None
    return True, "OFL 확인", Source(path, display, axes, weight, license_text, name.getDebugName(0) or "")

# --------------------------------------------------------------------------
# Build
# --------------------------------------------------------------------------
# dropped while subsetting; variation tables must survive until the weight is instanced
SUBSET_DROP = ["GSUB", "GPOS", "GDEF", "STAT", "vhea", "vmtx", "VORG", "meta", "DSIG", "BASE",
               "kern", "morx", "feat", "hdmx", "LTSH", "VDMX", "JSTF", "COLR", "CPAL"]
DROP_TABLES = SUBSET_DROP + ["MVAR", "HVAR", "gvar", "fvar", "avar", "cvar"]

def make_piece(source, codes, upem, scale, out_path):
    from fontTools import subset
    from fontTools.ttLib import TTFont
    from fontTools.ttLib.scaleUpem import scale_upem
    from fontTools.varLib import instancer
    font = TTFont(source.path)
    options = subset.Options()
    options.layout_features = []
    options.hinting = False
    options.notdef_outline = True
    options.name_IDs = ["*"]
    options.drop_tables += SUBSET_DROP
    subsetter = subset.Subsetter(options)
    subsetter.populate(unicodes=sorted(codes))
    subsetter.subset(font)
    if "fvar" in font:
        present = {axis.axisTag for axis in font["fvar"].axes}
        pins = {tag: value for tag, value in source.axes.items() if tag in present}
        if "wght" in present and "wght" not in pins:
            pins["wght"] = source.weight
        font = instancer.instantiateVariableFont(font, pins)
    for tag in DROP_TABLES:
        if tag in font:
            del font[tag]
    # size the piece relative to the others: scale coordinates, keep the shared em size
    wanted = round(upem * scale)
    if font["head"].unitsPerEm != wanted:
        scale_upem(font, wanted)
    font["head"].unitsPerEm = upem
    font.save(out_path)
    return out_path

def build_font(plan, family, out_path, include_han, metrics_key, log):
    """plan: {category key: (Source or None, scale)}; fills: {category: [Source]}."""
    from fontTools.merge import Merger, Options as MergeOptions
    from fontTools.ttLib import TTFont
    work = CACHE_DIR / "work"
    work.mkdir(parents=True, exist_ok=True)
    metrics_source = (plan[metrics_key][0] or plan["hangul"][0]
                      or next((plan[c["key"]][0] for c in CATEGORIES if plan[c["key"]][0]), None)
                      or plan["__fills__"]["hangul"][0])
    base_font = TTFont(metrics_source.path, lazy=False)
    upem = base_font["head"].unitsPerEm
    taken, pieces, used = set(), [], []
    order = [c for c in CATEGORIES if include_han or c["key"] != "han"]
    steps = []
    for category in order:                      # chosen fonts first
        source, scale = plan[category["key"]]
        if source:
            steps.append((category, source, scale))
    for category in order:                      # then Noto fills for anything left
        _, scale = plan[category["key"]]
        for fill in plan["__fills__"][category["key"]]:
            steps.append((category, fill, 1.0))
    for index, (category, source, scale) in enumerate(steps):
        codes = (source.cmap & category["codes"]) - taken
        if not codes:
            continue
        taken |= codes
        log(f"  {category['label']}: {source.display} ({len(codes)}자)")
        pieces.append(make_piece(source, codes, upem, scale, str(work / f"piece{index}.ttf")))
        if source not in used:
            used.append(source)
    log("합치는 중...")
    merged = Merger(options=MergeOptions(drop_tables=["vhea", "vmtx"])).merge(pieces)
    for table, fields in (("hhea", ("ascent", "descent", "lineGap")),
                          ("OS/2", ("sTypoAscender", "sTypoDescender", "sTypoLineGap", "usWinAscent", "usWinDescent"))):
        for field in fields:
            setattr(merged[table], field, getattr(base_font[table], field))
    merged["OS/2"].usWeightClass = metrics_source.weight
    merged["OS/2"].fsType = 0
    notices = []
    for source in used:
        if source.copyright and source.copyright not in notices:
            notices.append(source.copyright.strip())
    copyright_text = " ".join(notices) + " Modified by EzWoW Font Maker. Licensed under the SIL Open Font License 1.1."
    name = merged["name"]
    name.names = []
    ps_name = re.sub(r"[^A-Za-z0-9-]", "", family.replace(" ", "")) or "EzWoWFont"
    for nid, value in {0: copyright_text, 1: family, 2: "Regular", 3: f"{family}; EzWoW Font Maker", 4: family,
                       5: "Version 1.000", 6: ps_name[:63],
                       13: "This Font Software is licensed under the SIL Open Font License, Version 1.1.",
                       14: "https://openfontlicense.org"}.items():
        name.setName(value, nid, 3, 1, 0x409)
    merged.save(out_path)
    return used

def write_license(out_path, family, used):
    lines = [f"{family}", "=" * len(family), "",
             "This font is a Modified Version (subset and merge) of the fonts below, all licensed",
             "under the SIL Open Font License, Version 1.1. It was made with EzWoW Font Maker and",
             "does not use any of their Reserved Font Names.", ""]
    ofl_text = ""
    for source in used:
        lines.append(f"- {source.display}")
        if source.copyright:
            lines.append(f"    {source.copyright.strip()}")
        for reserved in source.reserved:
            lines.append(f"    Reserved Font Name: {reserved}")
        match = re.search(r"SIL OPEN FONT LICENSE.*", source.license_text, re.S | re.I)
        if match and not ofl_text:
            ofl_text = match.group(0)
    lines += ["", "-" * 60, "This Font Software is licensed under the SIL Open Font License, Version 1.1.",
              "This license is copied below, and is also available with a FAQ at: https://openfontlicense.org", "",
              ofl_text.replace("\r\n", "\n").lstrip("# ")]
    Path(out_path).write_text("\n".join(lines), encoding="utf-8")

def write_myfonts_list(folder):
    """Same as tools/make_myfonts.py: lets Font Changer find every file by name."""
    folder = Path(folder)
    fonts = sorted(p.name for p in folder.iterdir() if p.suffix.lower() in (".ttf", ".otf"))
    body = ",\n".join('    "%s"' % n.replace("\\", "\\\\").replace('"', '\\"') for n in fonts)
    (folder / "MyFonts.lua").write_text("-- Generated by EzWoW Font Maker\nEzWoW_MyFonts = {\n" + body +
                                        ("\n" if fonts else "") + "}\n", encoding="utf-8")
    (folder / "EzWoW-MyFonts.toc").write_text("## Interface: 16001\n## Title: EzWoW - My Fonts\n"
                                              "## Notes: Your own font files for EzWoW - Font Changer (generated)\n"
                                              "## Category: EzWoW\n\nMyFonts.lua\n", encoding="utf-8")
    return fonts

def coverage_report(cmap):
    return [(label, len(codes & cmap) / len(codes)) for label, codes in COVERAGE_TESTS]

# --------------------------------------------------------------------------
# Preview rendering
# --------------------------------------------------------------------------
class PreviewRenderer:
    BG = (14, 18, 24)
    TEXT = (237, 244, 247)
    MUTED = (167, 185, 197)
    ACCENT = (242, 196, 109)
    MISSING = (231, 124, 112)

    def __init__(self):
        self._fonts = {}

    def pil_font(self, source, size):
        from PIL import ImageFont
        key = (source.path, size, tuple(sorted(source.axes.items())))
        if key not in self._fonts:
            font = ImageFont.truetype(source.path, size)
            if source.axes:
                try:
                    axes = font.get_variation_axes()
                    values = []
                    for axis in axes:
                        tag = axis.get("name", b"")
                        tag = tag.decode() if isinstance(tag, bytes) else str(tag)
                        lookup = {"Weight": "wght", "Width": "wdth", "Optical size": "opsz", "Optical Size": "opsz"}.get(tag, tag)
                        values.append(source.axes.get(lookup, axis.get("default", axis.get("minimum"))))
                    font.set_variation_by_axes(values)
                except Exception:
                    pass
            self._fonts[key] = font
        return self._fonts[key]

    def render(self, rows, size, width=640):
        """rows: [(label, text, chooser)] where chooser(char) -> (Source, scale) or None."""
        from PIL import Image, ImageDraw
        line_height = int(size * 1.9)
        image = Image.new("RGB", (width, 16 + line_height * len(rows)), self.BG)
        draw = ImageDraw.Draw(image)
        label_font = None
        missing_total = []
        for row_index, (label, text, chooser, status) in enumerate(rows):
            y = 8 + row_index * line_height
            if label_font is None:
                label_font = self.label_font()
            draw.text((10, y + size * 0.3), label, font=label_font, fill=self.ACCENT)
            if status:
                text_status, color = status
                draw.text((128, y + size * 0.3), text_status, font=label_font, fill=color)
            x = 206
            for char in text:
                if x > width - size:
                    draw.text((x, y), "…", font=label_font, fill=self.MUTED)
                    break
                if char == " ":
                    x += size * 0.3
                    continue
                choice = chooser(char)
                if not choice:
                    draw.rectangle([x + 1, y + 2, x + size * 0.6, y + size], outline=self.MISSING)
                    x += size * 0.7
                    missing_total.append(char)
                    continue
                source, scale = choice
                font = self.pil_font(source, max(6, int(size * scale)))
                draw.text((x, y), char, font=font, fill=self.TEXT)
                x += font.getlength(char)
        return image, missing_total

    def label_font(self):
        from PIL import ImageFont
        for candidate in ("malgun.ttf", "C:/Windows/Fonts/malgun.ttf", "/usr/share/fonts/truetype/nanum/NanumGothic.ttf"):
            try:
                return ImageFont.truetype(candidate, 13)
            except OSError:
                continue
        return ImageFont.load_default()

# --------------------------------------------------------------------------
# Settings
# --------------------------------------------------------------------------
def load_settings():
    try:
        return json.loads(SETTINGS_FILE.read_text(encoding="utf-8"))
    except Exception:
        return {}

def save_settings(data):
    APP_DIR.mkdir(parents=True, exist_ok=True)
    SETTINGS_FILE.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")

def guess_myfonts_folder():
    roots = [Path(os.environ.get("ProgramFiles(x86)", "C:/Program Files (x86)")), Path(os.environ.get("ProgramFiles", "C:/Program Files")),
             Path("C:/"), Path("D:/")]
    for root in roots:
        wow = root / "World of Warcraft"
        if not wow.exists():
            continue
        for flavor in sorted(wow.iterdir()):
            addons = flavor / "Interface" / "AddOns"
            if (addons / "EzWoW-FontChanger").exists():
                return str(addons / "EzWoW-MyFonts")
    return ""

# --------------------------------------------------------------------------
# GUI
# --------------------------------------------------------------------------
class FontMakerApp:
    def __init__(self, root):
        self.root = root
        self.settings = load_settings()
        self.tasks = queue.Queue()
        self.busy = False
        self.renderer = PreviewRenderer()
        self.user_files = dict(self.settings.get("user_files", {}))   # display -> path
        self.preview_image = None
        self.built_source = None
        root.title(APP_TITLE)
        root.geometry("1180x760")
        root.minsize(1000, 640)
        self.build_ui()
        self.root.after(100, self.poll)

    # ---------- layout ----------
    def build_ui(self):
        style = ttk.Style(self.root)
        style.configure("Title.TLabel", font=("", 13, "bold"))
        main = ttk.Frame(self.root, padding=10)
        main.pack(fill="both", expand=True)
        main.columnconfigure(1, weight=1)
        main.rowconfigure(0, weight=1)

        left = ttk.Frame(main)
        left.grid(row=0, column=0, sticky="nsw", padx=(0, 10))
        right = ttk.Frame(main)
        right.grid(row=0, column=1, sticky="nsew")
        right.columnconfigure(0, weight=1)
        right.rowconfigure(2, weight=1)

        ttk.Label(left, text="언어별 글꼴 고르기", style="Title.TLabel").grid(row=0, column=0, columnspan=4, sticky="w")
        ttk.Label(left, text="무료 공개(OFL) 글꼴만 쓸 수 있어요. 빈 글자는 Noto로 채워 네모(□)가 생기지 않게 합니다.",
                  foreground="#666").grid(row=1, column=0, columnspan=4, sticky="w", pady=(0, 6))
        for column, text in enumerate(("언어", "글꼴", "굵기", "크기 %")):
            ttk.Label(left, text=text, foreground="#444").grid(row=2, column=column, sticky="w")

        self.rows = {}
        saved_rows = self.settings.get("rows", {})
        for index, category in enumerate(CATEGORIES):
            row = 3 + index
            frame_label = ttk.Frame(left)
            frame_label.grid(row=row, column=0, sticky="w", pady=2)
            include_var = tk.BooleanVar(value=self.settings.get("include_han", True))
            if category.get("optional"):
                ttk.Checkbutton(frame_label, text=category["label"], variable=include_var,
                                command=self.on_change).pack(side="left")
            else:
                ttk.Label(frame_label, text=category["label"], width=16).pack(side="left")
            font_var = tk.StringVar()
            font_box = ttk.Combobox(left, textvariable=font_var, width=30, state="readonly", values=self.font_choices())
            font_box.grid(row=row, column=1, padx=4)
            weight_var = tk.StringVar()
            weight_box = ttk.Combobox(left, textvariable=weight_var, width=9, state="readonly")
            weight_box.grid(row=row, column=2, padx=4)
            scale_var = tk.StringVar(value="100")
            scale_box = ttk.Spinbox(left, from_=70, to=130, increment=5, width=5, textvariable=scale_var, command=self.on_change)
            scale_box.grid(row=row, column=3)
            self.rows[category["key"]] = {"font": font_var, "font_box": font_box, "weight": weight_var,
                                          "weight_box": weight_box, "scale": scale_var, "include": include_var}
            saved = saved_rows.get(category["key"])
            key, weight = (saved["font"], saved["weight"]) if saved else category["default"]
            self.set_row_font(category["key"], key, weight)
            if saved:
                scale_var.set(saved.get("scale", "100"))
            font_box.bind("<<ComboboxSelected>>", lambda event, k=category["key"]: self.on_font_selected(k))
            weight_box.bind("<<ComboboxSelected>>", lambda event: self.on_change())

        options = ttk.Frame(left)
        options.grid(row=10, column=0, columnspan=4, sticky="we", pady=(10, 4))
        ttk.Label(options, text="줄 높이 기준:").pack(side="left")
        self.metrics_var = tk.StringVar(value=self.settings.get("metrics", "한글"))
        ttk.Combobox(options, textvariable=self.metrics_var, state="readonly", width=16,
                     values=[c["label"] for c in CATEGORIES if not c.get("optional")]).pack(side="left", padx=4)

        out = ttk.LabelFrame(left, text="만들기", padding=8)
        out.grid(row=11, column=0, columnspan=4, sticky="we", pady=(8, 0))
        out.columnconfigure(1, weight=1)
        ttk.Label(out, text="글꼴 이름").grid(row=0, column=0, sticky="w")
        self.name_var = tk.StringVar(value=self.settings.get("name", "My WoW Font"))
        ttk.Entry(out, textvariable=self.name_var, width=34).grid(row=0, column=1, sticky="we", padx=4)
        ttk.Label(out, text="저장 폴더").grid(row=1, column=0, sticky="w", pady=(4, 0))
        self.out_var = tk.StringVar(value=self.settings.get("out_dir") or guess_myfonts_folder() or str(Path.home() / "Desktop"))
        ttk.Entry(out, textvariable=self.out_var).grid(row=1, column=1, sticky="we", padx=4, pady=(4, 0))
        ttk.Button(out, text="찾기", width=6, command=self.choose_out_dir).grid(row=1, column=2, pady=(4, 0))
        ttk.Label(out, text="와우의 Interface\\AddOns\\EzWoW-MyFonts 폴더로 고르면 Font Changer가 바로 인식합니다 (게임 재시작).",
                  foreground="#666", wraplength=430).grid(row=2, column=0, columnspan=3, sticky="w", pady=(4, 0))
        buttons = ttk.Frame(out)
        buttons.grid(row=3, column=0, columnspan=3, sticky="we", pady=(8, 0))
        self.preview_button = ttk.Button(buttons, text="미리보기 (만들기 전)", command=self.start_preview)
        self.preview_button.pack(side="left")
        self.build_button = ttk.Button(buttons, text="글꼴 만들기", command=self.start_build)
        self.build_button.pack(side="left", padx=6)
        self.progress = ttk.Progressbar(buttons, mode="indeterminate", length=120)
        self.progress.pack(side="left", padx=6)

        log_frame = ttk.LabelFrame(left, text="진행 상황", padding=4)
        log_frame.grid(row=12, column=0, columnspan=4, sticky="nsew", pady=(8, 0))
        left.rowconfigure(12, weight=1)
        self.log_text = tk.Text(log_frame, height=10, width=64, wrap="word", state="disabled", font=("", 9))
        self.log_text.pack(fill="both", expand=True)

        # right: language test
        top = ttk.Frame(right)
        top.grid(row=0, column=0, sticky="we")
        ttk.Label(top, text="언어별 테스트", style="Title.TLabel").pack(side="left")
        self.mode_label = ttk.Label(top, text="", foreground="#666")
        self.mode_label.pack(side="left", padx=10)
        ttk.Label(top, text="글자 크기").pack(side="right")
        self.size_var = tk.StringVar(value="20")
        ttk.Spinbox(top, from_=10, to=40, width=4, textvariable=self.size_var, command=self.refresh_preview).pack(side="right", padx=4)

        custom = ttk.Frame(right)
        custom.grid(row=1, column=0, sticky="we", pady=(6, 6))
        custom.columnconfigure(1, weight=1)
        ttk.Label(custom, text="직접 입력:").grid(row=0, column=0)
        self.custom_var = tk.StringVar(value=self.settings.get("custom_text", "Галочкина 一脸 扫荡者 <射 一脸>"))
        entry = ttk.Entry(custom, textvariable=self.custom_var)
        entry.grid(row=0, column=1, sticky="we", padx=4)
        entry.bind("<KeyRelease>", lambda event: self.refresh_preview())

        canvas_frame = tk.Frame(right, background="#0e1218")
        canvas_frame.grid(row=2, column=0, sticky="nsew")
        self.preview_label = tk.Label(canvas_frame, background="#0e1218", anchor="nw")
        self.preview_label.pack(fill="both", expand=True)
        self.coverage_label = ttk.Label(right, text="", justify="left", wraplength=560)
        self.coverage_label.grid(row=3, column=0, sticky="we", pady=(6, 0))
        self.log("왼쪽에서 언어별 글꼴을 고르고 [미리보기]를 누르세요. 처음엔 글꼴을 내려받느라 시간이 걸립니다.")

    def font_choices(self):
        values = [AUTO_LABEL]
        for group in ("한글", "영문", "Noto"):
            values += [CATALOG[k]["name"] for k in CATALOG if CATALOG[k]["group"] == group]
        values += [f"[내 파일] {name}" for name in self.user_files]
        values.append(FILE_LABEL)
        return values

    def catalog_key_for(self, display):
        for key, entry in CATALOG.items():
            if entry["name"] == display:
                return key
        return None

    def set_row_font(self, category_key, key, weight):
        row = self.rows[category_key]
        if key == "auto":
            row["font"].set(AUTO_LABEL)
            row["weight_box"].configure(values=["400", "500", "600", "700"])
            row["weight"].set(weight or "500")
        elif key in CATALOG:
            row["font"].set(CATALOG[key]["name"])
            weights = catalog_weights(key)
            row["weight_box"].configure(values=[weight_label_text(w) if w in ("", "-Bold") else w for w in weights])
            shown = weight_label_text(weight) if weight in ("", "-Bold") else weight
            row["weight"].set(shown if shown in row["weight_box"]["values"] else row["weight_box"]["values"][0])
        elif key.startswith("file:") and key[5:] in self.user_files:
            row["font"].set(f"[내 파일] {key[5:]}")
            row["weight_box"].configure(values=["400", "500", "600", "700"])
            row["weight"].set(weight or "400")

    def row_key(self, category_key):
        display = self.rows[category_key]["font"].get()
        if display == AUTO_LABEL:
            return "auto"
        if display.startswith("[내 파일] "):
            return "file:" + display[len("[내 파일] "):]
        return self.catalog_key_for(display) or "auto"

    def on_font_selected(self, category_key):
        row = self.rows[category_key]
        if row["font"].get() == FILE_LABEL:
            path = filedialog.askopenfilename(title="OFL 글꼴 파일 선택", filetypes=[("TrueType", "*.ttf"), ("모든 파일", "*.*")])
            if not path:
                self.set_row_font(category_key, *CAT_BY_KEY[category_key]["default"])
                return
            ok, message, source = check_user_font(path)
            if not ok:
                messagebox.showwarning(APP_TITLE, message)
                self.set_row_font(category_key, *CAT_BY_KEY[category_key]["default"])
                return
            self.user_files[source.display] = path
            for other in self.rows.values():
                other["font_box"].configure(values=self.font_choices())
            self.set_row_font(category_key, "file:" + source.display, str(source.weight))
            self.log(f"내 파일 추가: {source.display} ({message})")
        else:
            self.set_row_font(category_key, self.row_key(category_key), "")
        self.on_change()

    def on_change(self):
        self.built_source = None
        self.mode_label.configure(text="설정이 바뀌었어요. [미리보기]를 다시 누르세요.")

    def choose_out_dir(self):
        folder = filedialog.askdirectory(title="저장 폴더 (예: ...\\Interface\\AddOns\\EzWoW-MyFonts)")
        if folder:
            self.out_var.set(folder)

    # ---------- background work ----------
    def log(self, message):
        self.log_text.configure(state="normal")
        self.log_text.insert("end", message + "\n")
        self.log_text.see("end")
        self.log_text.configure(state="disabled")

    def run_task(self, work, done):
        if self.busy:
            return
        self.busy = True
        self.progress.start(12)
        self.preview_button.state(["disabled"])
        self.build_button.state(["disabled"])

        def runner():
            try:
                result = work(lambda m: self.tasks.put(("log", m)))
                self.tasks.put(("done", (done, result)))
            except Exception as error:
                self.tasks.put(("log", "오류: " + "".join(traceback.format_exception_only(type(error), error)).strip()))
                self.tasks.put(("done", (None, None)))
        threading.Thread(target=runner, daemon=True).start()

    def poll(self):
        try:
            while True:
                kind, payload = self.tasks.get_nowait()
                if kind == "log":
                    self.log(payload)
                elif kind == "done":
                    self.busy = False
                    self.progress.stop()
                    self.preview_button.state(["!disabled"])
                    self.build_button.state(["!disabled"])
                    callback, result = payload
                    if callback:
                        callback(result)
        except queue.Empty:
            pass
        self.root.after(100, self.poll)

    def collect_plan_spec(self):
        spec = {}
        for category in CATEGORIES:
            row = self.rows[category["key"]]
            try:
                scale = max(0.7, min(1.3, float(row["scale"].get()) / 100))
            except ValueError:
                scale = 1.0
            spec[category["key"]] = (self.row_key(category["key"]), row["weight"].get(), scale)
        return spec

    def resolve_plan(self, spec, log):
        """Download / open every source the plan needs (worker thread)."""
        plan, fills, loaded = {}, {}, {}

        def catalog(key, weight):
            cache_key = (key, weight)
            if cache_key not in loaded:
                label = weight
                if key in CATALOG and "files" in CATALOG[key]:
                    label = {"Bold": "-Bold", "Regular": ""}.get(weight, weight) if key == "galmuri11" else weight
                loaded[cache_key] = load_catalog_source(key, label, log)
            return loaded[cache_key]

        for category in CATEGORIES:
            key, weight, scale = spec[category["key"]]
            source = None
            if key in CATALOG:
                source = catalog(key, weight)
            elif key.startswith("file:"):
                ok, message, source = check_user_font(self.user_files[key[5:]])
                if not ok:
                    raise RuntimeError(message)
                if source.axes:
                    source.axes["wght"] = int(weight) if str(weight).isdigit() else 400
            plan[category["key"]] = (source, scale)
            fill_weight = source.weight if source else (int(weight) if str(weight).isdigit() else 500)
            fill_weight = max(100, min(900, round(fill_weight / 100) * 100))
            fills[category["key"]] = [catalog(fill_key, str(fill_weight) if "var" in CATALOG[fill_key] else "Regular")
                                      for fill_key in category["fill"]]
        plan["__fills__"] = fills
        return plan

    # ---------- preview ----------
    def start_preview(self):
        spec = self.collect_plan_spec()
        include_han = self.rows["han"]["include"].get()

        def work(log):
            log("미리보기 준비 중...")
            plan = self.resolve_plan(spec, log)
            for source, _ in [v for k, v in plan.items() if k != "__fills__"]:
                if source:
                    source.cmap  # load cmaps in the worker
            for fills in plan["__fills__"].values():
                for fill in fills:
                    fill.cmap
            return plan, include_han

        self.run_task(work, self.show_plan_preview)

    def show_plan_preview(self, result):
        if not result:
            return
        self.current_plan, self.current_include_han = result
        self.built_source = None
        self.mode_label.configure(text="만들기 전 미리보기 (언어마다 고른 글꼴로 그림)")
        self.log("미리보기 완료. 마음에 들면 [글꼴 만들기]를 누르세요.")
        self.refresh_preview()

    def chooser_for_plan(self):
        plan, include_han = self.current_plan, self.current_include_han
        categories = [c for c in CATEGORIES if include_han or c["key"] != "han"]

        def choose(char):
            code = ord(char)
            for category in categories:
                if code in category["codes"]:
                    source, scale = plan[category["key"]]
                    if source and code in source.cmap:
                        return source, scale
                    for fill in plan["__fills__"][category["key"]]:
                        if code in fill.cmap:
                            return fill, 1.0
                    return None
            for category in categories:         # ASCII etc. outside the tables
                source, scale = plan[category["key"]]
                if source and code in source.cmap:
                    return source, scale
            return None
        return choose

    def refresh_preview(self):
        if self.built_source is not None:
            source = self.built_source

            def chooser(char, source=source):
                return (source, 1.0) if ord(char) in source.cmap else None
        elif getattr(self, "current_plan", None):
            chooser = self.chooser_for_plan()
        else:
            return
        try:
            size = max(10, min(40, int(self.size_var.get())))
        except ValueError:
            size = 20
        rows = []
        for category in CATEGORIES:
            if category["key"] == "han" and not self.rows["han"]["include"].get():
                rows.append((category["label"], category["sample"], chooser, ("빼고 만듦", PreviewRenderer.MUTED)))
                continue
            rows.append((category["label"], category["sample"], chooser, None))
        custom = self.custom_var.get().strip()
        if custom:
            rows.append(("직접 입력", custom, chooser, None))
        statuses = []
        for row in rows:
            missing = [c for c in row[1] if c != " " and not chooser(c)]
            if row[3]:
                statuses.append(row)
            elif missing:
                statuses.append((row[0], row[1], row[2], (f"없음 {len(missing)}자", PreviewRenderer.MISSING)))
            else:
                statuses.append((row[0], row[1], row[2], ("모두 표시", (110, 210, 110))))
        image, _ = self.renderer.render(statuses, size, width=max(560, self.preview_label.winfo_width() or 640))
        from PIL import ImageTk
        self.preview_image = ImageTk.PhotoImage(image)
        self.preview_label.configure(image=self.preview_image)

    # ---------- build ----------
    def start_build(self):
        family = re.sub(r"\s+", " ", self.name_var.get()).strip()
        if not re.fullmatch(r"[A-Za-z0-9 ]{2,40}", family):
            messagebox.showwarning(APP_TITLE, "글꼴 이름은 영문·숫자·공백 2~40자로 정해 주세요. (와우가 읽는 내부 이름)")
            return
        out_dir = Path(self.out_var.get().strip() or ".")
        spec = self.collect_plan_spec()
        include_han = self.rows["han"]["include"].get()
        metrics_key = next((c["key"] for c in CATEGORIES if c["label"] == self.metrics_var.get()), "hangul")
        self.save_current_settings()

        def work(log):
            log(f"'{family}' 만드는 중... (한자 포함 시 1~3분)")
            plan = self.resolve_plan(spec, log)
            reserved = []
            sources = [s for k, (s, _) in ((k, v) for k, v in plan.items() if k != "__fills__") if s]
            sources += [f for fills in plan["__fills__"].values() for f in fills]
            for source in sources:
                reserved += source.reserved
            for name in reserved:
                if name and name.lower() in family.lower():
                    raise RuntimeError(f"'{name}'은(는) 원본 글꼴의 예약 이름(Reserved Font Name)이라 새 글꼴 이름에 쓸 수 없어요. "
                                       "다른 이름을 정해 주세요.")
            out_dir.mkdir(parents=True, exist_ok=True)
            file_stem = re.sub(r"[^A-Za-z0-9]+", "-", family).strip("-")
            out_path = out_dir / f"{file_stem}.ttf"
            used = build_font(plan, family, str(out_path), include_han, metrics_key, log)
            write_license(out_dir / f"{file_stem}-LICENSE.txt", family, used)
            from fontTools.ttLib import TTFont
            cmap = set(TTFont(str(out_path), lazy=True).getBestCmap())
            listed = None
            if out_dir.name.lower() == "ezwow-myfonts":
                listed = write_myfonts_list(out_dir)
            return out_path, cmap, listed

        self.run_task(work, self.show_built)

    def show_built(self, result):
        if not result:
            return
        out_path, cmap, listed = result
        size_mb = out_path.stat().st_size / 1048576
        self.log(f"완성: {out_path} ({size_mb:.1f} MB)")
        self.log(f"라이선스 파일: {out_path.with_name(out_path.stem + '-LICENSE.txt').name} (글꼴과 함께 배포하세요)")
        if listed is not None:
            self.log(f"EzWoW-MyFonts 목록 갱신: {len(listed)}개. 게임을 다시 켜면 Font Changer에 나타납니다.")
        source = Source(out_path, out_path.stem)
        source._cmap = cmap
        self.built_source = source
        self.mode_label.configure(text=f"만든 글꼴로 테스트 중: {out_path.name}")
        lines = []
        for label, ratio in coverage_report(cmap):
            mark = "✓ 모두 표시" if ratio >= 0.999 else (f"△ {ratio * 100:.0f}%" if ratio > 0 else "✗ 없음")
            lines.append(f"{label}: {mark}")
        self.coverage_label.configure(text="만든 글꼴의 글자 포함 검사:  " + "   ".join(lines))
        self.refresh_preview()

    def save_current_settings(self):
        rows = {}
        for category in CATEGORIES:
            row = self.rows[category["key"]]
            key = self.row_key(category["key"])
            weight = row["weight"].get()
            if key == "galmuri11":
                weight = {"Regular": "", "Bold": "-Bold"}.get(weight, weight)
            rows[category["key"]] = {"font": key, "weight": weight, "scale": row["scale"].get()}
        self.settings.update({"rows": rows, "name": self.name_var.get(), "out_dir": self.out_var.get(),
                              "include_han": self.rows["han"]["include"].get(), "metrics": self.metrics_var.get(),
                              "custom_text": self.custom_var.get(), "user_files": self.user_files})
        save_settings(self.settings)


def main():
    if not ensure_dependencies():
        return
    root = tk.Tk()
    app = FontMakerApp(root)
    root.protocol("WM_DELETE_WINDOW", lambda: (app.save_current_settings(), root.destroy()))
    root.mainloop()


if __name__ == "__main__":
    main()

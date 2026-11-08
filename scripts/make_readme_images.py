#!/usr/bin/env python3
"""Draws the README mock-ups of EzWoW - Font Changer (docs/images/ui_*.png, settings_*.png).

The settings window, the More settings window, the per-language mix window and the
font test window are rebuilt from the sizes, coordinates, colours and strings in the
addon code (UI/OptionsWindow.lua, UI/FontTestWindow.lua, Core/UIKit.lua Theme,
Core/Init.lua, Core/Locales.lua, Data/FontList.lua), in game pixels x scale.
Text is drawn with the bundled fonts in Fonts/. Names in the examples are made up.

usage: python scripts/make_readme_images.py .
Renders with a local headless Chrome (set CHROME=<path> if it is not found).
"""
import html
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

PAGE_W = 1600
S = 1.0          # game px -> page px, set per window
UI_FONT = "EzWoW World Sans"   # the mock-up's game UI font (see STATE)

# ---------------------------------------------------------------------------
# Small readers for the Lua code
# ---------------------------------------------------------------------------


def read(root, rel):
    return (root / rel).read_text(encoding="utf-8")


def lua_table(src, start_pattern):
    """Text of the Lua table that starts at start_pattern (balanced braces)."""
    m = re.search(start_pattern, src)
    if not m:
        raise ValueError(start_pattern)
    i = src.index("{", m.start())
    depth = 0
    for j in range(i, len(src)):
        if src[j] == "{":
            depth += 1
        elif src[j] == "}":
            depth -= 1
            if depth == 0:
                return src[i + 1:j]
    raise ValueError("unbalanced " + start_pattern)


def unlua(v):
    return v.replace('\\"', '"').replace("\\n", "\n").replace("\\\\", "\\")


def lua_strings(block):
    """key = "value" pairs of a Lua table body."""
    return {k: unlua(v) for k, v in re.findall(r'(?:^|[\s,{])(\w+)\s*=\s*"((?:[^"\\]|\\.)*)"', block, re.M)}


def lua_list(block):
    """The string literals of a Lua list, in order."""
    return [unlua(v) for v in re.findall(r'"((?:[^"\\]|\\.)*)"', block)]


def lua_numbers(src, name):
    m = re.search(rf"local {name}\s*=\s*(-?\d+)", src)
    return int(m.group(1)) if m else None


def load(root):
    loc = read(root, "Core/Locales.lua")
    L = {}
    for code in ("koKR", "enUS"):
        t = lua_strings(lua_table(loc, rf"ns\.Locales\.{code} = \{{"))
        t.update(lua_strings(lua_table(lua_table(loc, r"local compactLabels = \{"), rf"\b{code} = \{{")))
        keys = lua_list(lua_table(loc, r"local helpKeys = \{"))
        vals = lua_list(lua_table(lua_table(loc, r"local helpText = \{"), rf"\b{code} = \{{"))
        t.update(zip(keys, vals))
        lang = lua_list(lua_table(lua_table(loc, r"local languageLabels = \{"), rf"\b{code} = \{{"))
        t["LANGUAGE"], t["LANGUAGE_AUTO"] = lang[0], lang[1]
        L[code] = t
    for k, v in L["enUS"].items():
        L["koKR"].setdefault(k, v)

    kit = read(root, "Core/UIKit.lua")
    theme = {k: [float(x) for x in v.split(",")] for k, v in
             re.findall(r"(\w+)\s*=\s*\{\s*([\d.,\s]+)\}", lua_table(kit, r"UIKit\.Theme = \{"))}
    init = read(root, "Core/Init.lua")
    targets = re.findall(r'"(\w+)"', re.search(r"ns\.TARGET_ORDER = \{([^}]*)\}", init).group(1))
    smin, smax, sstep = (int(v) for v in re.search(r"ns\.SCALE_MIN, ns\.SCALE_MAX, ns\.SCALE_STEP = (\d+), (\d+), (\d+)", init).groups())
    fl = read(root, "Data/FontList.lua")
    fonts = re.findall(r'\{ id = "(\w+)",\s*file = "([^"]+)",\s*name = "([^"]+)" \}', lua_table(fl, r"ns\.BUNDLED_FONTS = \{"))
    ow = read(root, "UI/OptionsWindow.lua")
    sample = unlua(re.search(r'local PREVIEW_SAMPLE = "((?:[^"\\]|\\.)*)"', ow).group(1))
    ff = read(root, "Modules/FontFamily.lua")
    alphabets = re.findall(r'"(\w+)"', re.search(r"ns\.FAMILY_ALPHABETS = \{([^}]*)\}", ff).group(1))
    tw = read(root, "UI/FontTestWindow.lua")
    tests = re.findall(r'\{ key = "(\w+)",\s*alphabet = "\w+",\s*sample = "((?:[^"\\]|\\.)*)" \}', lua_table(tw, r"local TEST_LINES = \{"))
    return {
        "L": {"ko": L["koKR"], "en": L["enUS"]}, "theme": theme, "targets": targets, "scale": (smin, smax, sstep),
        "fonts": fonts, "sample": sample, "alphabets": alphabets, "tests": tests,
        "W": lua_numbers(ow, "WINDOW_WIDTH"), "BLOCK_TOP": 112, "BLOCK_H": 84,
        "test_size": lua_numbers(tw, "SAMPLE_SIZE"), "test_row": lua_numbers(tw, "ROW_HEIGHT"),
        "font_dir": root / "Fonts",
    }


# ---------------------------------------------------------------------------
# HTML helpers (game px x S -> page px)
# ---------------------------------------------------------------------------
def px(v):
    return f"{v * S:.2f}px"


def esc(s):
    return html.escape(str(s), quote=False)


def css(c, alpha=None):
    r, g, b = (round(min(1, v) * 255) for v in c[:3])
    a = alpha if alpha is not None else (c[3] if len(c) > 3 else 1)
    return f"rgba({r},{g},{b},{a:.2f})"


def wow(s):
    """Game text -> HTML: |cffRRGGBB..|r colours and line breaks."""
    s = esc(s)
    s = re.sub(r"\|c[0-9a-fA-F]{2}([0-9a-fA-F]{6})", r'<span style="color:#\1">', s)
    s = s.replace("|r", "</span>")
    return s.replace("\n", "<br>")


SHADOW = "text-shadow:1px 1px 0 rgba(0,0,0,.85);"


def box(x, y, w, h, style="", inner=""):
    return f'<div class="abs" style="left:{px(x)};top:{px(y)};width:{px(w)};height:{px(h)};{style}">{inner}</div>'


def label(x, y, s, size, color, font=None, width=None, align="left", wrap=False, style=""):
    """A FontString whose TOPLEFT (or TOPRIGHT for align=right) is at x, y."""
    fam = f"font-family:'{font or UI_FONT}';"
    if align == "right":
        pos = f"right:calc(100% - {px(x)});"
    else:
        pos = f"left:{px(x)};"
    w = f"width:{px(width)};" if width else ""
    ws = "white-space:normal;" if wrap else "white-space:nowrap;overflow:hidden;text-overflow:ellipsis;"
    return (f'<div class="t" style="{pos}top:{px(y)};{w}font-size:{px(size)};color:{color};text-align:{align};'
            f'{ws}{fam}{SHADOW}{style}">{s}</div>')


class Win:
    """A flat EzWoW window as UIKit:ApplySurface draws it (1 px border)."""

    def __init__(self, th, w, h, border):
        self.th, self.w, self.h, self.border = th, w, h, border
        self.p = []

    def add(self, s):
        self.p.append(s)

    def button(self, x, y, w, h, text, font=None, size=12, align=None, border=None, color=None, arrow=False, fit=True):
        """fit: the label shrinks to the button like SettingsDialog.setButtonText (font buttons only cut off)."""
        th = self.th
        if align is None:
            align = "center" if w < 40 else "left"
        pad = 0 if w < 40 else 8
        right_pad = 22 if arrow else pad
        just = {"left": "flex-start", "center": "center"}[align]
        inner = (f'<span{' class="fit"' if fit else ''} style="font-family:\'{font or UI_FONT}\';font-size:{px(size)};color:{color or css(th["textBody"])};'
                 f'white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:100%;{SHADOW}">{text}</span>')
        if arrow:
            inner += (f'<span class="abs" style="right:{px(7)};top:50%;transform:translateY(-50%);font-size:{px(9)};'
                      f'color:{css(th["accent"])}">&#9660;</span>')
        self.p.append(box(x, y, w, h, f"background:{css(th['bgSecondary'])};border:1px solid {border or css(th['border'])};"
                                      f"display:flex;align-items:center;justify-content:{just};padding:0 {px(right_pad)} 0 {px(pad)}",
                          inner))

    def close(self, size, off):
        self.button(self.w - off - size, off, size, size, "x")

    def html(self, ox, oy):
        th = self.th
        return (f'<div class="abs" style="left:{ox:.0f}px;top:{oy:.0f}px;width:{px(self.w)};height:{px(self.h)};'
                f'background:{css(th["bgPrimary"])};border:1px solid {self.border};box-shadow:0 10px 40px rgba(0,0,0,.45)">'
                + "".join(self.p) + "</div>")


def callouts(points, start=1):
    return "".join(f'<div class="call" style="left:{x - 15:.0f}px;top:{y - 15:.0f}px">{start + i}</div>'
                   for i, (x, y) in enumerate(points))


def notes_block(x, y, w, notes, start=1, title=None):
    t = f'<div class="ntitle">{esc(title)}</div>' if title else ""
    rows = "".join(f'<div class="note"><span class="n">{start + i}</span><div><b>{esc(a)}</b> — {esc(b)}</div></div>'
                   for i, (a, b) in enumerate(notes))
    return f'<div class="notes" style="left:{x:.0f}px;top:{y:.0f}px;width:{w:.0f}px">{t}{rows}</div>'


def heading(title, lead, badge=None):
    b = f' <span class="badge">{esc(badge)}</span>' if badge else ""
    return f'<div class="page"><h1>{esc(title)}{b}</h1><div class="lead">{esc(lead)}</div></div>'


def page_css(ctx):
    acc = "#%02x%02x%02x" % tuple(round(v * 255) for v in ctx["theme"]["accent"][:3])
    faces = "".join(f"@font-face {{ font-family: '{name}'; src: url('{(ctx['font_dir'] / file).as_uri()}'); }}\n"
                    for _, file, name in ctx["fonts"])
    return faces + f"""
* {{ box-sizing: border-box; margin: 0; padding: 0; }}
html, body {{ width: {PAGE_W}px; overflow: hidden; }}
body {{ background: radial-gradient(ellipse at 25% 0%, #1d2b38 0%, #151f28 45%, #10171d 75%, #0c1115 100%);
  font-family: '{UI_FONT}', sans-serif; color: #edf4f7; position: relative; }}
.page {{ position: relative; padding: 34px 50px 0; }}
h1 {{ color: {acc}; font-size: 40px; font-weight: 700; display: flex; align-items: center; gap: 14px; }}
h1 .badge {{ font-size: 15px; background: {acc}; color: #10161c; padding: 2px 9px; border-radius: 5px; }}
.lead {{ color: #d5dde2; font-size: 19px; margin-top: 6px; }}
.abs {{ position: absolute; }}
.t {{ position: absolute; line-height: 1.25; }}
.call {{ position: absolute; width: 30px; height: 30px; border-radius: 50%; background: {acc}; color: #10161c; font-weight: 700;
  font-size: 16px; display: flex; align-items: center; justify-content: center; border: 2px solid #10161c; box-shadow: 0 0 0 2px {acc}55; z-index: 60; }}
.notes {{ position: absolute; }}
.ntitle {{ color: {acc}; font-size: 18px; font-weight: 700; margin: 8px 0 10px 40px; }}
.note {{ display: flex; gap: 12px; margin-bottom: 11px; font-size: 16px; line-height: 1.5; color: #dfe6ea; }}
.note .n {{ flex: none; width: 28px; height: 28px; border-radius: 50%; background: {acc}; color: #10161c; font-weight: 700;
  font-size: 15px; display: flex; align-items: center; justify-content: center; }}
.note b {{ color: #fff; }}
.foot {{ position: absolute; left: 50px; width: 1500px; color: #7d8d98; font-size: 13.5px; line-height: 1.5; }}
.card {{ position: absolute; border: 1px solid #344c5b; background: rgba(18,24,31,.92); padding: 9px 12px; }}
.card .nm {{ color: {acc}; font-size: 12px; }}
.card .sm {{ color: #edf4f7; font-size: 21px; white-space: nowrap; margin-top: 2px; }}
.chat {{ position: absolute; border: 1px solid #344c5b; background: rgba(8,12,16,.85); padding: 14px 18px; font-size: 21px; line-height: 1.5; }}
.mark {{ position: absolute; width: 30px; height: 30px; border-radius: 50%; display: flex; align-items: center; justify-content: center; font-size: 17px; }}
.cap {{ position: absolute; font-size: 19px; color: #e6edf1; }}
.bul {{ position: absolute; font-size: 17px; line-height: 2; color: #dfe6ea; white-space: nowrap; }}
.sec {{ position: absolute; font-size: 19px; font-weight: 700; color: #edf4f7; }}
"""


# ---------------------------------------------------------------------------
# Example state (what the windows show)
# ---------------------------------------------------------------------------
STATE = {   # target -> (font name or "inherit", scale %, needs relog)
    "ui": ("EzWoW World Sans", 100, False),
    "chat": ("EzWoW Jua", 100, False),
    "tooltip": ("inherit", 100, False),
    "combat": ("EzWoW Black Han Sans", 120, True),
    "nameplate": ("EzWoW Sans Bold", 100, True),
}
FAMILY = {"roman": "EzWoW Diphylleia", "korean": "EzWoW Jua", "simplifiedchinese": "EzWoW World Sans",
          "traditionalchinese": "EzWoW World Sans", "russian": "EzWoW World Sans"}
CUSTOM = [("font1.ttf", True, "EzWoW Gugi"), ("MyHandwriting.ttf", False, "EzWoW Single Day")]
TEST_INPUT_TEXT = "Mirelle 月影 Лиора ★"


def settings_window(ctx, L):
    th = ctx["theme"]
    W = ctx["W"]
    H = 546 + (len(ctx["targets"]) - 4) * ctx["BLOCK_H"]
    win = Win(th, W, H, css(th["border"]))
    acc, body, muted, warn = css(th["accent"]), css(th["textBody"]), css(th["textMuted"]), css(th["warning"])
    win.add(box(1, 1, W - 2, 2, f"background:{acc}"))
    win.add(label(18, 14, esc(L["TITLE"]), 16, acc))
    win.add(label(18, 36, esc(L["SIMPLE_SUBTITLE"]), 10, muted, width=W - 40))
    win.close(24, 10)
    # language combo box: TOPRIGHT -42, -11; label to its left
    win.button(W - 42 - 160, 11, 160, 22, esc(L["LANGUAGE_AUTO"]), arrow=True)
    win.add(label(W - 42 - 160 - 6, 16, esc(L["LANGUAGE"]), 10, muted, align="right"))
    win.button(20, 66, W - 40, 28, esc(L["ALL_FONTS"]), align="center")
    rows = {}
    for i, key in enumerate(ctx["targets"]):
        top = ctx["BLOCK_TOP"] + i * ctx["BLOCK_H"]
        rows[key] = top
        font, scale, relog = STATE[key]
        face = STATE["ui"][0] if font == "inherit" else font
        name = L["FONT_INHERIT_UI"] if font == "inherit" else font
        win.add(label(20, top, esc(L["TARGET_" + key]), 12, acc, width=280))
        if relog:
            win.add(label(W - 20, top + 1, esc(L["NOTE_RELOG_SHORT"]), 10, warn, width=180, align="right"))
        win.button(20, top + 20, 286, 26, esc(name), font=face, size=13, fit=False)
        if key != "chat":
            win.add(label(316, top + 27, esc(L["SIZE"]), 10, muted, width=36))
            win.button(356, top + 20, 26, 26, "-")
            win.button(384, top + 20, 52, 26, f"{scale}%", align="center")
            win.button(438, top + 20, 26, 26, "+")
        win.button(472, top + 20, 28, 26, "R")
        size = 15 if key == "chat" else round(15 * scale / 100)
        win.add(label(22, top + 54, esc(ctx["sample"]), size, body, font=face, width=W - 44))
    win.add(label(20, 450 + (len(ctx["targets"]) - 4) * ctx["BLOCK_H"], wow(L["QUICK_HINT"]), 10, muted, width=W - 40, wrap=True))
    for x, key in ((20, "RESET_ALL"), ((W - 140) / 2, "ADVANCED"), (W - 20 - 140, "RELOAD")):
        win.button(x, H - 16 - 30, 140, 30, esc(L[key]), align="center")
    return win, rows


def advanced_window(ctx, L):
    th = ctx["theme"]
    W, H = ctx["W"], 366
    win = Win(th, W, H, css(th["accent"]))
    acc, body, muted = css(th["accent"]), css(th["textBody"]), css(th["textMuted"])
    win.add(label(20, 16, esc(L["ADVANCED"]), 16, acc))
    win.close(24, 10)
    win.button(20, 56, 230, 28, esc(L["FAMILY_BUTTON"]), align="center")
    win.button(W - 20 - 240, 56, 240, 28, esc(L["TEST_BUTTON"]), align="center")
    top = 108
    win.add(label(20, top, esc(L["CUSTOM_TITLE"]), 12, acc))
    win.add(label(20, top + 20, wow(L["CUSTOM_HINT_SHORT"]), 10, muted, width=W - 40, wrap=True))
    win.add(box(20, top + 64, 330, 26, f"background:{css(th['bgInput'])};border:1px solid {css(th['border'])}"))
    win.button(360, top + 64, 100, 26, esc(L["CUSTOM_ADD"]), align="center")
    for i, (file, auto, face) in enumerate(CUSTOM):
        row_top = top + 96 + i * 24
        tag = f'  <span style="color:#a7b9c5">({esc(L["SRC_auto"])})</span>' if auto else ""
        win.add(label(22, row_top + 4, esc(file) + tag, 13, body, font=face, width=330))
        if not auto:
            win.button(360, row_top, 100, 22, esc(L["CUSTOM_REMOVE"]), align="center")
    return win


def family_window(ctx, L):
    th = ctx["theme"]
    W, H = 400, 150 + len(ctx["alphabets"]) * 34
    win = Win(th, W, H, css(th["accent"]))
    acc, body, muted = css(th["accent"]), css(th["textBody"]), css(th["textMuted"])
    win.add(label(16, 14, esc(L["FAMILY_TITLE"]), 12, acc))
    win.add(label(16, 34, esc(L["FAMILY_HINT"]), 10, muted, width=368, wrap=True))
    win.close(22, 8)
    for i, alpha in enumerate(ctx["alphabets"]):
        top = 78 + i * 34
        win.add(label(16, top + 6, esc(L["ALPHA_" + alpha]), 12, body, width=140))
        win.button(164, top, 220, 26, esc(FAMILY[alpha]), font=FAMILY[alpha], size=13, fit=False)
    win.button(16, H - 44 - 28, 368, 28, esc(L["PRESET_BUTTON"]), align="center", border=acc)
    # preview: each part in the font of its language
    parts = []
    for word in L["FAMILY_PREVIEW"].split(" "):
        if re.search(r"[가-힣]", word):
            f = FAMILY["korean"]
        elif re.search(r"[\u0400-\u04ff]", word):
            f = FAMILY["russian"]
        elif re.search(r"[\u4e00-\u9fff]", word):
            f = FAMILY["simplifiedchinese"]
        else:
            f = FAMILY["roman"]
        parts.append(f'<span style="font-family:\'{f}\'">{esc(word)}</span>')
    win.add(label(16, H - 16 - 19, " ".join(parts), 15, body, width=368))
    return win


def test_window(ctx, L):
    th = ctx["theme"]
    rows_h = ctx["test_row"]
    W, H = 470, 196 + len(ctx["tests"]) * rows_h
    win = Win(th, W, H, css(th["accent"]))
    acc, body, muted = css(th["accent"]), css(th["textBody"]), css(th["textMuted"])
    face = STATE["chat"][0]
    win.add(label(16, 14, esc(L["TEST_TITLE"]), 12, acc))
    win.add(label(16, 34, esc(L["TEST_HINT"]), 10, muted, width=438, wrap=True))
    win.close(22, 8)
    win.button(16, 66, 438, 26, esc(L["TEST_TARGET"].replace("%s", L["TARGET_chat"], 1).replace("%s", face, 1)))
    ok = css((0.45, 0.85, 0.45, 1))
    for i, (key, sample) in enumerate(ctx["tests"]):
        top = 102 + i * rows_h
        win.add(label(16, top + 4, esc(L["LANG_" + key]), 10, muted, width=78))
        win.add(label(98, top, esc(sample), ctx["test_size"], body, font=face, width=280))
        win.add(label(W - 16, top + 4, esc(L["STATUS_OK"]), 10, ok, width=76, align="right"))
    input_top = 110 + len(ctx["tests"]) * rows_h
    win.add(label(16, input_top, esc(L["TEST_INPUT"]), 10, muted))
    win.add(box(16, input_top + 16, 438, 26, f"background:{css(th['bgInput'])};border:1px solid {css(th['border'])}",
                label(8, 4, esc(TEST_INPUT_TEXT), 14, body, font=face)))
    win.add(label(18, input_top + 52, esc(TEST_INPUT_TEXT), ctx["test_size"], body, font=face, width=434))
    return win


# ---------------------------------------------------------------------------
# Pages
# ---------------------------------------------------------------------------
T = {
    "ko": {
        "sLead": "/ezfont · 영역별 글꼴과 크기, 전체 변경, 추가 설정(내 글꼴 · 언어별 조합 · 글꼴 테스트)",
        "sBadge": "설정창",
        "notes": [
            ("언어", "상자를 누르고 목록에서 고릅니다(자동 + 8개 언어). 고르면 바로 바뀝니다."),
            ("전체 글꼴 변경", "다섯 영역의 글꼴을 한 번에 바꿉니다. 영역별 크기는 그대로 둡니다."),
            ("영역별 글꼴", "게임 UI · 채팅창 · 툴팁 · 전투 숫자 · 이름표마다 글꼴을 고르면 바로 적용되고, 아래 줄에 여러 언어 예문이 그 글꼴로 보입니다. 마우스를 올리면 영역별 설명이 나옵니다."),
            ("크기 · 초기화", "- / + 로 70~150%(5% 단위), 가운데 숫자를 누르면 100%, R은 그 영역만 기본값. 채팅 크기는 채팅 탭 우클릭 → 글꼴 크기에서 바꿉니다."),
            ("툴팁", "처음에는 '게임 UI 글꼴 따름'. 글꼴과 크기를 따로 정할 수도 있습니다."),
            ("전투 숫자 · 이름표", "글꼴 파일은 캐릭터 선택 화면에 나갔다 들어오면 바뀝니다. 그때까지 '재접속 후 적용'이 보입니다."),
            ("아래 단추", "모두 기본값, 추가 설정(아래 창), UI 다시 불러오기."),
        ],
        "moreTitle": "추가 설정",
        "more": [
            ("추가 설정", "언어별 조합 · 글꼴 테스트 단추와 내 글꼴 추가. EzWoW-MyFonts 폴더의 font1.ttf~font30.ttf와 목록 파일의 글꼴은 자동으로 들어오고, 다른 이름은 입력해서 추가합니다."),
            ("언어별 글꼴 조합", "영어·유럽 문자, 한글, 중국어 간체·번체, 러시아어마다 글꼴을 고르고, 영역 글꼴에서 '언어별 조합'을 고르면 글자마다 그 언어의 글꼴로 그립니다."),
            ("글꼴 테스트", "고른 영역의 글꼴로 7개 언어 예문을 그려 보고 '모두 표시 / 일부만 / 글자 없음'을 알려 줍니다. 직접 입력한 이름도 확인합니다."),
        ],
        "sFoot": "애드온 코드의 창 크기·좌표·색상·문구와 포함된 글꼴로 재현한 예시 화면입니다. 세 창은 실제로는 설정창 옆에 붙어서 열립니다. 글꼴 선택과 이름은 예시입니다.",
        "lead": "기본 글꼴 22종 · 모두 한글·영어·러시아어·그리스어·일본어와 자주 쓰는 한자 8,836자 이상 포함 → 다른 나라 채팅·이름이 상자(□)로 깨지지 않음",
        "before": "게임 기본 글꼴 (한국어 클라이언트)",
        "after": "EzWoW 글꼴 적용 후",
        "grid": "기본 포함 글꼴 22종",
        "chat": [("#40ff40", "길드", "하늘별", "오늘 저녁 던전 가실 분?"),
                 ("#aaaaff", "파티", "林月影", "我来坦克，马上到"),
                 ("#ffc0c0", "일반", "Ветрана", "Привет! ищу группу"),
                 ("#aaaaff", "파티", "陳小雨", "謝謝大家，辛苦了")],
        "bullets": ["게임 UI · 채팅창 · 툴팁 · 전투 숫자 · 이름표 따로 설정",
                    "전체 글꼴 한 번에 변경 · 영역별 크기 70~150%",
                    "내 글꼴 폴더(EzWoW-MyFonts) 자동 인식",
                    "언어별 조합 · 언어별 글꼴 테스트",
                    "8개 언어 설정창 · 항목마다 마우스 오버 설명"],
        "foot": "포함된 글꼴로 그린 예시 화면입니다. 채팅 내용과 이름은 지어낸 예시입니다.",
    },
    "en": {
        "sLead": "/ezfont · font and size per area, change all, More settings (my fonts · per-language mix · font test)",
        "sBadge": "Settings",
        "notes": [
            ("Language", "Click the box and pick from the list (Automatic + 8 languages). It changes right away."),
            ("Change all fonts", "Sets the font of all five areas at once. Each area keeps its size."),
            ("Font per area", "Pick a font for the game UI, chat, tooltips, combat numbers and nameplates; it applies at once and the line below shows a sample in several languages. Hover for help on each area."),
            ("Size · reset", "- / + for 70–150% (5% steps), click the number for 100%, R resets only that area. Chat size: right-click a chat tab > Font Size."),
            ("Tooltips", "Follow the game UI font at first, or get their own font and size."),
            ("Combat numbers · nameplates", "Font files change after you return to character select and log in again; until then the area shows a note."),
            ("Bottom buttons", "Reset all, More settings (windows below), Reload UI."),
        ],
        "moreTitle": "More settings",
        "more": [
            ("More settings", "Buttons for the per-language mix and the font test, plus Add my font. font1.ttf–font30.ttf and listed files in the EzWoW-MyFonts folder are found automatically; other names are typed in."),
            ("Per-language font mix", "Pick a font for Latin, Korean, Simplified and Traditional Chinese and Russian, then choose 'Per-language mix' as an area's font: every character is drawn with the font of its language."),
            ("Font test", "Draws samples in 7 languages with the chosen area's font and says All shown / Partly / Missing. Type a name to check it too."),
        ],
        "sFoot": "Mock-up rebuilt from the window sizes, coordinates, colours and strings in the addon code, drawn with the bundled fonts. In game the three windows open next to the settings window. Font choices and names are examples.",
        "lead": "22 bundled fonts · each has Hangul, Latin, Cyrillic, Greek, kana and 8,836+ everyday Han characters → names and chat from other regions no longer show as boxes (□)",
        "before": "Game default font (English client)",
        "after": "With an EzWoW font",
        "grid": "22 bundled fonts",
        "chat": [("#40ff40", "Guild", "하늘별", "오늘 저녁 던전 가실 분?"),
                 ("#aaaaff", "Party", "林月影", "我来坦克，马上到"),
                 ("#ffc0c0", "General", "Ветрана", "Привет! ищу группу"),
                 ("#aaaaff", "Party", "陳小雨", "謝謝大家，辛苦了")],
        "bullets": ["Own font for UI, chat, tooltips, combat numbers, nameplates",
                    "Change all fonts at once · size 70–150% per area",
                    "Fonts in your EzWoW-MyFonts folder are found automatically",
                    "Per-language mix · per-language font test",
                    "Settings in 8 languages · hover help on every control"],
        "foot": "Example drawn with the bundled fonts. Chat lines and names are made up.",
    },
}


def settings_page(ctx, lang):
    global S
    t, L = T[lang], ctx["L"][lang]
    W = ctx["W"]
    sc = 1.15
    S = sc
    win, rows = settings_window(ctx, L)
    ox, oy = 60, 150
    H = win.h
    parts = [heading("EzWoW - Font Changer", t["sLead"], t["sBadge"]), win.html(ox, oy)]
    rx = ox + W * sc + 26
    pts = [(rx, oy + 22 * sc), (rx, oy + 80 * sc), (ox - 20, oy + (rows["ui"] + 33) * sc),
           (rx, oy + (rows["ui"] + 33) * sc), (rx, oy + (rows["tooltip"] + 33) * sc),
           (rx, oy + (rows["combat"] + rows["nameplate"] + 66) / 2 * sc), (rx, oy + (H - 31) * sc)]
    parts.append(callouts(pts))
    nx = ox + W * sc + 78
    parts.append(notes_block(nx, oy + 6, PAGE_W - nx - 40, t["notes"]))
    parts.append(notes_block(nx, oy + 470, PAGE_W - nx - 40, t["more"], start=8, title=t["moreTitle"]))
    # second row: More settings, per-language mix and font test windows at 1:1
    y2 = oy + H * sc + 60
    S = 1.0
    adv, fam, tst = advanced_window(ctx, L), family_window(ctx, L), test_window(ctx, L)
    x1, x2 = 50, 50 + adv.w + 20
    x3 = x2 + fam.w + 20
    parts += [adv.html(x1, y2), fam.html(x2, y2), tst.html(x3, y2)]
    parts.append(callouts([(x1 + 4, y2 + 4), (x2 + 4, y2 + 4), (x3 + 4, y2 + 4)], start=8))
    bottom = y2 + max(adv.h, fam.h, tst.h)
    parts.append(f'<div class="foot" style="top:{bottom + 26:.0f}px">{esc(t["sFoot"])}</div>')
    return "".join(parts), bottom + 90


def boxed(text):
    """What the game font of a Latin / Korean client draws: Han as boxes."""
    return re.sub(r"[\u3000-\u303f\u4e00-\u9fff\uff00-\uffef]", "□", text)


def boxed_en(text):
    return re.sub(r"[\u3000-\u303f\u4e00-\u9fff\uff00-\uffef\uac00-\ud7a3]", "□", text)


def ui_page(ctx, lang):
    t = T[lang]
    acc = "#%02x%02x%02x" % tuple(round(v * 255) for v in ctx["theme"]["accent"][:3])
    fix = boxed if lang == "ko" else boxed_en
    parts = [heading("EzWoW - Font Changer", t["lead"])]

    def chat(y, font, convert):
        lines = "".join(f'<div style="color:{c}">[{esc(ch)}] [{esc(convert(n))}]: {esc(convert(m))}</div>' for c, ch, n, m in t["chat"])
        return f'<div class="chat" style="left:50px;top:{y}px;width:560px;height:190px;font-family:{font}">{lines}</div>'

    parts.append('<div class="mark" style="left:50px;top:150px;background:#3a4650;color:#c8d2d8">&#10005;</div>'
                 f'<div class="cap" style="left:92px;top:151px">{esc(t["before"])}</div>')
    parts.append(chat(190, "'Malgun Gothic','Segoe UI',sans-serif", fix))
    parts.append(f'<div class="mark" style="left:50px;top:408px;background:{acc};color:#10161c">&#10003;</div>'
                 f'<div class="cap" style="left:92px;top:409px;font-weight:700">{esc(t["after"])}</div>')
    parts.append(chat(448, "'EzWoW Jua'", lambda s: s))
    parts.append('<div class="bul" style="left:50px;top:668px;width:560px">'
                 + "".join(f"<div>• {esc(b)}</div>" for b in t["bullets"]) + "</div>")
    parts.append(f'<div class="sec" style="left:660px;top:150px">{esc(t["grid"])}</div>')
    cw, ch_, gap = 288, 62, 8
    for i, (_, _, name) in enumerate(ctx["fonts"]):
        x = 660 + (i % 3) * (cw + gap)
        y = 186 + (i // 3) * (ch_ + gap)
        parts.append(f'<div class="card" style="left:{x}px;top:{y}px;width:{cw}px;height:{ch_}px">'
                     f'<div class="nm">{esc(name)}</div><div class="sm" style="font-family:\'{name}\'">가나다 Abc 简体 繁體 Кир</div></div>')
    rows = -(-len(ctx["fonts"]) // 3)
    bottom = max(186 + rows * (ch_ + gap), 668 + 34 * len(t["bullets"]) + 10)
    parts.append(f'<div class="foot" style="top:{bottom + 22}px">{esc(t["foot"])}</div>')
    return "".join(parts), bottom + 80


# ---------------------------------------------------------------------------
# Rendering (local headless Chrome)
# ---------------------------------------------------------------------------
def find_chrome():
    cands = [os.environ.get("CHROME"), r"C:\Program Files\Google\Chrome\Application\chrome.exe",
             r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
             shutil.which("chrome"), shutil.which("google-chrome"), shutil.which("chromium")]
    for c in cands:
        if c and Path(c).exists():
            return c
    sys.exit("Chrome not found (set CHROME=<path to chrome>)")


FIT_JS = """<script>
document.querySelectorAll('.fit').forEach(function (e) {
  var fs = parseFloat(getComputedStyle(e).fontSize), min = fs * 0.6;
  while (e.scrollWidth > e.clientWidth && fs > min) { fs -= 0.25; e.style.fontSize = fs + 'px'; }
});
</script>"""


def stop(proc):
    """Ends Chrome and its child processes."""
    if proc.poll() is None:
        if os.name == "nt":
            subprocess.run(["taskkill", "/T", "/F", "/PID", str(proc.pid)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        else:
            proc.kill()
    proc.wait()


def screenshot(cmd, out_png, timeout=180):
    """Runs headless Chrome until the screenshot file is written (Chrome may not exit by itself)."""
    if out_png.exists():
        out_png.unlink()
    proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        start, last = time.time(), -1
        while time.time() - start < timeout:
            if out_png.exists():
                size = out_png.stat().st_size
                if size > 0 and size == last:
                    return
                last = size
            elif proc.poll() is not None:
                raise RuntimeError(f"Chrome ended without writing {out_png}")
            time.sleep(0.5)
        raise TimeoutError(f"no screenshot after {timeout}s: {out_png}")
    finally:
        stop(proc)


def render(chrome, ctx, body, height, out_png, tmp):
    doc = (f'<!doctype html><html><head><meta charset="utf-8"><style>{page_css(ctx)}</style></head>'
           f'<body style="height:{int(height)}px">{body}{FIT_JS}</body></html>')
    page = Path(tmp) / (out_png.stem + ".html")
    page.write_text(doc, encoding="utf-8")
    # the bundled fonts are local files: allow the page to load them
    screenshot([chrome, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
                "--allow-file-access-from-files", f"--user-data-dir={Path(tmp) / 'chrome_profile'}",
                "--virtual-time-budget=8000", f"--window-size={PAGE_W},{int(height)}", f"--screenshot={out_png}",
                page.as_uri()], out_png)


def main(root: Path):
    ctx = load(root)
    out = root / "docs" / "images"
    out.mkdir(parents=True, exist_ok=True)
    chrome = find_chrome()
    tmp = tempfile.mkdtemp(prefix="ezfont_readme_")
    try:
        for lang in ("ko", "en"):
            for name, fn in (("ui", ui_page), ("settings", settings_page)):
                body, h = fn(ctx, lang)
                png = out / f"{name}_{lang}.png"
                render(chrome, ctx, body, h, png, tmp)
                print("wrote", png, int(h))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main(Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve())

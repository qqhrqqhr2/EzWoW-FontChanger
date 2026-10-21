--===========================================================================
-- EzWoW - Font Changer
-- Data/FontList.lua : Bundled Fonts (SIL Open Font License) & Font Catalog
--===========================================================================
local _, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

-- Every bundled font contains all of Latin (with accents), Greek, Cyrillic,
-- Hangul, kana, common symbols and the 8,836 Han characters in everyday use
-- (GB2312 + Big5 level 1); World Sans has every Han character.
-- Exact coverage lives in Data/FontCoverage.lua.
ns.BUNDLED_FONTS = {
    { id = "worldsans",   file = "EzWoW-WorldSans-Medium.ttf", name = "EzWoW World Sans" },
    { id = "sansbold",    file = "EzWoW-SansBold.ttf",         name = "EzWoW Sans Bold" },
    { id = "roundgothic", file = "EzWoW-RoundGothic.ttf",      name = "EzWoW Round Gothic" },
    { id = "softdodum",   file = "EzWoW-SoftDodum.ttf",        name = "EzWoW Soft Dodum" },
    { id = "gothic",      file = "EzWoW-Gothic.ttf",           name = "EzWoW Gothic" },
    { id = "myeongjo",    file = "EzWoW-Myeongjo.ttf",         name = "EzWoW Myeongjo" },
    { id = "neatsans",    file = "EzWoW-NeatSans.ttf",         name = "EzWoW Neat Sans" },
    { id = "techsans",    file = "EzWoW-TechSans.ttf",         name = "EzWoW Tech Sans" },
    { id = "jua",         file = "EzWoW-Jua.ttf",              name = "EzWoW Jua" },
    { id = "dohyeon",     file = "EzWoW-DoHyeon.ttf",          name = "EzWoW Do Hyeon" },
    { id = "blackhansans", file = "EzWoW-BlackHanSans.ttf",    name = "EzWoW Black Han Sans" },
    { id = "songmyung",   file = "EzWoW-SongMyung.ttf",        name = "EzWoW Song Myung" },
    { id = "penscript",   file = "EzWoW-PenScript.ttf",        name = "EzWoW Pen Script" },
    { id = "gaegu",       file = "EzWoW-Gaegu.ttf",            name = "EzWoW Gaegu" },
    { id = "pixel",       file = "EzWoW-Pixel.ttf",            name = "EzWoW Pixel" },
}

-- ids from the first test build, mapped to their replacements
ns.RENAMED_FONT_IDS = {
    ["bundled:pretendard"] = "bundled:worldsans",
    ["bundled:pretendard-bold"] = "bundled:sansbold",
    ["bundled:nanumgothic"] = "bundled:gothic",
    ["bundled:nanumgothic-bold"] = "bundled:gothic",
    ["bundled:nanummyeongjo"] = "bundled:myeongjo",
}

-- coverage key for the letters of each client language
local CLIENT_COVERAGE_KEY = {
    koKR = "korean", ruRU = "cyrillic", zhCN = "chinese", zhTW = "chinese",
}

function ns:ClientCoverageKey()
    return CLIENT_COVERAGE_KEY[GetLocale and GetLocale() or ""] or "latin"
end

-- 0..1 share of a test alphabet the font contains; nil when unknown (game / custom fonts)
function ns:FontCoverage(entry, coverageKey)
    local file = entry and entry.file
    local coverage = file and self.FONT_COVERAGE and self.FONT_COVERAGE[file]
    return coverage and coverage[coverageKey]
end

local LSM_LOCALE_MASK = {   -- which client locales each alphabet serves (LibSharedMedia bits)
    latin = "LOCALE_BIT_western", korean = "LOCALE_BIT_koKR", cyrillic = "LOCALE_BIT_ruRU",
    chinese = "LOCALE_BIT_zhCN",
}

local function sharedMedia()
    local libStub = _G.LibStub
    return libStub and libStub("LibSharedMedia-3.0", true)
end

-- Every selectable font: { id, name, path, file?, source, multilingual? }
-- source: "bundled" | "custom" | "shared" (fonts other addons registered)
function ns:FontCatalog()
    local list = {}
    for _, font in ipairs(self.BUNDLED_FONTS) do
        local hasHan = (self:FontCoverage(font, "chinese") or 0) > 0.99
        -- a font without everyday Han would get World Sans for Chinese automatically (ns:UsesFamily)
        list[#list + 1] = { id = "bundled:" .. font.id, name = font.name, file = font.file, path = self.FONT_PATH .. font.file,
            source = "bundled", multilingual = hasHan, autoMix = not hasHan }
    end
    for _, custom in ipairs(self:CustomFontFiles()) do
        list[#list + 1] = { id = "custom:" .. custom.file, name = (custom.file:gsub("%.[OoTt][Tt][Ff]$", "")), path = self:CustomFontPath(custom.file), source = "custom", auto = custom.auto }
    end
    local media = sharedMedia()
    if media and media.List then
        local seen = {}
        for _, entry in ipairs(list) do seen[(entry.path or ""):lower()] = true end
        for _, mediaName in ipairs(media:List("font") or {}) do
            local path = media:Fetch("font", mediaName, true)
            if type(path) == "string" and not seen[path:lower()] then
                seen[path:lower()] = true
                list[#list + 1] = { id = "shared:" .. mediaName, name = mediaName, path = path, source = "shared" }
            end
        end
    end
    return list
end

-- Lets other addons (EllesmereUI, ElvUI, WeakAuras ...) pick the bundled
-- fonts in their own font menus.
function ns:RegisterSharedMediaFonts()
    local media = sharedMedia()
    if not (media and media.Register) or self.sharedMediaRegistered then return end
    self.sharedMediaRegistered = true
    for _, font in ipairs(self.BUNDLED_FONTS) do
        local mask = 0
        for coverageKey, bitName in pairs(LSM_LOCALE_MASK) do
            if (self:FontCoverage(font, coverageKey) or 0) > 0.99 and media[bitName] then mask = mask + media[bitName] end
        end
        if mask > 0 and (self:FontCoverage(font, "chinese") or 0) > 0.99 and media.LOCALE_BIT_zhTW then mask = mask + media.LOCALE_BIT_zhTW end
        pcall(media.Register, media, "font", font.name, self.FONT_PATH .. font.file, mask > 0 and mask or nil)
    end
end

-- Fonts in the player's folder. WoW can't list a folder, so files are found by
--  1) the numbered names font1.ttf .. font30.ttf, probed once per session,
--  2) EzWoW_MyFonts, a list written by tools/make_myfonts (real file names),
--  3) names typed in the settings window (db.customFonts).
ns.AUTO_FONT_COUNT = 30
local detectedFiles

function ns:DetectFolderFonts()
    detectedFiles = {}
    local seen = {}
    local function add(file)
        if type(file) ~= "string" or file == "" or seen[file:lower()] then return end
        seen[file:lower()] = true
        if self:IsFontFileUsable(self:CustomFontPath(file)) then
            detectedFiles[#detectedFiles + 1] = { file = file, auto = true }
        end
    end
    for index = 1, self.AUTO_FONT_COUNT do
        add("font" .. index .. ".ttf")
        add("font" .. index .. ".otf")
    end
    for _, file in ipairs(type(_G.EzWoW_MyFonts) == "table" and _G.EzWoW_MyFonts or {}) do add(file) end
    return detectedFiles
end

function ns:CustomFontFiles()
    local files, seen = {}, {}
    for _, found in ipairs(detectedFiles or {}) do
        seen[found.file:lower()] = true
        files[#files + 1] = found
    end
    for _, custom in ipairs((self.db and self.db.customFonts) or {}) do
        if not seen[custom.file:lower()] then
            seen[custom.file:lower()] = true
            files[#files + 1] = { file = custom.file }
        end
    end
    return files
end

function ns:CustomFontPath(file)
    if file:find("\\", 1, true) or file:find("/", 1, true) then
        return (file:gsub("/", "\\"))   -- full path typed by the player
    end
    return self.CUSTOM_FONT_DIR .. file
end

-- nil for "default" (the game's own font) or a font that no longer exists
function ns:ResolveFont(fontId)
    if not fontId or fontId == "default" then return nil end
    if fontId == "family" then return self:FamilyEntry() end
    for _, entry in ipairs(self:FontCatalog()) do
        if entry.id == fontId then return entry end
    end
end

function ns:FontLacksClientScript(entry)
    local coverage = self:FontCoverage(entry, self:ClientCoverageKey())
    return coverage ~= nil and coverage < 0.99
end

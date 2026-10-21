--===========================================================================
-- EzWoW - Font Changer
-- Modules/FontFamily.lua : Per-Alphabet Font Combination (CreateFontFamily)
--===========================================================================
local _, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

-- The client draws each character with the member font for its alphabet,
-- so one "font" can mix e.g. Pretendard for Latin and NanumGothic for Hangul.
ns.FAMILY_ALPHABETS = { "roman", "korean", "simplifiedchinese", "traditionalchinese", "russian" }

local CLIENT_ALPHABET = {
    koKR = "korean", zhCN = "simplifiedchinese", zhTW = "traditionalchinese", ruRU = "russian",
}

local familyCache = {}        -- ["target|size|flags"] = font family object
local familySerial = 0        -- family names must be unique, so every build gets a new one

function ns:FamilySupported()
    return type(CreateFontFamily) == "function"
end

function ns:FamilyEntry()
    if not self:FamilySupported() then return nil end
    return { id = "family", name = self:L("FAMILY_NAME"), family = true, source = "family" }
end

-- Member font for one alphabet; "default" means the game's own font for that target
function ns:FamilyMemberPath(alphabet, targetKey)
    local fontId = self.db.family[alphabet]
    local entry = fontId and fontId ~= "default" and fontId ~= "family" and self:ResolveFont(fontId)
    return entry and entry.path or self:DefaultFontPath(targetKey)
end

-- Used where only a single file works (names above heads, combat numbers):
-- a family can't be used there, so take the multilingual font that covers
-- every alphabet, falling back to the client language's member.
function ns:FamilyPrimaryPath(targetKey)
    local multilingual = self:ResolveFont("bundled:worldsans")
    if multilingual then return multilingual.path end
    local locale = GetLocale and GetLocale() or ""
    return self:FamilyMemberPath(CLIENT_ALPHABET[locale] or "roman", targetKey)
end

-- One click: every target that can show other players' text stops showing boxes
function ns:ApplyMultilingualPreset()
    local family = self:FamilySupported()
    -- every bundled font covers all non-Han letters, so keep the player's pretty
    -- picks there; anything unknown (game / custom font) becomes World Sans
    for _, alphabet in ipairs(self.FAMILY_ALPHABETS) do
        local entry = self:ResolveFont(self.db.family[alphabet])
        local isChinese = alphabet == "simplifiedchinese" or alphabet == "traditionalchinese"
        if isChinese or not (entry and entry.source == "bundled") then
            self.db.family[alphabet] = "bundled:worldsans"
        end
    end
    self:RefreshFamilies()
    self:TargetConfig("ui").font = family and "family" or "bundled:worldsans"
    self:TargetConfig("chat").font = family and "family" or "bundled:worldsans"
    -- names above heads are drawn with one file only
    self:TargetConfig("nameplate").font = "bundled:worldsans"
    self:ApplyAll()
    if self.RefreshOptions then self:RefreshOptions() end
    self:Print(self:L("MSG_PRESET"))
end

-- The client draws each alphabet with its own member of a font object, and
-- SetFont(path) only fills the client language's members: Chinese on a Korean
-- client keeps an empty member and shows boxes even when the file has Han.
-- So every chosen font is applied as a family with all members set; a font
-- without Han gets World Sans for the Chinese members.
function ns:UsesFamily(entry)
    return entry ~= nil and self:FamilySupported() or false
end

local CHINESE_ALPHABETS = { simplifiedchinese = true, traditionalchinese = true }

function ns:GetFamilyFont(targetKey, size, flags, entry)
    if not self:FamilySupported() then return nil end
    size = math.floor((tonumber(size) or 12) + 0.5)
    flags = flags or ""
    local single = entry and not entry.family     -- one chosen font in every member
    local cacheKey = (single and entry.id or "mix") .. "|" .. targetKey .. "|" .. size .. "|" .. flags
    if familyCache[cacheKey] then return familyCache[cacheKey] end
    local hanEntry = single and entry.autoMix and self:ResolveFont("bundled:worldsans")
    local members = {}
    for _, alphabet in ipairs(self.FAMILY_ALPHABETS) do
        local file
        if single then
            file = (CHINESE_ALPHABETS[alphabet] and hanEntry and hanEntry.path) or entry.path
        else
            file = self:FamilyMemberPath(alphabet, targetKey)
        end
        members[#members + 1] = { alphabet = alphabet, file = file, height = size, flags = flags }
    end
    familySerial = familySerial + 1
    local ok, family = pcall(CreateFontFamily, "EzWoWFontChangerFamily" .. familySerial, members)
    if ok and family then
        familyCache[cacheKey] = family
        return family
    end
end

-- After a member font changes: rebuild families and re-apply targets using them
function ns:RefreshFamilies()
    for cacheKey in pairs(familyCache) do
        if cacheKey:find("^mix|") then familyCache[cacheKey] = nil end   -- auto mixes don't depend on members
    end
    for _, targetKey in ipairs(self.TARGET_ORDER) do
        if self:TargetConfig(targetKey).font == "family" then self:ApplyTarget(targetKey) end
    end
end

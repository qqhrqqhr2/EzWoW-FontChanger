--===========================================================================
-- EzWoW - Font Changer
-- Core/Init.lua : Namespace, SavedVariables, Chat Output & Slash Commands
--===========================================================================
local ADDON_NAME, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

_G.EzWoW_FontChanger = ns

ns.ADDON_NAME = ADDON_NAME or "EzWoW-FontChanger"
ns.ADDON_PATH = "Interface\\AddOns\\" .. ns.ADDON_NAME .. "\\"
ns.FONT_PATH = ns.ADDON_PATH .. "Fonts\\"
-- Folder for the player's own font files. It sits outside this addon's folder
-- so addon updates (which replace the whole folder) never delete them.
ns.CUSTOM_FONT_DIR = "Interface\\AddOns\\EzWoW-MyFonts\\"
ns.DONATE_URL = "https://buymeacoffee.com/qqhrqqhr2"

-- Each target is one group of game text that gets its own font and size.
ns.TARGET_ORDER = { "ui", "chat", "combat", "nameplate" }

ns.DEFAULTS = {
    targets = {
        ui        = { font = "default", scale = 100 },
        chat      = { font = "default", scale = 100 },
        combat    = { font = "default", scale = 100 },
        nameplate = { font = "default", scale = 100 },
    },
    customFonts = {},   -- { { file = "MyFont.ttf" }, ... }
    -- members of the "per-language combination" font; "default" = the game's font
    family = {
        roman = "default",
        korean = "default",
        simplifiedchinese = "bundled:worldsans",
        traditionalchinese = "bundled:worldsans",
        russian = "bundled:worldsans",
    },
}

ns.SCALE_MIN, ns.SCALE_MAX, ns.SCALE_STEP = 70, 150, 5

local function fillDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then target[key] = {} end
            fillDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
end

function ns:InitializeDatabase()
    if type(EzWoW_FontChangerDB) ~= "table" then EzWoW_FontChangerDB = {} end
    fillDefaults(EzWoW_FontChangerDB, self.DEFAULTS)
    self.db = EzWoW_FontChangerDB
    -- fonts renamed since the first test build
    local renamed = self.RENAMED_FONT_IDS or {}
    for _, cfg in pairs(self.db.targets) do cfg.font = renamed[cfg.font] or cfg.font end
    for alphabet, fontId in pairs(self.db.family) do self.db.family[alphabet] = renamed[fontId] or fontId end
    return self.db
end

function ns:TargetConfig(targetKey)
    local db = self.db or self:InitializeDatabase()
    return db.targets[targetKey]
end

function ns:Print(message)
    print("|cffF2C46D[EzWoW - Font Changer]|r " .. tostring(message))
end

SLASH_EZWOWFONTCHANGER1 = "/ezfont"
SLASH_EZWOWFONTCHANGER2 = "/ezwowfontchanger"
SlashCmdList.EZWOWFONTCHANGER = function(message)
    message = (message or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if message == "reset" or message == "초기화" then
        ns:ResetAllTargets()
    else
        ns:ToggleOptions()
    end
end

function EzWoW_FontChanger_OnAddonCompartmentClick()
    ns:ToggleOptions()
end

--===========================================================================
-- EzWoW - Font Changer
-- Modules/FontApplier.lua : Apply / Restore Fonts on Game Font Objects
--===========================================================================
local ADDON_NAME, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local FontApplier = ns.FontApplier or {}
ns.FontApplier = FontApplier

local CHAT_FONT_OBJECTS = { ChatFontNormal = true, ChatFontSmall = true, ChatFontLarge = true, ChatBubbleFont = true }
local COMBAT_FONT_OBJECTS = { CombatTextFont = true, CombatTextFontOutline = true }

-- Globals the client reads once when the world loads; changing them needs a relog.
local LOAD_TIME_GLOBALS = {
    ui        = { "STANDARD_TEXT_FONT" },
    combat    = { "DAMAGE_TEXT_FONT" },
    nameplate = { "UNIT_NAME_FONT", "NAMEPLATE_FONT" },
}

local originalFonts = {}       -- [fontObject or chat frame] = { path, size, flags }
local appliedFonts = {}        -- [fontObject] = { path, size } last values we set
local originalGlobals = {}     -- [globalName] = path
local fontIdAtLoad = {}        -- [targetKey] = font id applied to the load-time globals
local objectsByTarget          -- [targetKey] = { fontObject, ... }

function FontApplier.classify(objectName)
    if CHAT_FONT_OBJECTS[objectName] then return "chat" end
    if COMBAT_FONT_OBJECTS[objectName] then return "combat" end
    if objectName:find("NamePlate", 1, true) then return "nameplate" end
    return "ui"
end

function FontApplier.collectFontObjects()
    objectsByTarget = { ui = {}, chat = {}, combat = {}, nameplate = {} }
    local names = {}
    if GetFonts then
        names = GetFonts() or {}
    else
        for globalName, value in pairs(_G) do
            if type(value) == "table" and type(globalName) == "string" and value.GetObjectType
                and value.SetFont and select(2, pcall(value.GetObjectType, value)) == "Font" then
                names[#names + 1] = globalName
            end
        end
    end
    for _, objectName in ipairs(names) do
        local fontObject = type(objectName) == "string" and _G[objectName]
        if type(fontObject) == "table" and fontObject.GetFont and fontObject.SetFont then
            local bucket = objectsByTarget[FontApplier.classify(objectName)]
            bucket[#bucket + 1] = fontObject
        end
    end
    return objectsByTarget
end

function FontApplier.remember(region)
    local saved = originalFonts[region]
    local applied = appliedFonts[region]
    if saved and applied then
        -- someone else (Blizzard settings, another addon) set it since our last
        -- change: treat their values as the new baseline instead of undoing them
        local path, size = region:GetFont()
        if path and (path ~= applied.path or math.abs((size or 0) - applied.size) > 0.5) then
            saved = nil
        end
    end
    if not saved then
        local path, size, flags = region:GetFont()
        if not path then return nil end
        saved = { path = path, size = size or 12, flags = flags or "" }
        originalFonts[region] = saved
    end
    return saved
end

-- Font object: chosen font (or the original one) at original size x scale
function FontApplier.applyToObject(fontObject, entry, scale, targetKey)
    if not entry and scale == 1 and not originalFonts[fontObject] then return end   -- never touched
    local saved = FontApplier.remember(fontObject)
    if not saved then return end
    local size = math.floor(saved.size * scale + 0.5)
    local path = entry and entry.path or saved.path
    local family = ns:UsesFamily(entry) and ns:GetFamilyFont(targetKey, size, saved.flags, entry)
    if family and pcall(fontObject.SetFontObject, fontObject, family) then
        path = nil
    elseif entry and entry.family then
        path = ns:FamilyPrimaryPath(targetKey)
    end
    if path then fontObject:SetFont(path, size, saved.flags) end
    local appliedPath, appliedSize = fontObject:GetFont()
    appliedFonts[fontObject] = { path = appliedPath or path, size = appliedSize or size }
end

-- Chat frames keep the size the player picked in the chat tab menu
function FontApplier.applyToChatFrame(chatFrame, entry)
    if not (chatFrame and chatFrame.GetFont and chatFrame.SetFont) then return end
    if not entry and not originalFonts[chatFrame] then return end
    local saved = FontApplier.remember(chatFrame)
    if not saved then return end
    local _, currentSize, currentFlags = chatFrame:GetFont()
    currentSize, currentFlags = currentSize or saved.size, currentFlags or saved.flags
    if ns:UsesFamily(entry) then
        local family = ns:GetFamilyFont("chat", currentSize, currentFlags, entry)
        if family and pcall(chatFrame.SetFontObject, chatFrame, family) then return end
        chatFrame:SetFont(entry.family and ns:FamilyPrimaryPath("chat") or entry.path, currentSize, currentFlags)
        return
    end
    chatFrame:SetFont(entry and entry.path or saved.path, currentSize, currentFlags)
end

function FontApplier.chatFrames()
    local frames = {}
    for index = 1, (NUM_CHAT_WINDOWS or 10) do frames[#frames + 1] = _G["ChatFrame" .. index] end
    for _, frameName in ipairs(CHAT_FRAMES or {}) do
        local frame = _G[frameName]
        if frame and not tContains(frames, frame) then frames[#frames + 1] = frame end
    end
    return frames
end

function ns:ApplyTarget(targetKey)
    local cfg = self:TargetConfig(targetKey)
    local entry = self:ResolveFont(cfg.font)
    local scale = (tonumber(cfg.scale) or 100) / 100
    if not objectsByTarget then FontApplier.collectFontObjects() end
    for _, fontObject in ipairs(objectsByTarget[targetKey] or {}) do
        pcall(FontApplier.applyToObject, fontObject, entry, scale, targetKey)
    end
    if targetKey == "chat" then
        for _, chatFrame in ipairs(FontApplier.chatFrames()) do
            pcall(FontApplier.applyToChatFrame, chatFrame, entry)
        end
    end
end

function ns:ApplyAll()
    for _, targetKey in ipairs(self.TARGET_ORDER) do self:ApplyTarget(targetKey) end
end

-- Runs while this addon loads, before the world reads these globals.
function FontApplier.applyLoadTimeGlobals()
    for targetKey, globalNames in pairs(LOAD_TIME_GLOBALS) do
        local cfg = ns:TargetConfig(targetKey)
        local entry = ns:ResolveFont(cfg.font)
        fontIdAtLoad[targetKey] = entry and cfg.font or "default"
        for _, globalName in ipairs(globalNames) do
            if originalGlobals[globalName] == nil then originalGlobals[globalName] = _G[globalName] or false end
            if entry then _G[globalName] = entry.family and ns:FamilyPrimaryPath(targetKey) or entry.path end
        end
    end
end

-- Combat numbers and names above heads only pick up a new font after a relog
function ns:NeedsRelog(targetKey)
    if targetKey ~= "combat" and targetKey ~= "nameplate" then return false end
    local cfg = self:TargetConfig(targetKey)
    local current = self:ResolveFont(cfg.font) and cfg.font or "default"
    return fontIdAtLoad[targetKey] ~= nil and fontIdAtLoad[targetKey] ~= current
end

function ns:ResetAllTargets()
    for _, targetKey in ipairs(self.TARGET_ORDER) do
        local cfg = self:TargetConfig(targetKey)
        cfg.font, cfg.scale = "default", 100
    end
    self:ApplyAll()
    if self.RefreshOptions then self:RefreshOptions() end
    self:Print(self:L("MSG_RESET"))
end

-- true when the client can open the file (a fresh FontString has no font
-- until SetFont succeeds, so GetFont tells us whether it loaded)
function ns:IsFontFileUsable(path)
    if not FontApplier.probeFrame then
        FontApplier.probeFrame = CreateFrame("Frame", nil, UIParent)
        FontApplier.probeFrame:Hide()
    end
    local probe = FontApplier.probeFrame:CreateFontString(nil, "OVERLAY")
    local okCall, accepted = pcall(probe.SetFont, probe, path, 12, "")
    local loaded = probe:GetFont()
    return okCall and accepted ~= false and loaded ~= nil
end

-----------------------------------------------------------------------------
-- Events & Hooks
-----------------------------------------------------------------------------
local pendingRescan = false
function FontApplier.scheduleRescan()
    if pendingRescan then return end
    pendingRescan = true
    C_Timer.After(0.3, function()
        pendingRescan = false
        FontApplier.collectFontObjects()
        ns:ApplyAll()
    end)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(_, event, loadedName)
    if event == "ADDON_LOADED" then
        if loadedName == ADDON_NAME then
            ns:InitializeDatabase()
            ns:DetectFolderFonts()   -- before the load-time globals may need a folder font
            FontApplier.applyLoadTimeGlobals()
            ns:RegisterSharedMediaFonts()
        elseif ns.db then
            -- Blizzard load-on-demand UIs and other addons add new font objects
            FontApplier.scheduleRescan()
        end
    elseif event == "PLAYER_LOGIN" then
        ns:RegisterSharedMediaFonts()   -- in case SharedMedia loaded after us
        FontApplier.collectFontObjects()
        ns:ApplyAll()
        if FCF_SetChatWindowFontSize then
            hooksecurefunc("FCF_SetChatWindowFontSize", function() ns:ApplyTarget("chat") end)
        end
        if FCF_OpenTemporaryWindow then
            hooksecurefunc("FCF_OpenTemporaryWindow", function() ns:ApplyTarget("chat") end)
        end
        local driver = _G.NamePlateDriverFrame
        if driver and driver.UpdateNamePlateOptions then
            hooksecurefunc(driver, "UpdateNamePlateOptions", function() ns:ApplyTarget("nameplate") end)
        end
    end
end)

-- The game's own font for a target, used by the settings preview
function ns:DefaultFontPath(targetKey)
    if targetKey == "combat" then
        return originalGlobals.DAMAGE_TEXT_FONT or DAMAGE_TEXT_FONT or STANDARD_TEXT_FONT
    end
    local sampleName = ({ ui = "GameFontHighlight", chat = "ChatFontNormal", nameplate = "SystemFont_NamePlate" })[targetKey]
    local sample = sampleName and _G[sampleName]
    if sample and sample.GetFont then
        local saved = originalFonts[sample]
        return saved and saved.path or (sample:GetFont())
    end
    return originalGlobals.STANDARD_TEXT_FONT or STANDARD_TEXT_FONT
end

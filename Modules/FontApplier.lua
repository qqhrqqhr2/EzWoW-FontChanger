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
    if objectName:find("Tooltip", 1, true) then return "tooltip" end
    if CHAT_FONT_OBJECTS[objectName] then return "chat" end
    if COMBAT_FONT_OBJECTS[objectName] then return "combat" end
    if objectName:find("NamePlate", 1, true) then return "nameplate" end
    return "ui"
end

function FontApplier.collectFontObjects()
    objectsByTarget = { ui = {}, chat = {}, tooltip = {}, combat = {}, nameplate = {} }
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
    if family and ns:SetFontObjectKeepLook(fontObject, family) then
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
        if family and ns:SetFontObjectKeepLook(chatFrame, family) then return end
        chatFrame:SetFont(entry.family and ns:FamilyPrimaryPath("chat") or entry.path, currentSize, currentFlags)
        return
    end
    chatFrame:SetFont(entry and entry.path or saved.path, currentSize, currentFlags)
end

-- Last font seen on each chat frame right after this addon set it. The chat
-- tab's font size menu sets the frame font directly (no event), so a change
-- is noticed by comparing against this from a timer.
local chatFontSeen = setmetatable({}, { __mode = "k" })

function FontApplier.noteChatFonts()
    for _, chatFrame in ipairs(FontApplier.chatFrames()) do
        if chatFrame.GetFont then
            local path, size = chatFrame:GetFont()
            chatFontSeen[chatFrame] = path and { path = path, size = size } or nil
        end
    end
end

function FontApplier.chatFontsChanged()
    for _, chatFrame in ipairs(FontApplier.chatFrames()) do
        local seen = chatFontSeen[chatFrame]
        if seen and chatFrame.GetFont then
            local path, size = chatFrame:GetFont()
            if path ~= seen.path or size ~= seen.size then return true end
        end
    end
    return false
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

-- Hook bookkeeping lives in weak-keyed side tables: fields written onto game
-- frames would taint them.
local hookedInputs = setmetatable({}, { __mode = "k" })
local hookedTooltips = setmetatable({}, { __mode = "k" })

-- Only the edit boxes of the numbered chat windows (1-10) are ever watched.
-- Whisper window edit boxes (11+) carry secret whisper targets; running addon
-- code inside their show/focus handling taints the whisper history.
function FontApplier.isPermanentChatInput(editBox)
    if not (editBox and editBox.GetName) then return false end
    local name = editBox:GetName()
    local index = type(name) == "string" and tonumber(name:match("^ChatFrame(%d+)EditBox$"))
    return index ~= nil and index <= (NUM_CHAT_WINDOWS or 10)
end

local inputCallbacksRegistered = false
function FontApplier.watchChatInputs()
    if inputCallbacksRegistered then return end
    -- Callbacks from the client's chat edit box events run isolated from the
    -- default chat code, unlike script hooks on the edit box itself.
    if type(EventRegistry) == "table" and type(EventRegistry.RegisterCallback) == "function" then
        local function onEditBox(_, editBox)
            if FontApplier.isPermanentChatInput(editBox) then FontApplier.applyToChatInput(editBox) end
        end
        local okShow = pcall(EventRegistry.RegisterCallback, EventRegistry, "ChatFrame.OnEditBoxShow", onEditBox, "EzWoWFontChangerInputShow")
        local okFocus = pcall(EventRegistry.RegisterCallback, EventRegistry, "ChatFrame.OnEditBoxFocusGained", onEditBox, "EzWoWFontChangerInputFocus")
        inputCallbacksRegistered = okShow or okFocus
    end
end

-- Edit boxes can inherit CENTER from a shared font object. Applying a font
-- family preserves that inherited value, so chat input needs an explicit LEFT.
function FontApplier.applyToChatInput(editBox)
    if not (editBox and editBox.SetJustifyH) then return end
    local cfg = ns:TargetConfig("chat")
    local entry = ns:ResolveFont(cfg.font)
    pcall(FontApplier.applyToChatFrame, editBox, entry)
    pcall(editBox.SetJustifyH, editBox, "LEFT")
    -- Script hooks only when the edit box callbacks above are unavailable.
    if not inputCallbacksRegistered and editBox.HookScript and not hookedInputs[editBox]
        and FontApplier.isPermanentChatInput(editBox) then
        hookedInputs[editBox] = true
        editBox:HookScript("OnShow", FontApplier.applyToChatInput)
        editBox:HookScript("OnEditFocusGained", FontApplier.applyToChatInput)
    end
end

function FontApplier.refreshChatInputs()
    local seen = {}
    local function apply(editBox)
        if editBox and not seen[editBox] then
            seen[editBox] = true
            FontApplier.applyToChatInput(editBox)
        end
    end
    for index = 1, (NUM_CHAT_WINDOWS or 10) do
        local frame = _G["ChatFrame" .. index]
        apply(frame and frame.editBox)
        apply(_G["ChatFrame" .. index .. "EditBox"])
    end
    for _, frame in ipairs(FontApplier.chatFrames()) do apply(frame.editBox) end
    if ChatEdit_GetActiveWindow then apply(ChatEdit_GetActiveWindow()) end
end

-- Tooltip lines can have a local font left over from an earlier style pass.
-- Updating GameTooltipHeaderText alone does not update those local overrides.
function FontApplier.applyToTooltip(tip)
    if not (ns.db and tip and tip.GetName and tip.NumLines) then return end
    if tip.IsForbidden and tip:IsForbidden() then return end
    local name = tip:GetName()
    if not name then return end
    local entry = ns:TargetFontEntry("tooltip")
    local scale = (tonumber(ns:TargetConfig("tooltip").scale) or 100) / 100
    local function apply(region)
        if not (region and region.GetFont and region.SetFont) then return end
        if not entry and scale == 1 and not originalFonts[region] then return end
        -- A line inheriting a shared tooltip font is already scaled. Start from
        -- that object's original size instead of multiplying the scale twice.
        if not originalFonts[region] and region.GetFontObject then
            local object = region:GetFontObject()
            local saved = object and originalFonts[object]
            if saved and object.GetFont then
                local path, size = region:GetFont()
                local objectPath, objectSize = object:GetFont()
                if path == objectPath and size == objectSize then
                    originalFonts[region] = { path = saved.path, size = saved.size, flags = saved.flags }
                end
            end
        end
        FontApplier.applyToObject(region, entry, scale, "tooltip")
    end
    for index = 1, tip:NumLines() do
        pcall(apply, _G[name .. "TextLeft" .. index])
        pcall(apply, _G[name .. "TextRight" .. index])
    end
end

-- Tooltips that follow the tooltip font setting: the main one, the one opened
-- from chat links, and the two item comparison tooltips.
FontApplier.TOOLTIP_NAMES = { "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2" }

function FontApplier.hookTooltip()
    for _, tipName in ipairs(FontApplier.TOOLTIP_NAMES) do
        local tip = _G[tipName]
        if tip and tip.Show and not hookedTooltips[tip] then
            hookedTooltips[tip] = true
            -- OnShow alone misses updates while the tooltip remains visible.
            hooksecurefunc(tip, "Show", FontApplier.applyToTooltip)
        end
    end
end

function FontApplier.refreshShownTooltips()
    for _, tipName in ipairs(FontApplier.TOOLTIP_NAMES) do
        local tip = _G[tipName]
        if tip and tip.IsShown and tip:IsShown() then
            pcall(FontApplier.applyToTooltip, tip)
        end
    end
end

function ns:ApplyTarget(targetKey)
    local cfg = self:TargetConfig(targetKey)
    local entry = self:TargetFontEntry(targetKey)
    local scale = (tonumber(cfg.scale) or 100) / 100
    if not objectsByTarget then FontApplier.collectFontObjects() end
    for _, fontObject in ipairs(objectsByTarget[targetKey] or {}) do
        pcall(FontApplier.applyToObject, fontObject, entry, scale, targetKey)
    end
    if targetKey == "chat" then
        for _, chatFrame in ipairs(FontApplier.chatFrames()) do
            pcall(FontApplier.applyToChatFrame, chatFrame, entry)
        end
        pcall(FontApplier.noteChatFonts)
    end
    if targetKey == "ui" or targetKey == "chat" then FontApplier.refreshChatInputs() end
    if targetKey == "ui" and self:TargetConfig("tooltip").font == "inherit" then self:ApplyTarget("tooltip") end
    if targetKey == "tooltip" then FontApplier.refreshShownTooltips() end
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
        cfg.font, cfg.scale = self.DEFAULTS.targets[targetKey].font, 100
    end
    self:ApplyAll()
    if self.RefreshOptions then self:RefreshOptions() end
    self:Print(self:L("MSG_RESET"))
end

-- true when the client can open the file. One probe FontString is reused:
-- it is first reset to the game's standard font, so a SetFont that fails
-- leaves that baseline in place and GetFont tells us whether the file loaded.
local function normalizeFontPath(path)
    return type(path) == "string" and path:gsub("/", "\\"):lower() or nil
end

function ns:IsFontFileUsable(path)
    if type(path) ~= "string" or path == "" then return false end
    if not FontApplier.probeFrame then
        FontApplier.probeFrame = CreateFrame("Frame", nil, UIParent)
        FontApplier.probeFrame:Hide()
    end
    local probe = FontApplier.probeString
    if not probe then
        probe = FontApplier.probeFrame:CreateFontString(nil, "OVERLAY")
        FontApplier.probeString = probe
    end
    local baseline = originalGlobals.STANDARD_TEXT_FONT or STANDARD_TEXT_FONT
    local baseLoaded = type(baseline) == "string" and pcall(probe.SetFont, probe, baseline, 12, "") and probe:GetFont()
    if not baseLoaded then
        -- Baseline unavailable: fall back to a fresh FontString (no font until SetFont succeeds)
        local fresh = FontApplier.probeFrame:CreateFontString(nil, "OVERLAY")
        local okCall, accepted = pcall(fresh.SetFont, fresh, path, 12, "")
        return okCall and accepted ~= false and fresh:GetFont() ~= nil
    end
    if normalizeFontPath(path) == normalizeFontPath(baseline) then return true end
    local okCall, accepted = pcall(probe.SetFont, probe, path, 12, "")
    local loaded = probe:GetFont()
    return okCall and accepted ~= false and loaded ~= nil and loaded ~= baseLoaded
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

-- Chat windows are never followed by hooking the default chat functions
-- (opening a whisper window, changing the font size, activating chat input):
-- those run in the middle of the default whisper handling, and a hook there
-- breaks it. Instead this addon's own frame listens for the whisper and chat
-- window events and re-applies the chat font on the next frame.
local pendingChatApply = false
function FontApplier.queueChatApply()
    if pendingChatApply or not ns.db then return end
    pendingChatApply = true
    C_Timer.After(0, function()
        pendingChatApply = false
        ns:ApplyTarget("chat")
    end)
end

local chatWatcher = CreateFrame("Frame")
for _, eventName in ipairs({ "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER",
        "CHAT_MSG_BN_WHISPER_INFORM", "UPDATE_CHAT_WINDOWS" }) do
    pcall(chatWatcher.RegisterEvent, chatWatcher, eventName)
end
chatWatcher:SetScript("OnEvent", function()
    if FontApplier.loggedIn then FontApplier.queueChatApply() end
end)

-- Notices a size picked in the chat tab menu (which sends no event).
function FontApplier.startChatFontWatch()
    if FontApplier.chatFontTicker or not (C_Timer and C_Timer.NewTicker) then return end
    FontApplier.chatFontTicker = C_Timer.NewTicker(1, function()
        if pendingChatApply or not ns.db or not ns:TargetFontEntry("chat") then return end
        local isCallOk, changed = pcall(FontApplier.chatFontsChanged)
        if isCallOk and changed then FontApplier.queueChatApply() end
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
            ns:RegisterSharedFonts()
        elseif ns.db then
            -- Blizzard load-on-demand UIs and other addons add new font objects
            FontApplier.scheduleRescan()
        end
    elseif event == "PLAYER_LOGIN" then
        ns:RegisterSharedFonts()   -- in case the shared font library loaded after us
        FontApplier.hookTooltip()
        if ns.RegisterBlizzardOptions then ns:RegisterBlizzardOptions() end
        FontApplier.watchChatInputs()
        FontApplier.collectFontObjects()
        ns:ApplyAll()
        FontApplier.loggedIn = true
        FontApplier.startChatFontWatch()
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
    local sampleName = ({ ui = "GameFontHighlight", chat = "ChatFontNormal", tooltip = "GameTooltipText", nameplate = "SystemFont_NamePlate" })[targetKey]
    local sample = sampleName and _G[sampleName]
    if sample and sample.GetFont then
        local saved = originalFonts[sample]
        return saved and saved.path or (sample:GetFont())
    end
    return originalGlobals.STANDARD_TEXT_FONT or STANDARD_TEXT_FONT
end

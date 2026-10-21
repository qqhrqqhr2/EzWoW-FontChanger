--===========================================================================
-- EzWoW - Font Changer
-- UI/BlizzardPanel.lua : Game Settings > AddOns Page (opens the settings window)
--===========================================================================
local _, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local Theme = ns.UIKit.Theme
local PANEL_TITLE = "EzWoW - Font Changer"
local optionsPanel

function ns:RegisterBlizzardOptions()
    if optionsPanel then return end
    optionsPanel = CreateFrame("Frame", "EzWoWFontChangerOptionsPanel", UIParent)
    optionsPanel.name = PANEL_TITLE

    local icon = optionsPanel:CreateTexture(nil, "ARTWORK")
    icon:SetSize(32, 32)
    icon:SetPoint("TOPLEFT", 18, -18)
    icon:SetTexture(ns.ADDON_PATH .. "Media\\Icon")

    local heading = optionsPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    heading:SetPoint("LEFT", icon, "RIGHT", 10, 0)
    heading:SetText(PANEL_TITLE)
    heading:SetTextColor(unpack(Theme.accent))

    local desc = optionsPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -14)
    desc:SetWidth(520)
    desc:SetJustifyH("LEFT")

    local open = CreateFrame("Button", nil, optionsPanel, "BackdropTemplate")
    open:SetSize(220, 28)
    open:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -18)
    ns.UIKit:ApplyBackdrop(open)
    open:SetBackdropColor(0.24, 0.19, 0.11, 0.96)
    open:SetBackdropBorderColor(unpack(Theme.accent))
    open.label = open:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    open.label:SetPoint("CENTER")
    open.label:SetTextColor(unpack(Theme.accent))
    open:SetScript("OnEnter", function(self) self:SetBackdropColor(0.31, 0.25, 0.14, 1) end)
    open:SetScript("OnLeave", function(self) self:SetBackdropColor(0.24, 0.19, 0.11, 0.96) end)
    open:SetScript("OnMouseDown", function(self) self.label:SetPoint("CENTER", 1, -1) end)
    open:SetScript("OnMouseUp", function(self) self.label:SetPoint("CENTER", 0, 0) end)
    open:SetScript("OnClick", function()
        -- the game settings window sits above ours; close it so the window is visible
        if SettingsPanel and SettingsPanel:IsShown() and HideUIPanel then pcall(HideUIPanel, SettingsPanel) end
        ns:ToggleOptions()
    end)

    local hint = optionsPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", open, "BOTTOMLEFT", 0, -14)
    hint:SetTextColor(unpack(Theme.textMuted))

    optionsPanel.refreshText = function()
        desc:SetText(ns:L("PANEL_DESC"))
        open.label:SetText(ns:L("PANEL_OPEN"))
        ns.UIKit:FitFontString(open.label, 212, 1)
        hint:SetText(ns:L("PANEL_HINT"))
    end
    optionsPanel:SetScript("OnShow", optionsPanel.refreshText)

    if Settings and type(Settings.RegisterCanvasLayoutCategory) == "function" and type(Settings.RegisterAddOnCategory) == "function" then
        local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, optionsPanel, PANEL_TITLE)
        if ok and category then pcall(Settings.RegisterAddOnCategory, category) end
    elseif type(InterfaceOptions_AddCategory) == "function" then
        pcall(InterfaceOptions_AddCategory, optionsPanel)
    end
end

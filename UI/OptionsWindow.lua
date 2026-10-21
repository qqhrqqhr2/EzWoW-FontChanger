--===========================================================================
-- EzWoW - Font Changer
-- UI/OptionsWindow.lua : Settings Window, Font Picker & Custom Font List
--===========================================================================
local _, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local SettingsDialog = ns.SettingsDialog or {}
ns.SettingsDialog = SettingsDialog

local Theme = ns.UIKit.Theme
local WINDOW_WIDTH = 520
local BLOCK_TOP, BLOCK_HEIGHT = -112, 84
local PREVIEW_SIZE = 15
-- Same sample in every language, so each area shows how its font draws
-- Korean, Latin, Cyrillic, Simplified / Traditional Chinese and Japanese
local PREVIEW_SAMPLE = "한국어 ABC Русский 简体 繁體 かな 123"
local CUSTOM_ROWS = 5
local PICKER_ROWS = 8
local LANGUAGE_BUTTON_WIDTH, LANGUAGE_LIST_WIDTH, LANGUAGE_ROW_HEIGHT = 160, 200, 22

local configFrame, pickerFrame, advancedFrame, languageList

-----------------------------------------------------------------------------
-- Widgets
-----------------------------------------------------------------------------
function SettingsDialog.createButton(parent, width, height, text, onClick)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width, height)
    ns.UIKit:ApplySurface(button, Theme.bgSecondary, Theme.border)
    button.label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    if width < 40 then
        button.label:SetPoint("CENTER")   -- x / + / - buttons: no room for side insets
    else
        button.label:SetPoint("LEFT", 8, 0)
        button.label:SetPoint("RIGHT", -8, 0)
    end
    button.label:SetWordWrap(false)
    button.label:SetText(text or "")
    button.fitWidth = width >= 40 and width - 16 or nil
    button:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(unpack(Theme.accent)) end)
    button:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(unpack(Theme.border)) end)
    button:SetScript("OnClick", onClick)
    return button
end

-- Re-sets a button label and shrinks long translations to the label's inner width
function SettingsDialog.setButtonText(button, text)
    button.label:SetText(text or "")
    if button.fitWidth then ns.UIKit:FitFontString(button.label, button.fitWidth, 1) end
end

-- Hover help: first line of the text is the title, the rest the details
function SettingsDialog.showTip(owner, text)
    if not text or text == "" then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    local title, body = text:match("^([^\n]*)\n?(.*)$")
    GameTooltip:AddLine(title, Theme.accent[1], Theme.accent[2], Theme.accent[3])
    for line in (body or ""):gmatch("[^\n]+") do
        GameTooltip:AddLine(line, 0.929, 0.957, 0.969, true)
    end
    GameTooltip:Show()
end

function SettingsDialog.attachTip(widget, tipKey)
    if not (widget and widget.HookScript) then return end
    if widget.EnableMouse then widget:EnableMouse(true) end
    widget:HookScript("OnEnter", function(self)
        SettingsDialog.showTip(self, type(tipKey) == "function" and tipKey(self) or ns:L(tipKey))
    end)
    widget:HookScript("OnLeave", function(self)
        if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
    end)
end

-- Picker / list help for one font: style plus what it can show
function SettingsDialog.fontTip(entry)
    if entry and entry.inherit then return ns:L("TIP_TOOLTIP_INHERIT") end
    if not entry or entry.id == "default" then return ns:L("TIP_FONT_default") end
    if entry.family then return ns:L("TIP_FAMILY") end
    local lines = { entry.name }
    if entry.source == "bundled" then
        local key = "FONTDESC_" .. entry.id:gsub("^bundled:", "")
        if ns:L(key) ~= key then lines[#lines + 1] = ns:L(key) end
        local allHan = (ns:FontCoverage(entry, "chinese") or 0) >= 0.99 and entry.id == "bundled:worldsans"
        lines[#lines + 1] = ns:L(allHan and "TIP_FONT_HAN_ALL" or "TIP_FONT_HAN_COMMON")
    elseif entry.source == "custom" then
        lines[#lines + 1] = ns:L("TIP_FONT_custom")
    elseif entry.source == "shared" then
        lines[#lines + 1] = ns:L("TIP_FONT_shared")
    end
    return table.concat(lines, "\n")
end

function SettingsDialog.setFontSafely(fontString, path, size)
    if not (path and pcall(fontString.SetFont, fontString, path, size, "") and fontString:GetFont()) then
        fontString:SetFontObject(GameFontHighlight)
    end
end

-----------------------------------------------------------------------------
-- Font Picker (shared by the target blocks and the per-language members)
-----------------------------------------------------------------------------
-- Draws a font name in its own face; family entries use the family object
function SettingsDialog.renderFontSample(fontString, entry, targetKey, size)
    if ns:UsesFamily(entry) then
        local family = ns:GetFamilyFont(targetKey, size, "", entry)
        if family and ns:SetFontObjectKeepLook(fontString, family) then return end
        SettingsDialog.setFontSafely(fontString, entry.family and ns:FamilyPrimaryPath(targetKey) or entry.path, size)
        return
    end
    SettingsDialog.setFontSafely(fontString, entry and entry.path or ns:DefaultFontPath(targetKey), size)
end

function SettingsDialog.buildPicker()
    if pickerFrame then return pickerFrame end
    pickerFrame = CreateFrame("Frame", nil, configFrame, "BackdropTemplate")
    pickerFrame:SetSize(300, 58 + PICKER_ROWS * 24)
    pickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    pickerFrame:SetFrameLevel(configFrame:GetFrameLevel() + 40)
    pickerFrame:EnableMouse(true)
    pickerFrame:EnableMouseWheel(true)
    pickerFrame:SetClampedToScreen(true)
    ns.UIKit:ApplySurface(pickerFrame, Theme.bgPrimary, Theme.accent)
    pickerFrame.title = ns.UIKit:CreateLabel(pickerFrame, "GameFontNormal", "TOPLEFT", pickerFrame, "TOPLEFT", 12, -10, Theme.accent, ns:L("PICK_TITLE"))
    pickerFrame.scrollHint = ns.UIKit:CreateLabel(pickerFrame, "GameFontDisableSmall", "BOTTOMRIGHT", pickerFrame, "BOTTOMRIGHT", -12, 10, Theme.textMuted)
    pickerFrame.rows = {}
    for index = 1, PICKER_ROWS do
        local row = CreateFrame("Button", nil, pickerFrame)
        row:SetSize(276, 22)
        row:SetPoint("TOPLEFT", 12, -32 - (index - 1) * 24)
        row.highlight = row:CreateTexture(nil, "BACKGROUND")
        row.highlight:SetAllPoints()
        row.highlight:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.18)
        row.highlight:Hide()
        row.text = row:CreateFontString(nil, "OVERLAY")
        row.text:SetPoint("LEFT", 6, 0)
        row.text:SetPoint("RIGHT", -84, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        row.tag = ns.UIKit:CreateLabel(row, "GameFontDisableSmall", "RIGHT", row, "RIGHT", -6, 0, Theme.textMuted)
        row:SetScript("OnEnter", function(self)
            self.highlight:Show()
            local entry = self.fontId == "inherit" and { inherit = true } or (self.fontId == "default" and { id = "default" } or ns:ResolveFont(self.fontId))
            SettingsDialog.showTip(self, SettingsDialog.fontTip(entry))
        end)
        row:SetScript("OnLeave", function(self)
            self.highlight:Hide()
            if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
        end)
        row:SetScript("OnClick", function(self)
            local onSelect = pickerFrame.onSelect
            pickerFrame:Hide()
            onSelect(self.fontId)
            ns:RefreshOptions()
        end)
        pickerFrame.rows[index] = row
    end
    pickerFrame:SetScript("OnMouseWheel", function(self, delta)
        local maxOffset = math.max(0, #self.entries - PICKER_ROWS)
        self.offset = math.min(maxOffset, math.max(0, self.offset - delta))
        SettingsDialog.fillPicker()
    end)
    pickerFrame:Hide()
    return pickerFrame
end

function SettingsDialog.entryTag(entry)
    if entry.family then return ns:L("SRC_family") end
    if entry.multilingual then return ns:L("SRC_multi") end
    if entry.source == "custom" then return ns:L("SRC_custom") end
    if entry.source == "shared" then return ns:L("SRC_shared") end
    return ""
end

function SettingsDialog.fillPicker()
    pickerFrame.title:SetText(ns:L("PICK_TITLE"))
    local total = #pickerFrame.entries
    pickerFrame.scrollHint:SetText(total > PICKER_ROWS and string.format(ns:L("PICK_SCROLL"),
        pickerFrame.offset + 1, math.min(total, pickerFrame.offset + PICKER_ROWS), total) or "")
    local selectedId = pickerFrame.selectedId
    if selectedId and selectedId ~= "default" and selectedId ~= "inherit" and not ns:ResolveFont(selectedId) then selectedId = "default" end
    for index, row in ipairs(pickerFrame.rows) do
        local entry = pickerFrame.entries[index + pickerFrame.offset]
        if entry then
            row.fontId = entry.id
            SettingsDialog.renderFontSample(row.text, entry.id ~= "default" and entry or nil, pickerFrame.previewTarget, 14)
            local selected = selectedId == entry.id
            row.text:SetText((selected and "> " or "") .. entry.name)
            local color = selected and Theme.accent or Theme.textBody
            row.text:SetTextColor(color[1], color[2], color[3])
            if ns:FontLacksClientScript(entry) and not pickerFrame.isMember then
                row.tag:SetText("!")
                row.tag:SetTextColor(unpack(Theme.warning))
            else
                row.tag:SetText(SettingsDialog.entryTag(entry))
                row.tag:SetTextColor(unpack(Theme.textMuted))
            end
            row:Show()
        else
            row:Hide()
        end
    end
end

-- opts: { key, anchor, selectedId, previewTarget, includeFamily, isMember, onSelect }
function SettingsDialog.openPicker(opts)
    SettingsDialog.buildPicker()
    if languageList then languageList:Hide() end
    if pickerFrame:IsShown() and pickerFrame.key == opts.key then
        pickerFrame:Hide()
        return
    end
    pickerFrame.key = opts.key
    pickerFrame.selectedId = opts.selectedId
    pickerFrame.previewTarget = opts.previewTarget
    pickerFrame.isMember = opts.isMember
    pickerFrame.onSelect = opts.onSelect
    pickerFrame.entries = { { id = "default", name = ns:L("FONT_DEFAULT") } }
    if opts.includeInherit then table.insert(pickerFrame.entries, 1, { id = "inherit", name = ns:L("FONT_INHERIT_UI"), inherit = true }) end
    local familyEntry = opts.includeFamily and ns:FamilyEntry()
    if familyEntry then pickerFrame.entries[#pickerFrame.entries + 1] = familyEntry end
    for _, entry in ipairs(ns:FontCatalog()) do pickerFrame.entries[#pickerFrame.entries + 1] = entry end
    pickerFrame.offset = 0
    pickerFrame:SetParent(opts.anchor:GetParent())
    pickerFrame:SetFrameLevel(opts.anchor:GetFrameLevel() + 40)
    pickerFrame:ClearAllPoints()
    pickerFrame:SetPoint("TOPLEFT", opts.anchor, "BOTTOMLEFT", 0, -2)
    SettingsDialog.fillPicker()
    pickerFrame:Show()
end

function SettingsDialog.openTargetPicker(targetKey, anchor)
    SettingsDialog.openPicker({
        key = "target:" .. targetKey, anchor = anchor, previewTarget = targetKey, includeFamily = true,
        includeInherit = targetKey == "tooltip",
        selectedId = ns:TargetConfig(targetKey).font,
        onSelect = function(fontId)
            ns:TargetConfig(targetKey).font = fontId
            ns:ApplyTarget(targetKey)
        end,
    })
end

function SettingsDialog.applyFontToAll(fontId)
    for _, targetKey in ipairs(ns.TARGET_ORDER) do
        ns:TargetConfig(targetKey).font = fontId
        ns:ApplyTarget(targetKey)
    end
    ns:RefreshOptions()
end

function SettingsDialog.resetTarget(targetKey)
    local cfg = ns:TargetConfig(targetKey)
    cfg.font, cfg.scale = ns.DEFAULTS.targets[targetKey].font, 100
    ns:ApplyTarget(targetKey)
    ns:RefreshOptions()
end

function SettingsDialog.openAllFontPicker(anchor)
    SettingsDialog.openPicker({
        key = "all", anchor = anchor, previewTarget = "chat", includeFamily = false,
        selectedId = false, onSelect = SettingsDialog.applyFontToAll,
    })
end

-----------------------------------------------------------------------------
-- Per-Language Combination Window
-----------------------------------------------------------------------------
local familyFrame

function SettingsDialog.buildFamilyWindow()
    if familyFrame then return familyFrame end
    familyFrame = CreateFrame("Frame", "EzWoWFontChangerFamily", configFrame, "BackdropTemplate")
    familyFrame:SetSize(400, 150 + #ns.FAMILY_ALPHABETS * 34)
    familyFrame:SetPoint("TOPLEFT", configFrame, "TOPRIGHT", 8, 0)
    familyFrame:SetFrameLevel(configFrame:GetFrameLevel() + 10)
    familyFrame:EnableMouse(true)
    familyFrame:SetClampedToScreen(true)
    ns.UIKit:ApplySurface(familyFrame, Theme.bgPrimary, Theme.accent)
    familyFrame.title = ns.UIKit:CreateLabel(familyFrame, "GameFontNormal", "TOPLEFT", familyFrame, "TOPLEFT", 16, -14, Theme.accent)
    familyFrame.hint = ns.UIKit:CreateLabel(familyFrame, "GameFontHighlightSmall", "TOPLEFT", familyFrame, "TOPLEFT", 16, -34, Theme.textMuted)
    familyFrame.hint:SetWidth(368)
    familyFrame.hint:SetJustifyH("LEFT")
    local close = SettingsDialog.createButton(familyFrame, 22, 22, "x", function() familyFrame:Hide() end)
    close:SetPoint("TOPRIGHT", -8, -8)
    close.label:SetJustifyH("CENTER")

    familyFrame.rows = {}
    for index, alphabet in ipairs(ns.FAMILY_ALPHABETS) do
        local top = -78 - (index - 1) * 34
        local row = {}
        row.label = ns.UIKit:CreateLabel(familyFrame, "GameFontHighlight", "TOPLEFT", familyFrame, "TOPLEFT", 16, top - 6, Theme.textBody)
        row.label:SetWidth(140)
        row.label:SetJustifyH("LEFT")
        row.button = SettingsDialog.createButton(familyFrame, 220, 26, "", function(self)
            SettingsDialog.openPicker({
                key = "member:" .. alphabet, anchor = self, previewTarget = "chat", isMember = true,
                selectedId = ns.db.family[alphabet],
                onSelect = function(fontId)
                    ns.db.family[alphabet] = fontId
                    ns:RefreshFamilies()
                end,
            })
        end)
        row.button:SetPoint("TOPLEFT", 164, top)
        SettingsDialog.attachTip(row.button, "TIP_FAMILY_ROW")
        familyFrame.rows[alphabet] = row
    end
    familyFrame.presetButton = SettingsDialog.createButton(familyFrame, 368, 28, "", function() ns:ApplyMultilingualPreset() end)
    familyFrame.presetButton:SetPoint("BOTTOMLEFT", 16, 44)
    familyFrame.presetButton.label:SetJustifyH("CENTER")
    SettingsDialog.attachTip(familyFrame.presetButton, "TIP_PRESET")
    familyFrame.presetButton:SetBackdropBorderColor(unpack(Theme.accent))
    familyFrame.presetButton:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(unpack(Theme.accent)) end)

    familyFrame.preview = familyFrame:CreateFontString(nil, "OVERLAY")
    familyFrame.preview:SetPoint("BOTTOMLEFT", 16, 16)
    familyFrame.preview:SetWidth(368)
    familyFrame.preview:SetJustifyH("LEFT")
    familyFrame.preview:SetWordWrap(false)
    familyFrame.preview:SetTextColor(unpack(Theme.textBody))
    familyFrame:SetScript("OnHide", function() if pickerFrame then pickerFrame:Hide() end end)
    familyFrame:Hide()
    return familyFrame
end

function SettingsDialog.refreshFamilyWindow()
    if not (familyFrame and familyFrame:IsShown()) then return end
    familyFrame.title:SetText(ns:L("FAMILY_TITLE"))
    familyFrame.hint:SetText(ns:L("FAMILY_HINT"))
    SettingsDialog.setButtonText(familyFrame.presetButton, ns:L("PRESET_BUTTON"))
    for alphabet, row in pairs(familyFrame.rows) do
        row.label:SetText(ns:L("ALPHA_" .. alphabet))
        ns.UIKit:FitFontString(row.label, 140, 1)
        local entry = ns:ResolveFont(ns.db.family[alphabet])
        row.button.label:SetText(entry and entry.name or ns:L("FONT_DEFAULT"))
        SettingsDialog.setFontSafely(row.button.label, entry and entry.path or ns:DefaultFontPath("chat"), 13)
    end
    SettingsDialog.renderFontSample(familyFrame.preview, ns:FamilyEntry(), "chat", PREVIEW_SIZE)
    familyFrame.preview:SetText(ns:L("FAMILY_PREVIEW"))
end

function SettingsDialog.toggleFamilyWindow()
    SettingsDialog.buildFamilyWindow()
    familyFrame:SetShown(not familyFrame:IsShown())
    SettingsDialog.refreshFamilyWindow()
end

-----------------------------------------------------------------------------
-- Target Blocks (one per font group)
-----------------------------------------------------------------------------
function SettingsDialog.buildTargetBlock(targetKey, index)
    local top = BLOCK_TOP - (index - 1) * BLOCK_HEIGHT
    local block = {}
    block.title = ns.UIKit:CreateLabel(configFrame, "GameFontNormal", "TOPLEFT", configFrame, "TOPLEFT", 20, top, Theme.accent)
    block.title:SetWidth(280)
    block.title:SetWordWrap(false)
    SettingsDialog.attachTip(block.title, "TIP_" .. targetKey)
    block.note = ns.UIKit:CreateLabel(configFrame, "GameFontHighlightSmall", "TOPRIGHT", configFrame, "TOPRIGHT", -20, top - 1, Theme.warning)
    block.note:SetWidth(180)
    block.note:SetWordWrap(false)
    block.note:SetJustifyH("RIGHT")

    block.fontButton = SettingsDialog.createButton(configFrame, 286, 26, "", function(self)
        SettingsDialog.openTargetPicker(targetKey, self)
    end)
    block.fontButton:SetPoint("TOPLEFT", 20, top - 20)
    SettingsDialog.attachTip(block.fontButton, "TIP_" .. targetKey)

    local function stepScale(delta)
        local cfg = ns:TargetConfig(targetKey)
        cfg.scale = math.min(ns.SCALE_MAX, math.max(ns.SCALE_MIN, (cfg.scale or 100) + delta))
        ns:ApplyTarget(targetKey)
        ns:RefreshOptions()
    end
    block.sizeLabel = ns.UIKit:CreateLabel(configFrame, "GameFontHighlightSmall", "TOPLEFT", configFrame, "TOPLEFT", 316, top - 27, Theme.textMuted, ns:L("SIZE"))
    block.minus = SettingsDialog.createButton(configFrame, 26, 26, "-", function() stepScale(-ns.SCALE_STEP) end)
    block.minus:SetPoint("TOPLEFT", 356, top - 20)
    block.value = SettingsDialog.createButton(configFrame, 52, 26, "", function()
        ns:TargetConfig(targetKey).scale = 100
        ns:ApplyTarget(targetKey)
        ns:RefreshOptions()
    end)
    block.value:SetPoint("TOPLEFT", 384, top - 20)
    block.value.label:SetJustifyH("CENTER")
    SettingsDialog.attachTip(block.value, "TIP_SIZE_RESET")
    block.plus = SettingsDialog.createButton(configFrame, 26, 26, "+", function() stepScale(ns.SCALE_STEP) end)
    block.plus:SetPoint("TOPLEFT", 438, top - 20)
    block.reset = SettingsDialog.createButton(configFrame, 28, 26, "R", function() SettingsDialog.resetTarget(targetKey) end)
    block.reset:SetPoint("TOPLEFT", 472, top - 20)
    block.reset.label:SetJustifyH("CENTER")
    SettingsDialog.attachTip(block.reset, targetKey == "tooltip" and "TIP_TOOLTIP_RESET" or "TIP_TARGET_RESET")
    SettingsDialog.attachTip(block.minus, "TIP_SIZE")
    SettingsDialog.attachTip(block.plus, "TIP_SIZE")
    block.minus.label:SetJustifyH("CENTER")
    block.plus.label:SetJustifyH("CENTER")

    block.preview = configFrame:CreateFontString(nil, "OVERLAY")
    block.preview:SetPoint("TOPLEFT", 22, top - 54)
    block.preview:SetWidth(WINDOW_WIDTH - 44)
    block.preview:SetJustifyH("LEFT")
    block.preview:SetWordWrap(false)
    block.preview:SetTextColor(unpack(Theme.textBody))
    return block
end

function SettingsDialog.refreshTargetBlock(targetKey, block)
    local cfg = ns:TargetConfig(targetKey)
    local entry = ns:TargetFontEntry(targetKey)
    block.title:SetText(ns:L("TARGET_" .. targetKey))
    ns.UIKit:FitFontString(block.title, 280, 1)
    block.sizeLabel:SetText(ns:L("SIZE"))
    ns.UIKit:FitFontString(block.sizeLabel, 36, 1)
    block.fontButton.label:SetText(cfg.font == "inherit" and ns:L("FONT_INHERIT_UI") or (entry and entry.name or ns:L("FONT_DEFAULT")))
    SettingsDialog.renderFontSample(block.fontButton.label, entry, targetKey, 13)

    local chat = targetKey == "chat"
    block.sizeLabel:SetShown(not chat)
    block.minus:SetShown(not chat)
    block.plus:SetShown(not chat)
    block.value:SetShown(not chat)
    SettingsDialog.setButtonText(block.value, (cfg.scale or 100) .. "%")

    local scale = chat and 1 or (cfg.scale or 100) / 100
    SettingsDialog.renderFontSample(block.preview, entry, targetKey, math.floor(PREVIEW_SIZE * scale + 0.5))
    block.preview:SetText(PREVIEW_SAMPLE)

    if ns:FontLacksClientScript(entry) then
        block.note:SetText(ns:L("MISSING_GLYPH_SHORT"))
    elseif ns:NeedsRelog(targetKey) then
        block.note:SetText(ns:L("NOTE_RELOG_SHORT"))
    else
        block.note:SetText("")
    end
    ns.UIKit:FitFontString(block.note, 180, 1)
end

-----------------------------------------------------------------------------
-- Custom Fonts
-----------------------------------------------------------------------------
function SettingsDialog.addCustomFont(text)
    local file = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if file == "" then return end
    if not file:lower():find("%.[ot]tf$") then file = file .. ".ttf" end
    for _, custom in ipairs(ns:CustomFontFiles()) do
        if custom.file:lower() == file:lower() then
            ns:Print(string.format(ns:L("MSG_CUSTOM_DUP"), file))
            return
        end
    end
    if not ns:IsFontFileUsable(ns:CustomFontPath(file)) then
        ns:Print(string.format(ns:L("MSG_CUSTOM_FAIL"), ns:CustomFontPath(file)))
        return
    end
    table.insert(ns.db.customFonts, { file = file })
    ns:Print(string.format(ns:L("MSG_CUSTOM_OK"), file))
    advancedFrame.customInput:SetText("")
    ns:RefreshOptions()
end

function SettingsDialog.removeCustomFont(file)
    local removed
    for index, custom in ipairs(ns.db.customFonts) do
        if custom.file == file then removed = table.remove(ns.db.customFonts, index) break end
    end
    if not removed then return end
    -- targets using it go back to the game font
    for _, targetKey in ipairs(ns.TARGET_ORDER) do
        local cfg = ns:TargetConfig(targetKey)
        if cfg.font == "custom:" .. removed.file then
            cfg.font = "default"
            ns:ApplyTarget(targetKey)
        end
    end
    ns:RefreshOptions()
end

function SettingsDialog.buildCustomSection(top)
    local parent = advancedFrame
    parent.customTitle = ns.UIKit:CreateLabel(parent, "GameFontNormal", "TOPLEFT", parent, "TOPLEFT", 20, top, Theme.accent)
    parent.customHint = ns.UIKit:CreateLabel(parent, "GameFontHighlightSmall", "TOPLEFT", parent, "TOPLEFT", 20, top - 20, Theme.textMuted)
    parent.customHint:SetWidth(WINDOW_WIDTH - 40)
    parent.customHint:SetJustifyH("LEFT")

    local input = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    input:SetSize(330, 26)
    input:SetPoint("TOPLEFT", 20, top - 64)
    ns.UIKit:ApplySurface(input, Theme.bgInput, Theme.border)
    input:SetFontObject(ChatFontNormal)
    input:SetJustifyH("LEFT")
    input:SetTextInsets(8, 8, 0, 0)
    input:SetAutoFocus(false)
    input:SetScript("OnEnterPressed", function(self) SettingsDialog.addCustomFont(self:GetText()) end)
    input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    input:SetScript("OnEditFocusGained", function(self) self:SetBackdropBorderColor(unpack(Theme.accent)) end)
    input:SetScript("OnEditFocusLost", function(self) self:SetBackdropBorderColor(unpack(Theme.border)) end)
    parent.customInput = input
    SettingsDialog.attachTip(input, "TIP_CUSTOM")

    parent.customAdd = SettingsDialog.createButton(parent, 100, 26, "", function()
        SettingsDialog.addCustomFont(input:GetText())
    end)
    parent.customAdd:SetPoint("LEFT", input, "RIGHT", 10, 0)
    SettingsDialog.attachTip(parent.customAdd, "TIP_CUSTOM")
    parent.customAdd.label:SetJustifyH("CENTER")

    parent.customEmpty = ns.UIKit:CreateLabel(parent, "GameFontDisableSmall", "TOPLEFT", parent, "TOPLEFT", 22, top - 100, Theme.textMuted)
    parent.customMore = ns.UIKit:CreateLabel(parent, "GameFontDisableSmall", "TOPLEFT", parent, "TOPLEFT", 22, top - 96 - CUSTOM_ROWS * 24, Theme.textMuted)
    parent.customRows = {}
    for index = 1, CUSTOM_ROWS do
        local rowTop = top - 96 - (index - 1) * 24
        local row = {}
        row.text = parent:CreateFontString(nil, "OVERLAY")
        row.text:SetPoint("TOPLEFT", 22, rowTop - 4)
        row.text:SetWidth(330)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        row.remove = SettingsDialog.createButton(parent, 100, 22, "", function()
            SettingsDialog.removeCustomFont(row.file)
        end)
        row.remove:SetPoint("TOPLEFT", 360, rowTop)
        row.remove.label:SetJustifyH("CENTER")
        parent.customRows[index] = row
    end
end

function SettingsDialog.refreshCustomSection()
    if not advancedFrame then return end
    advancedFrame.customTitle:SetText(ns:L("CUSTOM_TITLE"))
    advancedFrame.customHint:SetText(ns:L("CUSTOM_HINT_SHORT"))
    SettingsDialog.setButtonText(advancedFrame.customAdd, ns:L("CUSTOM_ADD"))
    local customs = ns:CustomFontFiles()
    local overflow = #customs - CUSTOM_ROWS
    advancedFrame.customEmpty:SetText(#customs == 0 and ns:L("CUSTOM_EMPTY") or "")
    advancedFrame.customMore:SetText(overflow > 0 and string.format(ns:L("CUSTOM_MORE"), overflow) or "")
    for index, row in ipairs(advancedFrame.customRows) do
        local custom = customs[index]
        row.file = custom and custom.file
        if custom then
            row.text:SetText(custom.file .. (custom.auto and ("  |cffA7B9C5(" .. ns:L("SRC_auto") .. ")|r") or ""))
            SettingsDialog.setFontSafely(row.text, ns:CustomFontPath(custom.file), 13)
            row.text:SetTextColor(unpack(Theme.textBody))
            SettingsDialog.setButtonText(row.remove, ns:L("CUSTOM_REMOVE"))
        end
        row.text:SetShown(custom ~= nil)
        -- files found in the folder are removed by deleting the file, not here
        row.remove:SetShown(custom ~= nil and not custom.auto)
    end
end

-----------------------------------------------------------------------------
-- Addon Language (combo box: click it, then click a language in the list)
-----------------------------------------------------------------------------
function SettingsDialog.buildLanguageList()
    if languageList then return languageList end
    languageList = CreateFrame("Frame", nil, configFrame, "BackdropTemplate")
    languageList:SetSize(LANGUAGE_LIST_WIDTH, 12 + #ns.LANGUAGE_ORDER * LANGUAGE_ROW_HEIGHT)
    languageList:SetFrameStrata("FULLSCREEN_DIALOG")
    languageList:SetFrameLevel(configFrame:GetFrameLevel() + 50)
    languageList:EnableMouse(true)
    languageList:SetClampedToScreen(true)
    ns.UIKit:ApplySurface(languageList, Theme.bgPrimary, Theme.accent)
    languageList.rows = {}
    for index, code in ipairs(ns.LANGUAGE_ORDER) do
        local row = CreateFrame("Button", nil, languageList)
        row:SetSize(LANGUAGE_LIST_WIDTH - 12, LANGUAGE_ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 6, -6 - (index - 1) * LANGUAGE_ROW_HEIGHT)
        row.code = code
        row.highlight = row:CreateTexture(nil, "BACKGROUND")
        row.highlight:SetAllPoints()
        row.highlight:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.18)
        row.highlight:Hide()
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")   -- same font as the rest of the window
        row.text:SetPoint("LEFT", 8, 0)
        row.text:SetPoint("RIGHT", -8, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        row:SetScript("OnEnter", function(self) self.highlight:Show() end)
        row:SetScript("OnLeave", function(self) self.highlight:Hide() end)
        row:SetScript("OnClick", function(self)
            languageList:Hide()
            ns:SetLanguage(self.code)
        end)
        languageList.rows[index] = row
    end
    languageList:Hide()
    return languageList
end

function SettingsDialog.fillLanguageList()
    local current = ns.db.language or "auto"
    for _, row in ipairs(languageList.rows) do
        local selected = row.code == current
        row.text:SetText((selected and "> " or "") .. ns:LanguageName(row.code))
        local color = selected and Theme.accent or Theme.textBody
        row.text:SetTextColor(color[1], color[2], color[3])
        ns.UIKit:FitFontString(row.text, LANGUAGE_LIST_WIDTH - 28, 1)
    end
end

function SettingsDialog.toggleLanguageList()
    SettingsDialog.buildLanguageList()
    if languageList:IsShown() then
        languageList:Hide()
        return
    end
    if pickerFrame then pickerFrame:Hide() end
    languageList:ClearAllPoints()
    languageList:SetPoint("TOPRIGHT", configFrame.languageButton, "BOTTOMRIGHT", 0, -2)
    SettingsDialog.fillLanguageList()
    languageList:Show()
end

function SettingsDialog.buildLanguageButton()
    local button = SettingsDialog.createButton(configFrame, LANGUAGE_BUTTON_WIDTH, 22, "", SettingsDialog.toggleLanguageList)
    button:SetPoint("TOPRIGHT", -42, -11)
    button.label:ClearAllPoints()
    button.label:SetPoint("LEFT", 8, 0)
    button.label:SetPoint("RIGHT", -22, 0)
    button.label:SetJustifyH("LEFT")
    button.fitWidth = LANGUAGE_BUTTON_WIDTH - 30
    -- the dropdown arrow: the game's right arrow turned to point down
    button.arrow = button:CreateTexture(nil, "OVERLAY")
    button.arrow:SetSize(12, 12)
    button.arrow:SetPoint("RIGHT", -7, 0)
    button.arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    button.arrow:SetTexCoord(0, 1, 1, 1, 0, 0, 1, 0)
    button.arrow:SetVertexColor(Theme.accent[1], Theme.accent[2], Theme.accent[3])
    SettingsDialog.attachTip(button, "TIP_LANGUAGE")
    configFrame.languageButton = button

    configFrame.languageLabel = ns.UIKit:CreateLabel(configFrame, "GameFontHighlightSmall", "RIGHT", button, "LEFT", -6, 0, Theme.textMuted)
    configFrame.languageLabel:SetJustifyH("RIGHT")
end

function SettingsDialog.refreshLanguageButton()
    configFrame.languageLabel:SetText(ns:L("LANGUAGE"))
    ns.UIKit:FitFontString(configFrame.languageLabel, 80, 1)
    SettingsDialog.setButtonText(configFrame.languageButton, ns:LanguageName(ns.db.language))
    if languageList and languageList:IsShown() then SettingsDialog.fillLanguageList() end
end

function ns:SetLanguage(code)
    if code ~= "auto" and not self.LANGUAGE_NAMES[code] then return end
    local db = self.db or self:InitializeDatabase()
    db.language = code
    self:RefreshOptions()
    if self.RefreshBlizzardPanel then self:RefreshBlizzardPanel() end
    self:Print(string.format(self:L("MSG_LANGUAGE"), self:LanguageName(code)))
end

-----------------------------------------------------------------------------
-- Window
-----------------------------------------------------------------------------
function SettingsDialog.toggleAdvanced()
    if not advancedFrame then
        advancedFrame = CreateFrame("Frame", "EzWoWFontChangerAdvanced", configFrame, "BackdropTemplate")
        SettingsDialog.advancedFrame = advancedFrame
        advancedFrame:SetSize(WINDOW_WIDTH, 366)
        advancedFrame:SetPoint("CENTER", configFrame, "CENTER")
        advancedFrame:SetFrameLevel(configFrame:GetFrameLevel() + 20)
        advancedFrame:SetClampedToScreen(true)
        advancedFrame:EnableMouse(true)
        ns.UIKit:ApplySurface(advancedFrame, Theme.bgPrimary, Theme.accent)
        advancedFrame.titleText = ns.UIKit:CreateLabel(advancedFrame, "GameFontNormalLarge", "TOPLEFT", advancedFrame, "TOPLEFT", 20, -16, Theme.accent)
        local close = SettingsDialog.createButton(advancedFrame, 24, 24, "x", function() advancedFrame:Hide() end)
        close:SetPoint("TOPRIGHT", -10, -10)
        close.label:SetJustifyH("CENTER")
        if ns:FamilySupported() then
            advancedFrame.familyButton = SettingsDialog.createButton(advancedFrame, 230, 28, "", SettingsDialog.toggleFamilyWindow)
            advancedFrame.familyButton:SetPoint("TOPLEFT", 20, -56)
            advancedFrame.familyButton.label:SetJustifyH("CENTER")
            SettingsDialog.attachTip(advancedFrame.familyButton, "TIP_FAMILY")
        end
        advancedFrame.testButton = SettingsDialog.createButton(advancedFrame, advancedFrame.familyButton and 240 or 480, 28, "", function() SettingsDialog.toggleTestWindow() end)
        advancedFrame.testButton:SetPoint("TOPRIGHT", -20, -56)
        advancedFrame.testButton.label:SetJustifyH("CENTER")
        SettingsDialog.attachTip(advancedFrame.testButton, "TIP_TEST")
        SettingsDialog.buildCustomSection(-108)
        advancedFrame:SetScript("OnHide", function()
            if familyFrame then familyFrame:Hide() end
            if pickerFrame then pickerFrame:Hide() end
        end)
        tinsert(UISpecialFrames, "EzWoWFontChangerAdvanced")
        advancedFrame:Hide()
    end
    advancedFrame:SetShown(not advancedFrame:IsShown())
    ns:RefreshOptions()
end

function SettingsDialog.build()
    if configFrame then return configFrame end

    configFrame = CreateFrame("Frame", "EzWoWFontChangerSettings", UIParent, "BackdropTemplate")
    SettingsDialog.configFrame = configFrame
    configFrame:SetSize(WINDOW_WIDTH, 546 + (#ns.TARGET_ORDER - 4) * BLOCK_HEIGHT)
    configFrame:SetPoint("CENTER")
    configFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    configFrame:SetToplevel(true)
    configFrame:SetClampedToScreen(true)
    configFrame:SetMovable(true)
    configFrame:EnableMouse(true)
    configFrame:RegisterForDrag("LeftButton")
    configFrame:SetScript("OnDragStart", configFrame.StartMoving)
    configFrame:SetScript("OnDragStop", configFrame.StopMovingOrSizing)
    configFrame:SetScript("OnHide", function()
        if pickerFrame then pickerFrame:Hide() end
        if languageList then languageList:Hide() end
        if familyFrame then familyFrame:Hide() end
        if advancedFrame then advancedFrame:Hide() end
    end)
    ns.UIKit:ApplySurface(configFrame, Theme.bgPrimary, Theme.border)
    tinsert(UISpecialFrames, "EzWoWFontChangerSettings")

    local accentLine = configFrame:CreateTexture(nil, "ARTWORK")
    accentLine:SetColorTexture(unpack(Theme.accent))
    accentLine:SetPoint("TOPLEFT", 1, -1)
    accentLine:SetPoint("TOPRIGHT", -1, -1)
    accentLine:SetHeight(2)

    configFrame.titleText = ns.UIKit:CreateLabel(configFrame, "GameFontNormalLarge", "TOPLEFT", configFrame, "TOPLEFT", 18, -14, Theme.accent)
    configFrame.subtitle = ns.UIKit:CreateLabel(configFrame, "GameFontHighlightSmall", "TOPLEFT", configFrame, "TOPLEFT", 18, -36, Theme.textMuted)
    local close = SettingsDialog.createButton(configFrame, 24, 24, "x", function() configFrame:Hide() end)
    close:SetPoint("TOPRIGHT", -10, -10)
    close.label:SetJustifyH("CENTER")
    SettingsDialog.buildLanguageButton()
    configFrame.allFontButton = SettingsDialog.createButton(configFrame, WINDOW_WIDTH - 40, 28, "", SettingsDialog.openAllFontPicker)
    configFrame.allFontButton:SetPoint("TOPLEFT", 20, -66)
    configFrame.allFontButton.label:SetJustifyH("CENTER")
    SettingsDialog.attachTip(configFrame.allFontButton, "TIP_ALL_FONTS")

    configFrame.blocks = {}
    for index, targetKey in ipairs(ns.TARGET_ORDER) do
        configFrame.blocks[targetKey] = SettingsDialog.buildTargetBlock(targetKey, index)
    end
    configFrame.quickHint = ns.UIKit:CreateLabel(configFrame, "GameFontHighlightSmall", "TOPLEFT", configFrame, "TOPLEFT", 20, -450 - (#ns.TARGET_ORDER - 4) * BLOCK_HEIGHT, Theme.textMuted)
    configFrame.quickHint:SetWidth(WINDOW_WIDTH - 40)
    configFrame.quickHint:SetJustifyH("LEFT")

    configFrame.resetButton = SettingsDialog.createButton(configFrame, 140, 30, "", function() ns:ResetAllTargets() end)
    configFrame.resetButton:SetPoint("BOTTOMLEFT", 20, 16)
    configFrame.advancedButton = SettingsDialog.createButton(configFrame, 140, 30, "", SettingsDialog.toggleAdvanced)
    configFrame.advancedButton:SetPoint("BOTTOM", 0, 16)
    configFrame.reloadButton = SettingsDialog.createButton(configFrame, 140, 30, "", function() ReloadUI() end)
    configFrame.reloadButton:SetPoint("BOTTOMRIGHT", -20, 16)
    for _, button in ipairs({ configFrame.resetButton, configFrame.advancedButton, configFrame.reloadButton }) do
        button.label:SetJustifyH("CENTER")
    end
    SettingsDialog.attachTip(configFrame.resetButton, "TIP_RESET")
    SettingsDialog.attachTip(configFrame.advancedButton, "TIP_ADVANCED")
    SettingsDialog.attachTip(configFrame.reloadButton, "TIP_RELOAD")

    configFrame:Hide()
    return configFrame
end

function ns:RefreshOptions()
    if not configFrame or not configFrame:IsShown() then return end
    configFrame.titleText:SetText(self:L("TITLE"))
    SettingsDialog.refreshLanguageButton()
    configFrame.subtitle:SetText(self:L("SIMPLE_SUBTITLE"))
    configFrame.subtitle:SetWidth(WINDOW_WIDTH - 40)
    configFrame.subtitle:SetWordWrap(false)
    ns.UIKit:FitFontString(configFrame.subtitle, WINDOW_WIDTH - 40, 1)
    configFrame.quickHint:SetText(self:L("QUICK_HINT"))
    SettingsDialog.setButtonText(configFrame.allFontButton, self:L("ALL_FONTS"))
    for targetKey, block in pairs(configFrame.blocks) do
        SettingsDialog.refreshTargetBlock(targetKey, block)
    end
    SettingsDialog.setButtonText(configFrame.resetButton, self:L("RESET_ALL"))
    SettingsDialog.setButtonText(configFrame.reloadButton, self:L("RELOAD"))
    SettingsDialog.setButtonText(configFrame.advancedButton, self:L("ADVANCED"))
    if advancedFrame and advancedFrame:IsShown() then
        advancedFrame.titleText:SetText(self:L("ADVANCED"))
        SettingsDialog.setButtonText(advancedFrame.testButton, self:L("TEST_BUTTON"))
        if advancedFrame.familyButton then SettingsDialog.setButtonText(advancedFrame.familyButton, self:L("FAMILY_BUTTON")) end
        SettingsDialog.refreshCustomSection()
    end
    if SettingsDialog.refreshTestWindow then SettingsDialog.refreshTestWindow() end
    SettingsDialog.refreshFamilyWindow()
    if pickerFrame and pickerFrame:IsShown() then SettingsDialog.fillPicker() end
end

function ns:OpenOptions()
    SettingsDialog.build()
    configFrame:Show()
    configFrame:Raise()
    self:RefreshOptions()
end

function ns:ToggleOptions()
    SettingsDialog.build()
    if configFrame:IsShown() then
        configFrame:Hide()
    else
        self:OpenOptions()
    end
end

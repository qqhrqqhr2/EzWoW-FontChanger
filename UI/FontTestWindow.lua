--===========================================================================
-- EzWoW - Font Changer
-- UI/FontTestWindow.lua : Per-Language Font Test (samples + free text)
--===========================================================================
local _, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local SettingsDialog = ns.SettingsDialog
local Theme = ns.UIKit.Theme

-- Same sample in every client language: the point is to see the letters
local TEST_LINES = {
    { key = "korean",   alphabet = "korean",            sample = "다람쥐 헌 쳇바퀴에 타고파 · 대족장 드랄" },
    { key = "latin",    alphabet = "roman",             sample = "Ŝtěfän Ørjåsæter Çağrı Łódź ÀÉÎÕÜß" },
    { key = "cyrillic", alphabet = "russian",           sample = "Съешь же ещё этих мягких булок" },
    { key = "greek",    alphabet = "roman",             sample = "Ξεσκεπάζω την ψυχοφθόρα βδελυγμία" },
    { key = "chinese",  alphabet = "simplifiedchinese", sample = "小龍女 大家好 一起刷副本吗 臺灣 謝謝" },
    { key = "japanese", alphabet = "roman",             sample = "さくら カタカナ こんにちは" },
    { key = "symbols",  alphabet = "roman",             sample = "★☆♥♡♪→←✓※●◆■▲…«»€©™" },
}
local SAMPLE_SIZE = 15
local ROW_HEIGHT = 26

local testFrame
local testTargetKey = "chat"

-- Font that will draw this language for the target, as a catalog entry (nil = game font)
function SettingsDialog.testEntryFor(targetKey, line)
    local cfg = ns:TargetConfig(targetKey)
    local entry = ns:ResolveFont(cfg.font)
    if entry and entry.family then
        local memberId = ns.db.family[line.alphabet]
        return memberId and memberId ~= "default" and ns:ResolveFont(memberId) or nil
    end
    if entry and entry.autoMix and ns:FamilySupported() and line.key == "chinese" then
        return ns:ResolveFont("bundled:worldsans")   -- automatic Han from World Sans
    end
    return entry
end

function SettingsDialog.testStatus(entry, coverageKey)
    local coverage = ns:FontCoverage(entry, coverageKey)
    if coverage == nil then return ns:L("STATUS_UNKNOWN"), Theme.textMuted end
    if coverage >= 0.99 then return ns:L("STATUS_OK"), { 0.45, 0.85, 0.45, 1 } end
    if coverage > 0 then return ns:L("STATUS_PART"), Theme.warning end
    return ns:L("STATUS_NONE"), Theme.warning
end

function SettingsDialog.buildTestWindow()
    if testFrame then return testFrame end
    local parent = SettingsDialog.configFrame
    testFrame = CreateFrame("Frame", "EzWoWFontChangerTest", parent, "BackdropTemplate")
    testFrame:SetSize(470, 196 + #TEST_LINES * ROW_HEIGHT)
    testFrame:SetPoint("TOPRIGHT", parent, "TOPLEFT", -8, 0)
    testFrame:SetFrameLevel(parent:GetFrameLevel() + 10)
    testFrame:EnableMouse(true)
    ns.UIKit:ApplySurface(testFrame, Theme.bgPrimary, Theme.accent)

    testFrame.title = ns.UIKit:CreateLabel(testFrame, "GameFontNormal", "TOPLEFT", testFrame, "TOPLEFT", 16, -14, Theme.accent)
    testFrame.hint = ns.UIKit:CreateLabel(testFrame, "GameFontHighlightSmall", "TOPLEFT", testFrame, "TOPLEFT", 16, -34, Theme.textMuted)
    testFrame.hint:SetWidth(438)
    testFrame.hint:SetJustifyH("LEFT")
    local close = SettingsDialog.createButton(testFrame, 22, 22, "x", function() testFrame:Hide() end)
    close:SetPoint("TOPRIGHT", -8, -8)
    close.label:SetJustifyH("CENTER")

    -- which area's font to test; click cycles through the four areas
    testFrame.targetButton = SettingsDialog.createButton(testFrame, 438, 26, "", function()
        for index, targetKey in ipairs(ns.TARGET_ORDER) do
            if targetKey == testTargetKey then
                testTargetKey = ns.TARGET_ORDER[index % #ns.TARGET_ORDER + 1]
                break
            end
        end
        SettingsDialog.refreshTestWindow()
    end)
    testFrame.targetButton:SetPoint("TOPLEFT", 16, -66)
    SettingsDialog.attachTip(testFrame.targetButton, "TIP_TEST_TARGET")

    testFrame.rows = {}
    for index, line in ipairs(TEST_LINES) do
        local top = -102 - (index - 1) * ROW_HEIGHT
        local row = {}
        row.label = ns.UIKit:CreateLabel(testFrame, "GameFontHighlightSmall", "TOPLEFT", testFrame, "TOPLEFT", 16, top - 4, Theme.textMuted)
        row.label:SetWidth(78)
        row.label:SetJustifyH("LEFT")
        row.sample = testFrame:CreateFontString(nil, "OVERLAY")
        row.sample:SetPoint("TOPLEFT", 98, top)
        row.sample:SetWidth(280)
        row.sample:SetJustifyH("LEFT")
        row.sample:SetWordWrap(false)
        row.sample:SetTextColor(unpack(Theme.textBody))
        row.status = ns.UIKit:CreateLabel(testFrame, "GameFontHighlightSmall", "TOPRIGHT", testFrame, "TOPRIGHT", -16, top - 4, Theme.textMuted)
        row.status:SetWidth(76)
        row.status:SetJustifyH("RIGHT")
        testFrame.rows[index] = row
    end

    local inputTop = -110 - #TEST_LINES * ROW_HEIGHT
    testFrame.inputLabel = ns.UIKit:CreateLabel(testFrame, "GameFontHighlightSmall", "TOPLEFT", testFrame, "TOPLEFT", 16, inputTop, Theme.textMuted)
    local input = CreateFrame("EditBox", nil, testFrame, "BackdropTemplate")
    input:SetSize(438, 26)
    input:SetPoint("TOPLEFT", 16, inputTop - 16)
    ns.UIKit:ApplySurface(input, Theme.bgInput, Theme.border)
    input:SetTextInsets(8, 8, 0, 0)
    input:SetAutoFocus(false)
    input:SetFontObject(ChatFontNormal)
    input:SetScript("OnTextChanged", function() SettingsDialog.refreshTestPreview() end)
    input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    input:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    testFrame.input = input
    SettingsDialog.attachTip(input, "TIP_TEST_INPUT")
    testFrame.preview = testFrame:CreateFontString(nil, "OVERLAY")
    testFrame.preview:SetPoint("TOPLEFT", 18, inputTop - 52)
    testFrame.preview:SetWidth(434)
    testFrame.preview:SetJustifyH("LEFT")
    testFrame.preview:SetWordWrap(false)
    testFrame.preview:SetTextColor(unpack(Theme.textBody))

    parent:HookScript("OnHide", function() testFrame:Hide() end)
    testFrame:Hide()
    return testFrame
end

-- target font (family or single file) at the target's size, like in game
function SettingsDialog.renderTargetFont(fontString, targetKey)
    local cfg = ns:TargetConfig(targetKey)
    local scale = targetKey == "chat" and 1 or (cfg.scale or 100) / 100
    SettingsDialog.renderFontSample(fontString, ns:ResolveFont(cfg.font), targetKey, math.floor(SAMPLE_SIZE * scale + 0.5))
end

function SettingsDialog.refreshTestPreview()
    if not (testFrame and testFrame:IsShown()) then return end
    SettingsDialog.renderTargetFont(testFrame.preview, testTargetKey)
    local text = testFrame.input:GetText()
    testFrame.preview:SetText(text ~= "" and text or "|cff63727B" .. ns:L("TEST_INPUT_EMPTY") .. "|r")
end

function SettingsDialog.refreshTestWindow()
    if not (testFrame and testFrame:IsShown()) then return end
    testFrame.title:SetText(ns:L("TEST_TITLE"))
    testFrame.hint:SetText(ns:L("TEST_HINT"))
    testFrame.inputLabel:SetText(ns:L("TEST_INPUT"))
    local entry = ns:ResolveFont(ns:TargetConfig(testTargetKey).font)
    testFrame.targetButton.label:SetText(string.format(ns:L("TEST_TARGET"), ns:L("TARGET_" .. testTargetKey), entry and entry.name or ns:L("FONT_DEFAULT")))
    local singleFile = testTargetKey == "combat" or testTargetKey == "nameplate"
    for index, line in ipairs(TEST_LINES) do
        local row = testFrame.rows[index]
        row.label:SetText(ns:L("LANG_" .. line.key))
        SettingsDialog.renderTargetFont(row.sample, testTargetKey)
        row.sample:SetText(line.sample)
        local drawingEntry = SettingsDialog.testEntryFor(testTargetKey, line)
        if singleFile and entry and entry.family then
            -- names above heads / combat numbers use one file even with the mix
            drawingEntry = ns:ResolveFont("bundled:worldsans")
        elseif singleFile and entry and entry.autoMix then
            -- one file there, so no automatic Han: show the truth for names above heads
            drawingEntry = entry
        end
        local statusText, color = SettingsDialog.testStatus(drawingEntry, line.key)
        row.status:SetText(statusText)
        row.status:SetTextColor(color[1], color[2], color[3])
    end
    SettingsDialog.refreshTestPreview()
end

function SettingsDialog.toggleTestWindow()
    SettingsDialog.buildTestWindow()
    testFrame:SetShown(not testFrame:IsShown())
    SettingsDialog.refreshTestWindow()
end

--===========================================================================
-- EzWoW - Font Changer
-- Modules/Diagnostics.lua : /ezfont diag - how the client draws Chinese
--===========================================================================
local _, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local SAMPLE = "大家好 小龍女 扫荡者 · 가나다 ABC"
local diagFrame

-- Draws the same Chinese text four ways so a screenshot shows which one the
-- client actually renders: plain SetFont, a full-member family, a family
-- built with only the Chinese members, and the game's own chat font.
function ns:ShowFontDiagnostics()
    local jua = self.FONT_PATH .. "EzWoW-Jua.ttf"
    if not diagFrame then
        diagFrame = CreateFrame("Frame", "EzWoWFontChangerDiag", UIParent, "BackdropTemplate")
        diagFrame:SetSize(620, 250)
        diagFrame:SetPoint("CENTER", 0, 120)
        diagFrame:SetFrameStrata("DIALOG")
        diagFrame:EnableMouse(true)
        diagFrame:SetMovable(true)
        diagFrame:RegisterForDrag("LeftButton")
        diagFrame:SetScript("OnDragStart", diagFrame.StartMoving)
        diagFrame:SetScript("OnDragStop", diagFrame.StopMovingOrSizing)
        ns.UIKit:ApplySurface(diagFrame, ns.UIKit.Theme.bgPrimary, ns.UIKit.Theme.accent)
        diagFrame.rows = {}
        for index = 1, 4 do
            local label = diagFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            label:SetPoint("TOPLEFT", 14, -14 - (index - 1) * 52)
            local text = diagFrame:CreateFontString(nil, "OVERLAY")
            text:SetPoint("TOPLEFT", 14, -30 - (index - 1) * 52)
            diagFrame.rows[index] = { label = label, text = text }
        end
        local close = CreateFrame("Button", nil, diagFrame, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 0, 0)
    end
    local rows = diagFrame.rows
    local results = {}

    -- 1) plain SetFont on a fresh font string
    local ok1 = pcall(rows[1].text.SetFont, rows[1].text, jua, 22, "")
    rows[1].label:SetText("1) SetFont(EzWoW Jua)  ok=" .. tostring(ok1))
    results[1] = ok1

    -- 2) family with every member = Jua
    local members, okFamily, family = {}, false, nil
    for _, alphabet in ipairs(self.FAMILY_ALPHABETS) do
        members[#members + 1] = { alphabet = alphabet, file = jua, height = 22, flags = "" }
    end
    if CreateFontFamily then
        okFamily, family = pcall(CreateFontFamily, "EzWoWFontChangerDiag" .. math.random(1, 1e9), members)
    end
    local okSet = okFamily and family and pcall(rows[2].text.SetFontObject, rows[2].text, family)
    rows[2].label:SetText("2) CreateFontFamily(all = Jua)  create=" .. tostring(okFamily) .. "  apply=" .. tostring(okSet)
        .. (okFamily and "" or ("  " .. tostring(family))))
    if not okSet then rows[2].text:SetFontObject(GameFontHighlight) end

    -- 3) family where only the Chinese members are Jua, others the game font
    local gameFont = STANDARD_TEXT_FONT
    local mixed = {}
    for _, alphabet in ipairs(self.FAMILY_ALPHABETS) do
        local chinese = alphabet == "simplifiedchinese" or alphabet == "traditionalchinese"
        mixed[#mixed + 1] = { alphabet = alphabet, file = chinese and jua or gameFont, height = 22, flags = "" }
    end
    local okMixed, mixedFamily = false, nil
    if CreateFontFamily then
        okMixed, mixedFamily = pcall(CreateFontFamily, "EzWoWFontChangerDiag" .. math.random(1, 1e9), mixed)
    end
    local okSet3 = okMixed and mixedFamily and pcall(rows[3].text.SetFontObject, rows[3].text, mixedFamily)
    rows[3].label:SetText("3) family(Chinese = Jua, others = game font)  apply=" .. tostring(okSet3))
    if not okSet3 then rows[3].text:SetFontObject(GameFontHighlight) end

    -- 4) the game's own chat font, for comparison
    rows[4].text:SetFontObject(ChatFontNormal)
    rows[4].label:SetText("4) ChatFontNormal (game)  " .. tostring(select(1, ChatFontNormal:GetFont())))

    for _, row in ipairs(rows) do
        row.text:SetText(SAMPLE)
        row.text:SetTextColor(1, 1, 1)
    end
    diagFrame:Show()
    self:Print("locale=" .. tostring(GetLocale()) .. "  CreateFontFamily=" .. tostring(CreateFontFamily ~= nil)
        .. "  STANDARD_TEXT_FONT=" .. tostring(STANDARD_TEXT_FONT))
end

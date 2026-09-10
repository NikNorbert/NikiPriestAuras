-- NikiPriestAuras: group/raid Weakened Soul timer.
--
-- Vanilla has no group-role API. The recipient of the player's most recent
-- successful Power Word: Shield cast is therefore treated as the tank. With
-- SuperWoW, UNIT_CASTEVENT supplies the exact target even for mouseover casts.

local WEAKENED_SOUL_DURATION = 15
local UPDATE_INTERVAL = 0.10
local ICON_SIZE = 64
local BASE_FONT_SIZE = 19
local DEFAULT_TIMER_SIZE = 19

local locale = GetLocale and GetLocale() or "enUS"
local timerLabel = "Tank Weakened Soul timer"
local sizeLabel = "Timer size"
local pixelSuffix = " px"
local moveHint = "Drag the red timer to place it anywhere on screen"
if locale == "ruRU" then
    timerLabel = "Таймер Weakened Soul у танка"
    sizeLabel = "Размер таймера"
    pixelSuffix = " пкс"
    moveHint = "Перетащите красный таймер в любое место экрана"
end

local trackedName = nil
local trackedGuid = nil
local trackedStartedAt = nil
local trackedExpiresAt = nil
local updateElapsed = 0
local timerDragging = false

local timerFrame = CreateFrame(
    "Frame",
    "NikiPriestAurasTankShieldTimer",
    UIParent
)
timerFrame:SetWidth(ICON_SIZE)
timerFrame:SetHeight(ICON_SIZE)
timerFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 76)
timerFrame:SetFrameStrata("HIGH")
timerFrame:SetFrameLevel(15)
timerFrame:SetMovable(true)
timerFrame:SetClampedToScreen(true)
timerFrame:RegisterForDrag("LeftButton")
timerFrame:EnableMouse(false)

-- Vanilla's font renderer stops producing reliable larger glyphs above about
-- 19 px. Keep a crisp 19 px base glyph and scale this visual child instead;
-- the shield and number then grow together throughout the full slider range.
local timerVisual = CreateFrame("Frame", nil, timerFrame)
timerVisual:SetWidth(ICON_SIZE)
timerVisual:SetHeight(ICON_SIZE)
timerVisual:SetPoint("CENTER", timerFrame, "CENTER", 0, 0)

local timerTexture = timerVisual:CreateTexture(nil, "ARTWORK")
timerTexture:SetTexture(
    "Interface\\AddOns\\NikiPriestAuras\\Textures\\PowerWordShieldReminder_256"
)
timerTexture:SetAllPoints(timerVisual)
timerTexture:SetVertexColor(1.00, 0.20, 0.20, 1)

local timerText = timerVisual:CreateFontString(nil, "OVERLAY")
timerText:SetPoint("CENTER", timerVisual, "CENTER", 0, 0)
timerText:SetTextColor(1.00, 0.94, 0.86)
timerText:SetShadowColor(0.45, 0.00, 0.00, 1)
timerText:SetShadowOffset(2, -2)

timerFrame:Hide()

local shieldSpellIds = {
    [17] = true,
    [592] = true,
    [600] = true,
    [3747] = true,
    [6065] = true,
    [6066] = true,
    [10898] = true,
    [10899] = true,
    [10900] = true,
    [10901] = true
}

local function InitializeOptions()
    if type(NikiPriestAurasDB) ~= "table" then
        NikiPriestAurasDB = {}
    end
    if type(NikiPriestAurasDB.tankShieldTimerEnabled) ~= "boolean" then
        NikiPriestAurasDB.tankShieldTimerEnabled = true
    end
    if type(NikiPriestAurasDB.tankShieldTimerFontSize) ~= "number" then
        NikiPriestAurasDB.tankShieldTimerFontSize = DEFAULT_TIMER_SIZE
    end
    if type(NikiPriestAurasDB.tankShieldTimerX) ~= "number" then
        NikiPriestAurasDB.tankShieldTimerX = 0
    end
    if type(NikiPriestAurasDB.tankShieldTimerY) ~= "number" then
        NikiPriestAurasDB.tankShieldTimerY = 76
    end
    if NikiPriestAurasDB.tankShieldTimerFontSize < 12 then
        NikiPriestAurasDB.tankShieldTimerFontSize = 12
    elseif NikiPriestAurasDB.tankShieldTimerFontSize > 64 then
        NikiPriestAurasDB.tankShieldTimerFontSize = 64
    end
end

local function ApplyTimerStyle()
    InitializeOptions()
    -- Timer dimensions and opacity are intentionally independent of the
    -- central reminder icon group.
    local visualScale =
        NikiPriestAurasDB.tankShieldTimerFontSize / BASE_FONT_SIZE
    timerFrame:SetWidth(ICON_SIZE * visualScale)
    timerFrame:SetHeight(ICON_SIZE * visualScale)
    timerVisual:SetScale(visualScale)
    timerFrame:SetAlpha(1)
    timerText:SetFont(
        "Fonts\\FRIZQT__.TTF",
        BASE_FONT_SIZE,
        "OUTLINE"
    )
end

local function ApplyTimerPosition()
    InitializeOptions()
    timerFrame:ClearAllPoints()
    timerFrame:SetPoint(
        "CENTER",
        UIParent,
        "CENTER",
        NikiPriestAurasDB.tankShieldTimerX,
        NikiPriestAurasDB.tankShieldTimerY
    )
end

local function SaveTimerPosition()
    InitializeOptions()
    local frameX, frameY = timerFrame:GetCenter()
    local parentX, parentY = UIParent:GetCenter()
    if not frameX or not frameY or not parentX or not parentY then
        return
    end

    NikiPriestAurasDB.tankShieldTimerX = frameX - parentX
    NikiPriestAurasDB.tankShieldTimerY = frameY - parentY
    ApplyTimerPosition()
end

local function FinishTimerDragging()
    if not timerDragging then
        return
    end
    timerFrame:StopMovingOrSizing()
    timerDragging = false
    SaveTimerPosition()
end

timerFrame:SetScript("OnDragStart", function()
    local settings = getglobal("NikiPriestAurasSettingsFrame")
    if settings and settings:IsShown() then
        timerDragging = true
        timerFrame:StartMoving()
    end
end)

timerFrame:SetScript("OnDragStop", function()
    FinishTimerDragging()
end)

timerFrame:SetScript("OnMouseUp", function()
    FinishTimerDragging()
end)

local function NormalizeSpellId(spellId)
    if spellId and spellId < 0 then
        return spellId + 65536
    end
    return spellId
end

local function IsPowerWordShieldSpell(spellId)
    spellId = NormalizeSpellId(tonumber(spellId))
    if spellId and shieldSpellIds[spellId] then
        return true
    end

    if spellId and type(SpellInfo) == "function" then
        local spellName = SpellInfo(spellId)
        if spellName then
            spellName = string.lower(spellName)
            return spellName == "power word: shield" or
                   spellName == "слово силы: щит"
        end
    end

    return false
end

local function UnitMatchesReference(unit, reference)
    if not unit or not UnitExists(unit) or not reference or reference == "" then
        return false
    end
    return UnitIsUnit(unit, reference) and true or false
end

local function FindGroupUnit(reference)
    local raidCount = GetNumRaidMembers and GetNumRaidMembers() or 0
    local index
    if raidCount > 0 then
        for index = 1, raidCount do
            local unit = "raid" .. tostring(index)
            if UnitMatchesReference(unit, reference) then
                return unit
            end
        end
    else
        local partyCount = GetNumPartyMembers and GetNumPartyMembers() or 0
        for index = 1, partyCount do
            local unit = "party" .. tostring(index)
            if UnitMatchesReference(unit, reference) then
                return unit
            end
        end
    end
    return nil
end

local function ResolveTrackedUnit()
    local reference = trackedGuid or trackedName
    local unit = FindGroupUnit(reference)
    if unit then
        return unit
    end

    -- Non-SuperWoW clients do not expose GUIDs from UnitExists. A name scan
    -- keeps an already tracked recipient stable when raid slots are reordered.
    if trackedName then
        local raidCount = GetNumRaidMembers and GetNumRaidMembers() or 0
        local index
        if raidCount > 0 then
            for index = 1, raidCount do
                unit = "raid" .. tostring(index)
                if UnitExists(unit) and UnitName(unit) == trackedName then
                    return unit
                end
            end
        else
            local partyCount = GetNumPartyMembers and GetNumPartyMembers() or 0
            for index = 1, partyCount do
                unit = "party" .. tostring(index)
                if UnitExists(unit) and UnitName(unit) == trackedName then
                    return unit
                end
            end
        end
    end

    return nil
end

local function UnitHasAuraTexture(unit, helpful, firstPattern, secondPattern)
    local index
    for index = 1, 32 do
        local texture
        if helpful then
            texture = UnitBuff(unit, index)
        else
            texture = UnitDebuff(unit, index)
        end
        if not texture then
            break
        end

        local textureName = string.lower(texture)
        if string.find(textureName, firstPattern) or
           (secondPattern and string.find(textureName, secondPattern)) then
            return true
        end
    end
    return false
end

local function UnitHasPowerWordShield(unit)
    return UnitHasAuraTexture(unit, true, "spell_holy_powerwordshield")
end

local function UnitHasWeakenedSoul(unit)
    return UnitHasAuraTexture(
        unit,
        false,
        "spell_holy_ashestoashes",
        "weakenedsoul"
    )
end

local function ClearTrackedTank()
    trackedName = nil
    trackedGuid = nil
    trackedStartedAt = nil
    trackedExpiresAt = nil
    timerFrame:Hide()
end

local function TrackShieldRecipient(reference)
    local unit = FindGroupUnit(reference)
    if not unit then
        return
    end

    local _, guid = UnitExists(unit)
    trackedName = UnitName(unit)
    trackedGuid = guid
    trackedStartedAt = GetTime()
    trackedExpiresAt = trackedStartedAt + WEAKENED_SOUL_DURATION
    timerFrame:Hide()
end

local function UpdateTimerDisplay(force)
    InitializeOptions()

    local settingsFrame = getglobal("NikiPriestAurasSettingsFrame")
    if settingsFrame and settingsFrame:IsShown() then
        ApplyTimerStyle()
        timerText:SetText("15")
        timerFrame:Show()
        return
    end

    if NikiPriestAurasDB.addonEnabled == false or
       not NikiPriestAurasDB.tankShieldTimerEnabled or
       (type(UnitOnTaxi) == "function" and UnitOnTaxi("player")) then
        timerFrame:Hide()
        return
    end

    if not trackedExpiresAt then
        timerFrame:Hide()
        return
    end

    local now = GetTime()
    if now >= trackedExpiresAt then
        ClearTrackedTank()
        return
    end

    local unit = ResolveTrackedUnit()
    if not unit or UnitIsDeadOrGhost(unit) then
        ClearTrackedTank()
        return
    end

    -- Never show the countdown while the absorb itself remains active.
    if UnitHasPowerWordShield(unit) then
        timerFrame:Hide()
        return
    end

    if not UnitHasWeakenedSoul(unit) then
        -- Allow one second for the server aura update following an instant
        -- cast, then stop tracking if the debuff has actually disappeared.
        if trackedStartedAt and now - trackedStartedAt < 1 then
            timerFrame:Hide()
            return
        end
        ClearTrackedTank()
        return
    end

    ApplyTimerStyle()
    timerText:SetText(tostring(math.ceil(trackedExpiresAt - now)))
    timerFrame:Show()
end

local eventFrame = CreateFrame("Frame", "NikiPriestAurasTankShieldTimerEvents")
eventFrame:RegisterEvent("VARIABLES_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
eventFrame:RegisterEvent("UNIT_AURA")
pcall(eventFrame.RegisterEvent, eventFrame, "UNIT_CASTEVENT")

eventFrame:SetScript("OnEvent", function()
    if event == "VARIABLES_LOADED" then
        InitializeOptions()
        ApplyTimerStyle()
        ApplyTimerPosition()
    elseif event == "PLAYER_ENTERING_WORLD" then
        ClearTrackedTank()
    elseif event == "UNIT_CASTEVENT" then
        local caster = arg1
        local target = arg2
        local action = arg3
        local spellId = arg4
        if action == "CAST" and caster and
           UnitIsUnit(caster, "player") and
           IsPowerWordShieldSpell(spellId) then
            TrackShieldRecipient(target)
        end
    elseif event == "PARTY_MEMBERS_CHANGED" or
           event == "RAID_ROSTER_UPDATE" then
        if trackedExpiresAt and not ResolveTrackedUnit() then
            ClearTrackedTank()
        end
    end

    UpdateTimerDisplay(true)
end)

eventFrame:SetScript("OnUpdate", function()
    updateElapsed = updateElapsed + (tonumber(arg1) or 0)
    if updateElapsed >= UPDATE_INTERVAL then
        updateElapsed = 0
        UpdateTimerDisplay(false)
    end
end)

-- Add compact controls below the existing shield-frame settings.
local settingsFrame = getglobal("NikiPriestAurasSettingsFrame")
if settingsFrame then
    local enabledCheckbox = CreateFrame(
        "CheckButton",
        "NikiPriestAurasTankShieldTimerCheckbox",
        settingsFrame,
        "UICheckButtonTemplate"
    )
    enabledCheckbox:SetWidth(22)
    enabledCheckbox:SetHeight(22)
    enabledCheckbox:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", 25, -365)

    local enabledLabel = enabledCheckbox:CreateFontString(
        nil,
        "OVERLAY",
        "GameFontNormalSmall"
    )
    enabledLabel:SetPoint("LEFT", enabledCheckbox, "RIGHT", 1, 0)
    enabledLabel:SetText(timerLabel)
    enabledLabel:SetTextColor(0.82, 0.90, 1.00)

    local sizeSlider = CreateFrame(
        "Slider",
        "NikiPriestAurasTankShieldTimerSizeSlider",
        settingsFrame,
        "OptionsSliderTemplate"
    )
    sizeSlider:SetPoint("TOP", settingsFrame, "TOP", 0, -407)
    sizeSlider:SetWidth(235)
    sizeSlider:SetHeight(18)
    sizeSlider:SetMinMaxValues(12, 64)
    sizeSlider:SetValueStep(1)
    local sliderLow = getglobal("NikiPriestAurasTankShieldTimerSizeSliderLow")
    local sliderHigh = getglobal("NikiPriestAurasTankShieldTimerSizeSliderHigh")
    if sliderLow then sliderLow:SetText("12" .. pixelSuffix) end
    if sliderHigh then sliderHigh:SetText("64" .. pixelSuffix) end

    local dragHint = settingsFrame:CreateFontString(
        nil,
        "OVERLAY",
        "GameFontNormalSmall"
    )
    dragHint:SetPoint("TOP", settingsFrame, "TOP", 0, -447)
    dragHint:SetText(moveHint)
    dragHint:SetTextColor(1.00, 0.82, 0.20)

    local refreshingControls = false
    local function RefreshControls()
        InitializeOptions()
        refreshingControls = true
        enabledCheckbox:SetChecked(
            NikiPriestAurasDB.tankShieldTimerEnabled and 1 or nil
        )
        sizeSlider:SetValue(NikiPriestAurasDB.tankShieldTimerFontSize)
        local sliderText = getglobal(
            "NikiPriestAurasTankShieldTimerSizeSliderText"
        )
        if sliderText then
            sliderText:SetText(
                sizeLabel .. ": " ..
                tostring(NikiPriestAurasDB.tankShieldTimerFontSize) ..
                pixelSuffix
            )
        end
        refreshingControls = false
        ApplyTimerPosition()
        UpdateTimerDisplay(true)
    end

    enabledCheckbox:SetScript("OnClick", function()
        InitializeOptions()
        NikiPriestAurasDB.tankShieldTimerEnabled =
            this:GetChecked() and true or false
        UpdateTimerDisplay(true)
    end)

    sizeSlider:SetScript("OnValueChanged", function()
        local value = math.floor(this:GetValue() + 0.5)
        local sliderText = getglobal(
            "NikiPriestAurasTankShieldTimerSizeSliderText"
        )
        if sliderText then
            sliderText:SetText(sizeLabel .. ": " .. tostring(value) .. pixelSuffix)
        end
        if not refreshingControls then
            InitializeOptions()
            NikiPriestAurasDB.tankShieldTimerFontSize = value
            ApplyTimerStyle()
            UpdateTimerDisplay(true)
        end
    end)

    local originalOnShow = settingsFrame:GetScript("OnShow")
    settingsFrame:SetScript("OnShow", function()
        if originalOnShow then
            originalOnShow()
        end
        ApplyTimerPosition()
        timerFrame:EnableMouse(true)
        RefreshControls()
    end)

    local originalOnHide = settingsFrame:GetScript("OnHide")
    settingsFrame:SetScript("OnHide", function()
        FinishTimerDragging()
        timerFrame:EnableMouse(false)
        if originalOnHide then
            originalOnHide()
        end
        UpdateTimerDisplay(true)
    end)
end

function NikiPriestAuras_ResetTankShieldTimerPosition()
    InitializeOptions()
    NikiPriestAurasDB.tankShieldTimerX = 0
    NikiPriestAurasDB.tankShieldTimerY = 76
    ApplyTimerPosition()
end

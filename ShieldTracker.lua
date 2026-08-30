-- NikiPriestAuras: Power Word: Shield durability on the pfUI player frame.
-- Turtle WoW 1.18.1 / Vanilla 1.12 API, with optional Nampower precision.

local UPDATE_INTERVAL = 0.10
local LOW_SHIELD_THRESHOLD = 0.50
local CRITICAL_SHIELD_THRESHOLD = 0.25
local SHIELD_REMOVAL_GRACE = 0.50
local SHIELD_RECAST_TIME_JUMP = 0.75

local POWER_WORD_SHIELD_IDS = {
    [17] = true,
    [592] = true,
    [600] = true,
    [3747] = true,
    [6065] = true,
    [6066] = true,
    [10898] = true,
    [10899] = true,
    [10900] = true,
    [10901] = true,
}

local tracker = CreateFrame("Frame", "NikiPriestAurasShieldTracker", UIParent)
local scanTooltip = CreateFrame(
    "GameTooltip",
    "NikiPriestAurasShieldScanTooltip",
    UIParent,
    "GameTooltipTemplate"
)
scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
scanTooltip:Hide()

local elapsedSinceUpdate = 0
local shieldActive = false
local shieldMaximum = nil
local shieldRemaining = nil
local pfPlayerFrame = nil
local shieldText = nil
local customEventsRegistered = false
local recentAbsorbs = {}
local autoAttackEventCount = 0
local spellDamageEventCount = 0
local combatLogAbsorbCount = 0
local shieldLastTimeLeft = nil
local shieldRemovalGraceUntil = nil
local shieldAbsorbedTotal = 0
local lastDamageSource = nil
local lastDamageAmount = nil
local lastAbsorbAmount = nil

local function PrintMessage(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff80c0ffNikiPriestAuras Shield:|r " .. message)
    end
end

local function CleanNumber(text)
    if not text then
        return nil
    end

    text = string.gsub(text, "[^0-9]", "")
    if text == "" then
        return nil
    end
    return tonumber(text)
end

local function FindLargestNumber(text)
    if not text then
        return nil
    end

    local largest = nil
    local searchFrom = 1
    while searchFrom <= string.len(text) do
        local startAt, endAt, numberText = string.find(
            text,
            "(%d[%d,%.]*)",
            searchFrom
        )
        if not startAt then
            break
        end

        local value = CleanNumber(numberText)
        if value and (not largest or value > largest) then
            largest = value
        end
        searchFrom = endAt + 1
    end

    return largest
end

local function ParseCurrentTooltipAbsorb()
    local combinedText = ""
    local lineIndex
    for lineIndex = 1, 20 do
        local left = getglobal("NikiPriestAurasShieldScanTooltipTextLeft" .. lineIndex)
        local right = getglobal("NikiPriestAurasShieldScanTooltipTextRight" .. lineIndex)
        local leftText = left and left:GetText() or nil
        local rightText = right and right:GetText() or nil
        if leftText then
            combinedText = combinedText .. " " .. leftText
        end
        if rightText then
            combinedText = combinedText .. " " .. rightText
        end
    end

    local lower = string.lower(combinedText)
    local absorbAt = string.find(lower, "absorb")
    if absorbAt then
        -- Restrict the scan to the absorb sentence, then select the largest
        -- number. This rejects the 29-second aura timer while keeping the
        -- actual 356-point shield value from a wrapped Turtle tooltip.
        local absorbText = string.sub(lower, absorbAt, absorbAt + 140)
        local result = FindLargestNumber(absorbText)
        if result and result > 0 then
            return result
        end
    end

    -- Some Turtle tooltips omit the word "absorbs" but still describe the
    -- protected damage on the same wrapped line.
    for lineIndex = 2, 20 do
        local left = getglobal("NikiPriestAurasShieldScanTooltipTextLeft" .. lineIndex)
        local text = left and left:GetText() or nil
        if text then
            lower = string.lower(text)
            if string.find(lower, "damage") then
                local result = FindLargestNumber(lower)
                if result and result > 0 then
                    return result
                end
            end
        end
    end

    return nil
end

local function ParseShieldMaximum(buffIndex)
    scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    scanTooltip:SetPlayerBuff(buffIndex)
    scanTooltip:Show()
    local result = ParseCurrentTooltipAbsorb()
    scanTooltip:Hide()
    return result
end

local function GetSpellbookShieldMaximum()
    if type(GetNumSpellTabs) ~= "function" or
       type(GetSpellTabInfo) ~= "function" or
       type(GetSpellName) ~= "function" then
        return nil
    end

    local highestSlot = nil
    local tabIndex
    for tabIndex = 1, GetNumSpellTabs() do
        local _, _, firstSpell, spellCount = GetSpellTabInfo(tabIndex)
        if firstSpell and spellCount then
            local offset
            for offset = 1, spellCount do
                local spellSlot = firstSpell + offset
                local spellName = GetSpellName(spellSlot, BOOKTYPE_SPELL)
                if spellName and string.lower(spellName) == "power word: shield" then
                    highestSlot = spellSlot
                end
            end
        end
    end

    if not highestSlot then
        return nil
    end

    scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    scanTooltip:SetSpell(highestSlot, BOOKTYPE_SPELL)
    scanTooltip:Show()
    local result = ParseCurrentTooltipAbsorb()
    scanTooltip:Hide()
    return result
end

local function FindPlayerShield()
    if type(GetPlayerBuff) ~= "function" or
       type(GetPlayerBuffTexture) ~= "function" then
        return false, nil
    end

    local firstBuff = PLAYER_BUFF_START_ID or 0
    local slot
    for slot = 0, 31 do
        local buffIndex = GetPlayerBuff(firstBuff + slot, "HELPFUL")
        if not buffIndex or buffIndex < 0 then
            break
        end

        local texture = GetPlayerBuffTexture(buffIndex)
        if texture and string.find(string.lower(texture), "spell_holy_powerwordshield") then
            local auraMaximum = ParseShieldMaximum(buffIndex)
            local spellbookMaximum = GetSpellbookShieldMaximum()
            -- Turtle's active-aura tooltip can expose unrelated values such as
            -- 29/40-second timers after a shield is recast. The spellbook entry
            -- for the currently learned rank consistently carries the actual
            -- absorb amount, so it is authoritative whenever available.
            local maximum = spellbookMaximum or
                            (auraMaximum and auraMaximum > 30 and auraMaximum)
            local timeLeft = nil
            if type(GetPlayerBuffTimeLeft) == "function" then
                timeLeft = GetPlayerBuffTimeLeft(buffIndex)
            end
            return true, maximum, timeLeft
        end
    end

    return false, nil, nil
end

local function EnsurePfUIOverlay()
    if pfPlayerFrame and shieldText then
        return true
    end

    if not pfUI or not pfUI.uf or not pfUI.uf.player then
        return false
    end

    local frame = pfUI.uf.player
    if not frame.hp or not frame.hp.bar or not frame.texts then
        return false
    end

    pfPlayerFrame = frame
    shieldText = frame.texts:CreateFontString(
        "NikiPriestAurasPfUIShieldText",
        "OVERLAY",
        "GameFontNormalSmall"
    )
    shieldText:ClearAllPoints()
    shieldText:SetPoint("TOPLEFT", frame.hp.bar, "TOPLEFT", 1, 1)
    shieldText:SetPoint("BOTTOMRIGHT", frame.hp.bar, "BOTTOMRIGHT", -1, -1)
    shieldText:SetJustifyH("CENTER")
    shieldText:SetJustifyV("MIDDLE")

    if frame.hpCenterText and frame.hpCenterText.GetFont then
        local font, size, flags = frame.hpCenterText:GetFont()
        if font and size then
            shieldText:SetFont(font, size, flags)
        end
    end

    shieldText:Hide()
    return true
end

local function HidePfUIHealthText()
    if not pfPlayerFrame then
        return
    end
    if pfPlayerFrame.hpLeftText then pfPlayerFrame.hpLeftText:Hide() end
    if pfPlayerFrame.hpCenterText then pfPlayerFrame.hpCenterText:Hide() end
    if pfPlayerFrame.hpRightText then pfPlayerFrame.hpRightText:Hide() end
end

local function RestorePfUIHealthText()
    if not pfPlayerFrame then
        return
    end
    if pfPlayerFrame.hpLeftText then pfPlayerFrame.hpLeftText:Show() end
    if pfPlayerFrame.hpCenterText then pfPlayerFrame.hpCenterText:Show() end
    if pfPlayerFrame.hpRightText then pfPlayerFrame.hpRightText:Show() end
end

local function UpdatePfUIShieldText()
    if not EnsurePfUIOverlay() then
        return
    end

    if not shieldActive then
        shieldText:Hide()
        RestorePfUIHealthText()
        return
    end

    HidePfUIHealthText()

    if shieldMaximum and shieldMaximum > 0 then
        local remaining = shieldRemaining or shieldMaximum
        remaining = math.max(0, math.min(shieldMaximum, remaining))
        local ratio = remaining / shieldMaximum

        shieldText:SetText(tostring(math.floor(remaining + 0.5)) .. " / " ..
                           tostring(math.floor(shieldMaximum + 0.5)))
        if ratio <= CRITICAL_SHIELD_THRESHOLD then
            shieldText:SetTextColor(1.00, 0.18, 0.12, 1)
        elseif ratio <= LOW_SHIELD_THRESHOLD then
            shieldText:SetTextColor(1.00, 0.82, 0.12, 1)
        else
            shieldText:SetTextColor(0.78, 0.90, 1.00, 1)
        end
    else
        -- This is used only if a localized client tooltip cannot expose the
        -- absorb value. Health text is still replaced while the shield lives.
        shieldText:SetText("SHIELD")
        shieldText:SetTextColor(0.78, 0.90, 1.00, 1)
    end

    shieldText:Show()
end

local function ResetShieldDurability(parsedMaximum, timeLeft)
    shieldActive = true
    shieldMaximum = parsedMaximum or shieldMaximum
    shieldRemaining = shieldMaximum
    shieldLastTimeLeft = timeLeft
    shieldRemovalGraceUntil = nil
    shieldAbsorbedTotal = 0
    lastDamageSource = nil
    lastDamageAmount = nil
    lastAbsorbAmount = nil
    recentAbsorbs = {}
end

local function RefreshShieldState(forceReset)
    local hasShield, parsedMaximum, timeLeft = FindPlayerShield()

    if hasShield then
        if not shieldActive then
            ResetShieldDurability(parsedMaximum, timeLeft)
        elseif forceReset or
               (timeLeft and shieldLastTimeLeft and
                timeLeft > shieldLastTimeLeft + SHIELD_RECAST_TIME_JUMP) then
            -- Recasting PW:S modifies the existing aura instead of briefly
            -- removing it. Treat the duration jump as a fresh full shield.
            ResetShieldDurability(parsedMaximum, timeLeft)
        elseif (not shieldMaximum or shieldMaximum <= 0) and
               parsedMaximum and parsedMaximum > 0 then
            shieldMaximum = parsedMaximum
            shieldRemaining = parsedMaximum
        end
        shieldLastTimeLeft = timeLeft or shieldLastTimeLeft
    elseif shieldActive then
        shieldActive = false
        shieldLastTimeLeft = nil
        -- Nampower's final damage event and PLAYER_AURAS_CHANGED can arrive in
        -- either order when an attack breaks the shield. Keep the numerical
        -- state briefly so the last absorbed part is not discarded.
        shieldRemovalGraceUntil = GetTime() + SHIELD_REMOVAL_GRACE
    end

    UpdatePfUIShieldText()
end

local function IsDuplicateAbsorb(amount, source)
    local now = GetTime()
    local index

    for index = table.getn(recentAbsorbs), 1, -1 do
        local entry = recentAbsorbs[index]
        if now - entry.time > 0.35 then
            table.remove(recentAbsorbs, index)
        elseif entry.amount == amount and entry.source ~= source then
            return true
        end
    end

    table.insert(recentAbsorbs, {
        amount = amount,
        source = source,
        time = now,
    })
    return false
end

local function ApplyAbsorbedDamage(amount, source, damage)
    amount = tonumber(amount)
    local graceActive = shieldRemovalGraceUntil and
                        GetTime() <= shieldRemovalGraceUntil
    if (not shieldActive and not graceActive) or
       not shieldRemaining or not amount or amount <= 0 then
        return
    end
    source = source or "unknown"
    if IsDuplicateAbsorb(amount, source) then
        return
    end

    shieldRemaining = math.max(0, shieldRemaining - amount)
    shieldAbsorbedTotal = shieldAbsorbedTotal + amount
    lastDamageSource = source
    lastDamageAmount = tonumber(damage)
    lastAbsorbAmount = amount
    if shieldActive then
        UpdatePfUIShieldText()
    end
end

local function IsPowerWordShieldSpell(spellId)
    spellId = tonumber(spellId)
    return spellId and POWER_WORD_SHIELD_IDS[spellId]
end

local function GetPlayerGuid()
    if type(GetUnitGUID) == "function" then
        return GetUnitGUID("player")
    elseif type(UnitGUID) == "function" then
        return UnitGUID("player")
    end
    return nil
end

local function TargetIsPlayer(targetGuid)
    local playerGuid = GetPlayerGuid()
    return playerGuid and targetGuid and playerGuid == targetGuid
end

local function ParseMitigationAbsorb(mitigation)
    if type(mitigation) ~= "string" then
        return nil
    end
    local _, _, amount = string.find(mitigation, "^%s*(%-?%d+)")
    return amount and tonumber(amount) or nil
end

local function ParseCombatLogAbsorb(message)
    if type(message) ~= "string" then
        return nil
    end
    local _, _, amount = string.find(string.lower(message), "([%d,]+)%s+absorbed")
    return CleanNumber(amount)
end

local function RegisterOptionalEvent(name)
    local ok = pcall(tracker.RegisterEvent, tracker, name)
    if ok then
        customEventsRegistered = true
    end
end

local function EnableNampowerShieldEvents()
    if type(GetNampowerVersion) ~= "function" or
       type(SetCVar) ~= "function" then
        return
    end

    -- Older Nampower releases expose these events only while their CVars are
    -- enabled. Newer releases enable them on registration, so setting both is
    -- harmless and keeps the tracker compatible with either implementation.
    pcall(SetCVar, "NP_EnableAutoAttackEvents", "1")
    pcall(SetCVar, "NP_EnableSpellDamageEvents", "1")
end

tracker:RegisterEvent("PLAYER_ENTERING_WORLD")
tracker:RegisterEvent("PLAYER_AURAS_CHANGED")
tracker:RegisterEvent("UNIT_AURA")
tracker:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS")
tracker:RegisterEvent("CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS")
tracker:RegisterEvent("CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE")
tracker:RegisterEvent("CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE")
tracker:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE")

EnableNampowerShieldEvents()
RegisterOptionalEvent("AUTO_ATTACK_OTHER")
RegisterOptionalEvent("SPELL_DAMAGE_EVENT_OTHER")
RegisterOptionalEvent("ENVIRONMENTAL_DMG_SELF")
RegisterOptionalEvent("BUFF_ADDED_SELF")
RegisterOptionalEvent("BUFF_UPDATE_DURATION_SELF")

tracker:SetScript("OnEvent", function()
    if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_AURAS_CHANGED" then
        RefreshShieldState()
    elseif event == "UNIT_AURA" then
        if not arg1 or arg1 == "player" then
            RefreshShieldState()
        end
    elseif event == "AUTO_ATTACK_OTHER" then
        autoAttackEventCount = autoAttackEventCount + 1
        local targetGuid = arg2
        local totalDamage = arg3
        local totalAbsorb = arg8
        if TargetIsPlayer(targetGuid) then
            ApplyAbsorbedDamage(totalAbsorb, "auto", totalDamage)
        end
    elseif event == "SPELL_DAMAGE_EVENT_OTHER" then
        spellDamageEventCount = spellDamageEventCount + 1
        local targetGuid = arg1
        local damage = arg4
        local mitigation = arg5
        if TargetIsPlayer(targetGuid) then
            ApplyAbsorbedDamage(ParseMitigationAbsorb(mitigation), "spell", damage)
        end
    elseif event == "ENVIRONMENTAL_DMG_SELF" then
        local targetGuid = arg1
        local damage = arg3
        local absorb = arg4
        if not targetGuid or TargetIsPlayer(targetGuid) then
            ApplyAbsorbedDamage(absorb, "environment", damage)
        end
    elseif event == "BUFF_ADDED_SELF" then
        if IsPowerWordShieldSpell(arg3) then
            RefreshShieldState(true)
        end
    elseif event == "BUFF_UPDATE_DURATION_SELF" then
        if IsPowerWordShieldSpell(arg4) then
            RefreshShieldState(true)
        end
    else
        local absorbed = ParseCombatLogAbsorb(arg1)
        if absorbed and absorbed > 0 then
            combatLogAbsorbCount = combatLogAbsorbCount + 1
            ApplyAbsorbedDamage(absorbed, "combat log", nil)
        end
    end
end)

tracker:SetScript("OnUpdate", function()
    elapsedSinceUpdate = elapsedSinceUpdate + arg1
    if elapsedSinceUpdate < UPDATE_INTERVAL then
        return
    end
    elapsedSinceUpdate = 0

    -- Polling keeps the overlay above pfUI's own frequent health-text refresh
    -- and also covers Turtle builds that delay PLAYER_AURAS_CHANGED.
    RefreshShieldState()

    if shieldRemovalGraceUntil and GetTime() > shieldRemovalGraceUntil then
        shieldRemovalGraceUntil = nil
        shieldMaximum = nil
        shieldRemaining = nil
        shieldAbsorbedTotal = 0
        recentAbsorbs = {}
    end
end)

SLASH_NIKIPRIESTAURASSHIELD1 = "/npashield"
SlashCmdList["NIKIPRIESTAURASSHIELD"] = function(message)
    local command = string.lower(message or "")
    command = string.gsub(command, "^%s+", "")
    command = string.gsub(command, "%s+$", "")

    if command == "tooltip" then
        local hasShield, parsedMaximum = FindPlayerShield()
        PrintMessage("tooltip scan: active=" .. tostring(hasShield) ..
                     ", parsed maximum=" .. tostring(parsedMaximum) ..
                     ", spellbook fallback=" .. tostring(GetSpellbookShieldMaximum()))
        return
    end

    local maximumText = shieldMaximum and tostring(math.floor(shieldMaximum + 0.5)) or "unknown"
    local remainingText = shieldRemaining and tostring(math.floor(shieldRemaining + 0.5)) or "unknown"
    local pfuiText = EnsurePfUIOverlay() and "yes" or "no"
    local eventText = customEventsRegistered and "yes" or "no"
    local lastEventText = "none"
    if lastDamageSource then
        lastEventText = lastDamageSource ..
                        " damage=" .. tostring(lastDamageAmount or 0) ..
                        " absorb=" .. tostring(lastAbsorbAmount or 0)
    end
    PrintMessage("active=" .. tostring(shieldActive) ..
                 ", remaining=" .. remainingText ..
                 ", maximum=" .. maximumText ..
                 ", absorbed=" .. tostring(math.floor(shieldAbsorbedTotal + 0.5)) ..
                 ", pfUI=" .. pfuiText ..
                 ", Nampower events=" .. eventText ..
                 ", auto=" .. tostring(autoAttackEventCount) ..
                 ", spell=" .. tostring(spellDamageEventCount) ..
                 ", log=" .. tostring(combatLogAbsorbCount) ..
                 ", last=" .. lastEventText)
end

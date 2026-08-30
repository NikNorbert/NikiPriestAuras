-- NikiPriestAuras
-- Turtle WoW 1.18.1 / Vanilla 1.12 API

local MAGIC_DISPEL_TYPE = 1
local UPDATE_INTERVAL = 0.20
local PROC_UPDATE_INTERVAL = 0.05
local ICON_SIZE = 68
local ICON_GAP = 6
local SEARING_LIGHT_SPELL_ID = 51465
local PROC_ALERT_WIDTH = 460
local PROC_ALERT_HEIGHT = 230
local PROC_SCREEN_GLOW_SIZE = 105
local PROC_SCREEN_GLOW_DELAY = 0.18
local PROC_SCREEN_GLOW_FADE_IN = 0.16
local PROC_SYMBOL_EXPLOSION_DURATION = 0.25
local PROC_SYMBOL_EXPLOSION_GROWTH = 1.50
local PROC_SCREEN_GLOW_LINGER_DURATION = 0.50
local ENLIGHTENED_AURA_WIDTH = 340
local ENLIGHTENED_AURA_HEIGHT = 340
local ENLIGHTENED_DEFAULT_DURATION = 8.0
local ENLIGHTENED_MIN_PULSES_PER_SECOND = 0.50
local ENLIGHTENED_MAX_PULSES_PER_SECOND = 2.80
local ENLIGHTENED_ROTATION_RADIANS_PER_SECOND = 6.283185 / 48
local INCOMING_ATTACK_TIMEOUT = 6.0
local SHIELD_WARNING_TIME = 5.0
local WEAKENED_SOUL_BLINK_INTERVAL = 0.25

-- The settings UI follows the game client locale. Russian is used only by
-- ruRU clients; English is the safe fallback for every other locale.
local locale = GetLocale and GetLocale() or "enUS"
local L = {
    configure = "Unlock and configure:",
    icons = "Icons",
    aura = "Aura",
    proc = "Searing Light",
    shieldWhileAttacked = "Shield while attacked",
    shieldFrame = "Shield numbers on player frame:",
    shieldFramePfUI = "pfUI",
    shieldFrameBlizzard = "Blizzard (original)",
    enlightenedAuraEnabled = "Show Enlightened aura",
    originalIcons = "Original spell icons",
    size = "Size",
    opacity = "Opacity",
    iconSpacing = "Icon spacing",
    animationSpeed = "Animation speed",
    pixels = " px",
    dragHint = "Drag the selected element with the left mouse button",
    lock = "Lock",
    selectedIcons = "Selected: icons",
    selectedAura = "Selected: Enlightened aura",
    selectedProc = "Selected: Searing Light",
    dragToMove = "NikiPriestAuras - drag to move",
    procDrag = "Searing Light - drag | wheel: size ",
    procAlpha = "% | Shift+wheel: opacity ",
    addonShown = "Addon reminders enabled.",
    addonHidden = "Addon reminders hidden.",
    commands = "Commands: /npa, /npa show, /npa hide, /npa set, /npa reset, /npa test"
}

if locale == "ruRU" then
    L.configure = "Разблокировать и настроить:"
    L.icons = "Иконки"
    L.aura = "Аура"
    L.proc = "Searing Light"
    L.shieldWhileAttacked = "Щит при атаке"
    L.shieldFrame = "Цифры щита на фрейме игрока:"
    L.shieldFramePfUI = "pfUI"
    L.shieldFrameBlizzard = "Blizzard (ориг.)"
    L.enlightenedAuraEnabled = "Показывать ауру Enlightened"
    L.originalIcons = "Оригинальные иконки"
    L.size = "Размер"
    L.opacity = "Прозрачность"
    L.iconSpacing = "Расстояние между иконками"
    L.animationSpeed = "Скорость анимации"
    L.pixels = " пкс"
    L.dragHint = "Перетащите выбранный элемент левой кнопкой мыши"
    L.lock = "Заблокировать"
    L.selectedIcons = "Выбрано: иконки"
    L.selectedAura = "Выбрано: аура Enlightened"
    L.selectedProc = "Выбрано: Searing Light"
    L.dragToMove = "NikiPriestAuras - перетащите для перемещения"
    L.procDrag = "Searing Light - перетаскивание | колесо: размер "
    L.procAlpha = "% | Shift+колесо: прозрачность "
    L.addonShown = "Оповещения аддона включены."
    L.addonHidden = "Оповещения аддона скрыты."
    L.commands = "Команды: /npa, /npa show, /npa hide, /npa set, /npa reset, /npa test"
end

local magicDispelCache = {}
local inCombat = false
local updateElapsed = 0
local procUpdateElapsed = 0
local placementMode = false
local procPlacementMode = false
local settingsMode = false
local settingsSelection = "icons"
local iconDragging = false
local procDragging = false
local auraDragging = false
local procPulseElapsed = 0
local procScreenGlowElapsed = 0
local procAlertActive = false
local procExplosionElapsed = nil
local procGlowLingerElapsed = nil
local procExplosionStartAlpha = 0
local procGlowLingerStartAlpha = 0
local animationLastUpdateTime = nil
local enlightenedAuraElapsed = 0
local enlightenedAuraRotation = 0
local enlightenedAuraEntryElapsed = 0
local enlightenedAuraTimeLeft = nil
local enlightenedAuraDuration = ENLIGHTENED_DEFAULT_DURATION
local procTestUntil = nil
local enlightenedTestUntil = nil
local lastIncomingCreatureAttack = nil
local shieldBlinking = false
local wasOnTaxi = false
local enlightenKnown = false
local enlightenSpellTexture = nil
local dispelMagicSpellTexture = nil
local cureDiseaseSpellTexture = nil
local fortitudeSpellTexture = nil
local innerFireSpellTexture = nil
local divineSpiritKnown = false
local divineSpiritSpellTexture = nil
local powerWordShieldKnown = false
local powerWordShieldSpellTexture = nil

local anchor = CreateFrame("Frame", "NikiPriestAurasFrame", UIParent)
anchor:SetWidth(ICON_SIZE)
anchor:SetHeight(ICON_SIZE)
anchor:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
anchor:SetFrameStrata("HIGH")
anchor:SetMovable(true)
anchor:SetClampedToScreen(true)
anchor:RegisterForDrag("LeftButton")

-- Turtle custom procs are most reliable through the original Vanilla player
-- buff API. The hidden tooltip lets us distinguish Enlightened from another
-- aura that might reuse the Power Infusion icon.
local enlightenedScanTooltip = CreateFrame(
    "GameTooltip",
    "NikiPriestAurasEnlightenedScanTooltip",
    UIParent,
    "GameTooltipTemplate"
)
enlightenedScanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
enlightenedScanTooltip:Hide()

local function CreateReminderIcon(name, texturePath, borderR, borderG, borderB, title, description)
    local frame = CreateFrame("Frame", name, anchor)
    frame:SetWidth(ICON_SIZE)
    frame:SetHeight(ICON_SIZE)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 13,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    frame:SetBackdropColor(0, 0, 0, 0.90)
    frame:SetBackdropBorderColor(borderR, borderG, borderB, 1)
    frame:EnableMouse(false)
    frame:RegisterForDrag("LeftButton")

    local texture = frame:CreateTexture(nil, "ARTWORK")
    texture:SetTexture(texturePath)
    texture:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -5)
    texture:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -5, 5)
    frame.icon = texture

    local glow = frame:CreateTexture(nil, "OVERLAY")
    glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(borderR, borderG, borderB, 0.80)
    glow:SetPoint("CENTER", frame, "CENTER", 0, 0)
    glow:SetWidth(ICON_SIZE * 1.55)
    glow:SetHeight(ICON_SIZE * 1.55)
    frame.glow = glow

    frame:SetScript("OnEnter", function()
        GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, 1, 1, 1)
        GameTooltip:AddLine(description, borderR, borderG, borderB, true)
        if placementMode or settingsMode then
            GameTooltip:AddLine("Hold the left mouse button and drag to move.", 1, 0.82, 0, true)
        end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    frame:Hide()
    return frame
end

local dispelIcon = CreateReminderIcon(
    "NikiPriestAurasDispelIcon",
    "Interface\\AddOns\\NikiPriestAuras\\Textures\\DispelMagicReminder_256",
    0.20, 0.60, 1.00,
    "Dispel Magic",
    "The player or current target has a Magic effect that a priest can dispel."
)

local diseaseIcon = CreateReminderIcon(
    "NikiPriestAurasDiseaseIcon",
    "Interface\\AddOns\\NikiPriestAuras\\Textures\\CureDiseaseReminder_256",
    0.65, 0.45, 0.15,
    "Cure Disease",
    "The player or friendly target has a Disease debuff."
)

local shieldIcon = CreateReminderIcon(
    "NikiPriestAurasPowerWordShieldIcon",
    "Interface\\AddOns\\NikiPriestAuras\\Textures\\PowerWordShieldReminder_256",
    0.72, 0.86, 1.00,
    "Power Word: Shield",
    "A creature is attacking the player and Power Word: Shield is missing or has no more than 5 seconds remaining. A smooth fast pulse means Weakened Soul is still active."
)

local fortitudeIcon = CreateReminderIcon(
    "NikiPriestAurasFortitudeIcon",
    "Interface\\AddOns\\NikiPriestAuras\\Textures\\FortitudeReminder_256",
    1.00, 0.82, 0.20,
    "Power Word: Fortitude",
    "Power Word: Fortitude is missing from the player."
)

local divineSpiritIcon = CreateReminderIcon(
    "NikiPriestAurasDivineSpiritIcon",
    "Interface\\AddOns\\NikiPriestAuras\\Textures\\DivineSpiritReminder_256",
    0.72, 0.86, 1.00,
    "Divine Spirit",
    "Divine Spirit is missing from the player. This reminder is active only while the spell is learned."
)

local innerFireIcon = CreateReminderIcon(
    "NikiPriestAurasInnerFireIcon",
    "Interface\\AddOns\\NikiPriestAuras\\Textures\\InnerFireReminder_256",
    1.00, 0.42, 0.12,
    "Inner Fire",
    "Inner Fire is missing from the player."
)

-- The custom Inner Fire artwork is authored on black for Vanilla's additive
-- texture blending. Keep it frameless so only the cold holy flame is visible
-- instead of the generic square icon backdrop and action-button glow.
innerFireIcon:SetBackdrop(nil)
innerFireIcon.icon:ClearAllPoints()
innerFireIcon.icon:SetAllPoints(innerFireIcon)
innerFireIcon.icon:SetBlendMode("ADD")
innerFireIcon.glow:Hide()

local enlightenIcon = CreateReminderIcon(
    "NikiPriestAurasEnlightenIcon",
    "Interface\\AddOns\\NikiPriestAuras\\Textures\\EnlightenReminder_256",
    0.72, 0.82, 1.00,
    "Enlighten",
    "Enlighten is missing from the player. This reminder is active only while the talent spell is learned."
)

-- The reminder artwork is designed as a shared frameless set. Stretch every
-- silhouette over the full reminder slot and remove the generic square
-- backdrop/action-button glow so only the spell-shaped artwork is visible.
local function UseFramelessReminderArtwork(frame)
    frame:SetBackdrop(nil)
    frame.icon:ClearAllPoints()
    frame.icon:SetAllPoints(frame)
    frame.glow:Hide()
end

UseFramelessReminderArtwork(dispelIcon)
UseFramelessReminderArtwork(diseaseIcon)
UseFramelessReminderArtwork(shieldIcon)
UseFramelessReminderArtwork(fortitudeIcon)
UseFramelessReminderArtwork(divineSpiritIcon)
UseFramelessReminderArtwork(enlightenIcon)

local reminderIcons = { shieldIcon, dispelIcon, diseaseIcon, fortitudeIcon, divineSpiritIcon, innerFireIcon, enlightenIcon }

local function ApplyReminderTextureStyle()
    local useOriginal = type(NikiPriestAurasDB) == "table" and
                        NikiPriestAurasDB.originalReminderTextures

    if useOriginal then
        shieldIcon.icon:SetTexture(
            powerWordShieldSpellTexture or
            "Interface\\Icons\\Spell_Holy_PowerWordShield"
        )
        dispelIcon.icon:SetTexture(
            dispelMagicSpellTexture or
            "Interface\\Icons\\Spell_Holy_DispelMagic"
        )
        diseaseIcon.icon:SetTexture(
            cureDiseaseSpellTexture or
            "Interface\\Icons\\Spell_Holy_NullifyDisease"
        )
        fortitudeIcon.icon:SetTexture(
            fortitudeSpellTexture or
            "Interface\\Icons\\Spell_Holy_WordFortitude"
        )
        divineSpiritIcon.icon:SetTexture(
            divineSpiritSpellTexture or
            "Interface\\Icons\\Spell_Holy_DivineSpirit"
        )
        innerFireIcon.icon:SetTexture(
            innerFireSpellTexture or
            "Interface\\Icons\\Spell_Holy_InnerFire"
        )
        enlightenIcon.icon:SetTexture(
            enlightenSpellTexture or
            "Interface\\Icons\\BTNHolyScriptures"
        )
        innerFireIcon.icon:SetBlendMode("BLEND")
    else
        shieldIcon.icon:SetTexture("Interface\\AddOns\\NikiPriestAuras\\Textures\\PowerWordShieldReminder_256")
        dispelIcon.icon:SetTexture("Interface\\AddOns\\NikiPriestAuras\\Textures\\DispelMagicReminder_256")
        diseaseIcon.icon:SetTexture("Interface\\AddOns\\NikiPriestAuras\\Textures\\CureDiseaseReminder_256")
        fortitudeIcon.icon:SetTexture("Interface\\AddOns\\NikiPriestAuras\\Textures\\FortitudeReminder_256")
        divineSpiritIcon.icon:SetTexture("Interface\\AddOns\\NikiPriestAuras\\Textures\\DivineSpiritReminder_256")
        innerFireIcon.icon:SetTexture("Interface\\AddOns\\NikiPriestAuras\\Textures\\InnerFireReminder_256")
        enlightenIcon.icon:SetTexture("Interface\\AddOns\\NikiPriestAuras\\Textures\\EnlightenReminder_256")
        innerFireIcon.icon:SetBlendMode("ADD")
    end
end

-- Separate Wrath-style spell activation overlay. It is intentionally not part
-- of the reminder icon row, so a proc never moves the dispel/buff reminders.
local procFrame = CreateFrame("Frame", "NikiPriestAurasSearingLightProc", UIParent)
procFrame:SetWidth(PROC_ALERT_WIDTH)
procFrame:SetHeight(PROC_ALERT_HEIGHT)
procFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 155)
procFrame:SetFrameStrata("HIGH")
procFrame:SetFrameLevel(20)
procFrame:SetMovable(true)
procFrame:SetClampedToScreen(true)
procFrame:RegisterForDrag("LeftButton")
procFrame:EnableMouse(false)
procFrame:EnableMouseWheel(false)

-- A click-through golden vignette around the whole screen makes the short
-- Searing Light proc more noticeable without covering the center of the view.
-- The four gradients are kept on a separate frame so moving or scaling the
-- proc artwork never changes the screen-edge effect.
local procScreenGlowFrame = CreateFrame("Frame", "NikiPriestAurasSearingLightScreenGlow", UIParent)
procScreenGlowFrame:SetAllPoints(UIParent)
procScreenGlowFrame:SetFrameStrata("HIGH")
procScreenGlowFrame:SetFrameLevel(10)
procScreenGlowFrame:EnableMouse(false)

local procScreenGlowTop = procScreenGlowFrame:CreateTexture(nil, "OVERLAY")
procScreenGlowTop:SetTexture(1, 1, 1, 1)
procScreenGlowTop:SetBlendMode("ADD")
procScreenGlowTop:SetPoint("TOPLEFT", procScreenGlowFrame, "TOPLEFT", 0, 0)
procScreenGlowTop:SetPoint("TOPRIGHT", procScreenGlowFrame, "TOPRIGHT", 0, 0)
procScreenGlowTop:SetHeight(PROC_SCREEN_GLOW_SIZE)
procScreenGlowTop:SetGradientAlpha("VERTICAL", 1.00, 0.48, 0.05, 0.00, 1.00, 0.72, 0.16, 0.95)

local procScreenGlowBottom = procScreenGlowFrame:CreateTexture(nil, "OVERLAY")
procScreenGlowBottom:SetTexture(1, 1, 1, 1)
procScreenGlowBottom:SetBlendMode("ADD")
procScreenGlowBottom:SetPoint("BOTTOMLEFT", procScreenGlowFrame, "BOTTOMLEFT", 0, 0)
procScreenGlowBottom:SetPoint("BOTTOMRIGHT", procScreenGlowFrame, "BOTTOMRIGHT", 0, 0)
procScreenGlowBottom:SetHeight(PROC_SCREEN_GLOW_SIZE)
procScreenGlowBottom:SetGradientAlpha("VERTICAL", 1.00, 0.72, 0.16, 0.95, 1.00, 0.48, 0.05, 0.00)

local procScreenGlowLeft = procScreenGlowFrame:CreateTexture(nil, "OVERLAY")
procScreenGlowLeft:SetTexture(1, 1, 1, 1)
procScreenGlowLeft:SetBlendMode("ADD")
procScreenGlowLeft:SetPoint("TOPLEFT", procScreenGlowFrame, "TOPLEFT", 0, 0)
procScreenGlowLeft:SetPoint("BOTTOMLEFT", procScreenGlowFrame, "BOTTOMLEFT", 0, 0)
procScreenGlowLeft:SetWidth(PROC_SCREEN_GLOW_SIZE)
procScreenGlowLeft:SetGradientAlpha("HORIZONTAL", 1.00, 0.72, 0.16, 0.95, 1.00, 0.48, 0.05, 0.00)

local procScreenGlowRight = procScreenGlowFrame:CreateTexture(nil, "OVERLAY")
procScreenGlowRight:SetTexture(1, 1, 1, 1)
procScreenGlowRight:SetBlendMode("ADD")
procScreenGlowRight:SetPoint("TOPRIGHT", procScreenGlowFrame, "TOPRIGHT", 0, 0)
procScreenGlowRight:SetPoint("BOTTOMRIGHT", procScreenGlowFrame, "BOTTOMRIGHT", 0, 0)
procScreenGlowRight:SetWidth(PROC_SCREEN_GLOW_SIZE)
procScreenGlowRight:SetGradientAlpha("HORIZONTAL", 1.00, 0.48, 0.05, 0.00, 1.00, 0.72, 0.16, 0.95)

procScreenGlowFrame:SetAlpha(0)
procScreenGlowFrame:Hide()

-- A click-through living aura for the short Enlightened buff. Several
-- phase-shifted copies pulse and rotate without obscuring the character.
local enlightenedAuraFrame = CreateFrame("Frame", "NikiPriestAurasEnlightenedAura", UIParent)
enlightenedAuraFrame:SetWidth(ENLIGHTENED_AURA_WIDTH)
enlightenedAuraFrame:SetHeight(ENLIGHTENED_AURA_HEIGHT)
enlightenedAuraFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
enlightenedAuraFrame:SetFrameStrata("HIGH")
enlightenedAuraFrame:SetFrameLevel(8)
enlightenedAuraFrame:SetMovable(true)
enlightenedAuraFrame:SetClampedToScreen(true)
enlightenedAuraFrame:RegisterForDrag("LeftButton")
enlightenedAuraFrame:EnableMouse(false)

local ENLIGHTENED_WISPS_TEXTURE =
    "Interface\\AddOns\\NikiPriestAuras\\Textures\\EnlightenedAuraRays_512"

local enlightenedAuraTextureOuter = enlightenedAuraFrame:CreateTexture(nil, "ARTWORK")
enlightenedAuraTextureOuter:SetTexture(ENLIGHTENED_WISPS_TEXTURE)
enlightenedAuraTextureOuter:SetBlendMode("ADD")
enlightenedAuraTextureOuter:SetVertexColor(0.82, 0.88, 1.00, 1)
enlightenedAuraTextureOuter:SetPoint("CENTER", enlightenedAuraFrame, "CENTER", 0, 0)
enlightenedAuraTextureOuter:SetWidth(ENLIGHTENED_AURA_WIDTH * 1.08)
enlightenedAuraTextureOuter:SetHeight(ENLIGHTENED_AURA_HEIGHT * 1.08)

local enlightenedAuraTextureFlow = enlightenedAuraFrame:CreateTexture(nil, "ARTWORK")
enlightenedAuraTextureFlow:SetTexture(ENLIGHTENED_WISPS_TEXTURE)
enlightenedAuraTextureFlow:SetBlendMode("ADD")
enlightenedAuraTextureFlow:SetVertexColor(1.00, 0.91, 0.68, 1)
enlightenedAuraTextureFlow:SetPoint("CENTER", enlightenedAuraFrame, "CENTER", 0, 0)
enlightenedAuraTextureFlow:SetWidth(ENLIGHTENED_AURA_WIDTH * 1.02)
enlightenedAuraTextureFlow:SetHeight(ENLIGHTENED_AURA_HEIGHT * 1.02)

local enlightenedAuraTextureMain = enlightenedAuraFrame:CreateTexture(nil, "OVERLAY")
enlightenedAuraTextureMain:SetTexture(ENLIGHTENED_WISPS_TEXTURE)
enlightenedAuraTextureMain:SetBlendMode("ADD")
enlightenedAuraTextureMain:SetVertexColor(1.00, 0.98, 0.90, 1)
enlightenedAuraTextureMain:SetPoint("CENTER", enlightenedAuraFrame, "CENTER", 0, 0)
enlightenedAuraTextureMain:SetWidth(ENLIGHTENED_AURA_WIDTH)
enlightenedAuraTextureMain:SetHeight(ENLIGHTENED_AURA_HEIGHT)

enlightenedAuraFrame:SetAlpha(0)
enlightenedAuraFrame:Hide()

local procHalo = procFrame:CreateTexture(nil, "ARTWORK")
procHalo:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
procHalo:SetBlendMode("ADD")
procHalo:SetVertexColor(1.00, 0.72, 0.12, 0.55)
procHalo:SetPoint("CENTER", procFrame, "CENTER", 0, 0)
procHalo:SetWidth(185)
procHalo:SetHeight(185)
-- The selected proc artwork already contains its own soft glow. The Vanilla
-- action-button border has a faint square background when enlarged, so keep
-- this legacy helper hidden to avoid a visible rectangle behind the alert.
procHalo:Hide()

-- Three silhouette copies travel from the center outwards in staggered
-- phases. Vanilla has no shader masks, but scaling the same alpha artwork
-- produces a clean wave that follows the proc's shape without a rectangle.
local procWaveTextures = {}
local procWaveIndex
for procWaveIndex = 1, 3 do
    local procWave = procFrame:CreateTexture(nil, "ARTWORK")
    procWave:SetTexture("Interface\\AddOns\\NikiPriestAuras\\Textures\\SearingLightProc_256")
    procWave:SetBlendMode("ADD")
    procWave:SetVertexColor(0.82, 0.90, 1.00, 1)
    procWave:SetPoint("CENTER", procFrame, "CENTER", 0, 0)
    procWave:SetWidth(PROC_ALERT_WIDTH * 0.90)
    procWave:SetHeight(PROC_ALERT_HEIGHT * 0.90)
    procWave:SetAlpha(0)
    procWaveTextures[procWaveIndex] = procWave
end

-- Two low-alpha copies of the selected artwork create a living glow that
-- follows its real alpha silhouette. Unlike UI-ActionButton-Border, these
-- layers cannot reveal a square background around the proc.
local procGlowOuter = procFrame:CreateTexture(nil, "ARTWORK")
procGlowOuter:SetTexture("Interface\\AddOns\\NikiPriestAuras\\Textures\\SearingLightProc_256")
procGlowOuter:SetBlendMode("ADD")
procGlowOuter:SetVertexColor(0.72, 0.84, 1.00, 1)
procGlowOuter:SetPoint("CENTER", procFrame, "CENTER", 0, 0)
procGlowOuter:SetWidth(PROC_ALERT_WIDTH * 1.10)
procGlowOuter:SetHeight(PROC_ALERT_HEIGHT * 1.10)
procGlowOuter:SetAlpha(0.12)

local procGlowInner = procFrame:CreateTexture(nil, "ARTWORK")
procGlowInner:SetTexture("Interface\\AddOns\\NikiPriestAuras\\Textures\\SearingLightProc_256")
procGlowInner:SetBlendMode("ADD")
procGlowInner:SetVertexColor(0.94, 0.97, 1.00, 1)
procGlowInner:SetPoint("CENTER", procFrame, "CENTER", 0, 0)
procGlowInner:SetWidth(PROC_ALERT_WIDTH * 1.04)
procGlowInner:SetHeight(PROC_ALERT_HEIGHT * 1.04)
procGlowInner:SetAlpha(0.20)

local procTexture = procFrame:CreateTexture(nil, "OVERLAY")
-- The extension is intentionally omitted: Vanilla's texture loader appends
-- it itself and handles addon textures more reliably this way.
procTexture:SetTexture("Interface\\AddOns\\NikiPriestAuras\\Textures\\SearingLightProc_256")
procTexture:SetBlendMode("ADD")
procTexture:SetPoint("CENTER", procFrame, "CENTER", 0, 0)
procTexture:SetWidth(PROC_ALERT_WIDTH)
procTexture:SetHeight(PROC_ALERT_HEIGHT)
procFrame.texture = procTexture
procFrame.halo = procHalo
procFrame.glowOuter = procGlowOuter
procFrame.glowInner = procGlowInner
procFrame.waves = procWaveTextures
procFrame:Hide()

-- The disappearance burst lives on its own frame. Aura polling can hide the
-- active proc frame immediately after Smite consumes the buff, but this layer
-- remains independent and always finishes its short explosion animation.
local procExplosionFrame = CreateFrame(
    "Frame", "NikiPriestAurasSearingLightExplosion", UIParent
)
procExplosionFrame:SetWidth(PROC_ALERT_WIDTH)
procExplosionFrame:SetHeight(PROC_ALERT_HEIGHT)
procExplosionFrame:SetPoint("CENTER", procFrame, "CENTER", 0, 0)
procExplosionFrame:SetFrameStrata("HIGH")
procExplosionFrame:SetFrameLevel(21)
procExplosionFrame:EnableMouse(false)

local procExplosionGlow = procExplosionFrame:CreateTexture(nil, "ARTWORK")
procExplosionGlow:SetTexture(
    "Interface\\AddOns\\NikiPriestAuras\\Textures\\SearingLightProc_256"
)
procExplosionGlow:SetBlendMode("ADD")
procExplosionGlow:SetVertexColor(0.82, 0.90, 1.00, 1)
procExplosionGlow:SetPoint("CENTER", procExplosionFrame, "CENTER", 0, 0)

local procExplosionTexture = procExplosionFrame:CreateTexture(nil, "OVERLAY")
procExplosionTexture:SetTexture(
    "Interface\\AddOns\\NikiPriestAuras\\Textures\\SearingLightProc_256"
)
procExplosionTexture:SetBlendMode("ADD")
procExplosionTexture:SetVertexColor(1.00, 0.98, 0.92, 1)
procExplosionTexture:SetPoint("CENTER", procExplosionFrame, "CENTER", 0, 0)
procExplosionFrame:Hide()

local function GetConfiguredAlpha()
    if type(NikiPriestAurasDB) == "table" and type(NikiPriestAurasDB.alpha) == "number" then
        return NikiPriestAurasDB.alpha / 100
    end
    return 1
end

local function GetIconDisplayAlpha()
    local alpha = GetConfiguredAlpha()
    if settingsMode and alpha < 0.25 then
        return 0.25
    end
    return alpha
end

local function GetIconConfiguredScale()
    if type(NikiPriestAurasDB) == "table" and type(NikiPriestAurasDB.iconScale) == "number" then
        return NikiPriestAurasDB.iconScale / 100
    end
    return 1
end

local function GetIconConfiguredSpacing()
    if type(NikiPriestAurasDB) == "table" and
       type(NikiPriestAurasDB.iconSpacing) == "number" then
        return NikiPriestAurasDB.iconSpacing
    end
    return ICON_GAP * GetIconConfiguredScale()
end

local function ApplyIconScale()
    local configuredScale = GetIconConfiguredScale()
    local iconSize = ICON_SIZE * configuredScale
    local index

    -- Keep the movable container at scale 1. Using SetScale here makes the
    -- coordinates returned after dragging differ from UIParent coordinates,
    -- which causes the icons to jump when the mouse button is released.
    anchor:SetScale(1)
    anchor:SetHeight(iconSize)
    for index = 1, table.getn(reminderIcons) do
        reminderIcons[index]:SetWidth(iconSize)
        reminderIcons[index]:SetHeight(iconSize)
        reminderIcons[index].glow:SetWidth(iconSize * 1.55)
        reminderIcons[index].glow:SetHeight(iconSize * 1.55)
    end
end

local function GetProcConfiguredAlpha()
    if type(NikiPriestAurasDB) == "table" and type(NikiPriestAurasDB.procAlpha) == "number" then
        return NikiPriestAurasDB.procAlpha / 100
    end
    return 0.85
end

local function GetProcDisplayAlpha()
    local alpha = GetProcConfiguredAlpha()
    if (procPlacementMode or settingsMode) and alpha < 0.25 then
        return 0.25
    end
    return alpha
end

local function GetProcConfiguredScale()
    if type(NikiPriestAurasDB) == "table" and type(NikiPriestAurasDB.procScale) == "number" then
        return NikiPriestAurasDB.procScale / 100
    end
    return 1
end

local function GetAuraConfiguredAlpha()
    if type(NikiPriestAurasDB) == "table" and
       type(NikiPriestAurasDB.auraAlpha) == "number" then
        return NikiPriestAurasDB.auraAlpha / 100
    end
    return 1
end

local function GetAuraDisplayAlpha()
    local alpha = GetAuraConfiguredAlpha()
    if settingsMode and settingsSelection == "aura" and alpha < 0.25 then
        return 0.25
    end
    return alpha
end

local function GetAuraConfiguredScale()
    if type(NikiPriestAurasDB) == "table" and
       type(NikiPriestAurasDB.auraScale) == "number" then
        return NikiPriestAurasDB.auraScale / 100
    end
    return 1
end

local function ApplyAuraDimensions()
    local scale = GetAuraConfiguredScale()
    enlightenedAuraFrame:SetWidth(ENLIGHTENED_AURA_WIDTH * scale)
    enlightenedAuraFrame:SetHeight(ENLIGHTENED_AURA_HEIGHT * scale)
end

local function GetProcAnimationSpeed()
    if type(NikiPriestAurasDB) == "table" and type(NikiPriestAurasDB.procAnimationSpeed) == "number" then
        return NikiPriestAurasDB.procAnimationSpeed / 100
    end
    return 1
end

local function ApplyProcDimensions(pulseScale, innerGlowScale, outerGlowScale)
    local configuredScale = GetProcConfiguredScale()
    local width = PROC_ALERT_WIDTH * configuredScale
    local height = PROC_ALERT_HEIGHT * configuredScale
    local mainScale = pulseScale or 1
    local innerScale = innerGlowScale or 1.04
    local outerScale = outerGlowScale or 1.10

    procFrame:SetWidth(width)
    procFrame:SetHeight(height)
    procTexture:SetWidth(width * mainScale)
    procTexture:SetHeight(height * mainScale)
    procGlowInner:SetWidth(width * innerScale)
    procGlowInner:SetHeight(height * innerScale)
    procGlowOuter:SetWidth(width * outerScale)
    procGlowOuter:SetHeight(height * outerScale)
    procHalo:SetWidth(height * 0.80 * mainScale)
    procHalo:SetHeight(height * 0.80 * mainScale)
end

local function ApplyProcExplosionDimensions(explosionScale)
    local configuredScale = GetProcConfiguredScale()
    local width = PROC_ALERT_WIDTH * configuredScale
    local height = PROC_ALERT_HEIGHT * configuredScale
    local scale = explosionScale or 1

    procExplosionFrame:SetWidth(width)
    procExplosionFrame:SetHeight(height)
    procExplosionTexture:SetWidth(width * scale)
    procExplosionTexture:SetHeight(height * scale)
    procExplosionGlow:SetWidth(width * (scale + 0.10))
    procExplosionGlow:SetHeight(height * (scale + 0.10))
end

local function HideProcAlertImmediately()
    procAlertActive = false
    procExplosionElapsed = nil
    procGlowLingerElapsed = nil
    procFrame:Hide()
    procExplosionFrame:Hide()
    procScreenGlowFrame:Hide()
    ApplyProcDimensions(1)
    ApplyProcExplosionDimensions(1)
end

local function SetProcAlert(visible, immediate)
    local testActive = procTestUntil and GetTime() < procTestUntil
    if visible and not settingsMode and not testActive and
       type(NikiPriestAurasDB) == "table" and
       NikiPriestAurasDB.addonEnabled == false then
        visible = false
        immediate = true
    end

    if visible then
        if not procAlertActive then
            procAlertActive = true
            procExplosionElapsed = nil
            procGlowLingerElapsed = nil
            procPulseElapsed = 0
            procScreenGlowElapsed = 0
            ApplyProcDimensions(1)
            ApplyProcExplosionDimensions(1)
            procExplosionFrame:Hide()
            local waveIndex
            for waveIndex = 1, table.getn(procWaveTextures) do
                procWaveTextures[waveIndex]:SetAlpha(0)
            end
            procFrame:SetAlpha(GetProcDisplayAlpha())
            procScreenGlowFrame:SetAlpha(0)
            procScreenGlowFrame:Show()
            procFrame:Show()
        else
            -- A new proc can arrive while a previous exit animation is still
            -- fading. Restore both layers immediately and resume normally.
            procExplosionElapsed = nil
            procGlowLingerElapsed = nil
            if not procScreenGlowFrame:IsShown() then
                procScreenGlowFrame:Show()
            end
            if not procFrame:IsShown() then
                procFrame:Show()
            end
        end
    elseif immediate then
        HideProcAlertImmediately()
    elseif procAlertActive then
        -- Falling edge: Smite consumed the proc. The symbol bursts away much
        -- faster than the screen-edge glow, which remains for half a second.
        procAlertActive = false
        procExplosionElapsed = 0
        procGlowLingerElapsed = 0
        procExplosionStartAlpha = procFrame:GetAlpha() or GetProcDisplayAlpha()
        procGlowLingerStartAlpha = procScreenGlowFrame:GetAlpha() or 0
        ApplyProcExplosionDimensions(1)
        procExplosionTexture:SetAlpha(1)
        procExplosionGlow:SetAlpha(0.42)
        procExplosionFrame:SetAlpha(procExplosionStartAlpha)
        procExplosionFrame:Show()
        procFrame:Hide()
    else
        -- Repeated aura polls must not restart either exit timer.
        if not procExplosionElapsed and not procGlowLingerElapsed then
            procFrame:Hide()
            procScreenGlowFrame:Hide()
        end
    end
end

local function UpdateProcAnimation(elapsed)
    if not procAlertActive then
        if procExplosionElapsed then
            procExplosionElapsed = procExplosionElapsed + elapsed
            local progress = math.min(
                1,
                procExplosionElapsed / PROC_SYMBOL_EXPLOSION_DURATION
            )
            local smooth = progress * progress * (3 - 2 * progress)
            -- Grow by 150% from the active symbol size (ending at 250%)
            -- while fading over the configured quarter-second burst.
            local expansion = 1 + smooth * PROC_SYMBOL_EXPLOSION_GROWTH
            ApplyProcExplosionDimensions(expansion)
            procExplosionTexture:SetAlpha(1 - smooth * 0.28)
            procExplosionGlow:SetAlpha((1 - smooth) * 0.42)
            procExplosionFrame:SetAlpha(
                procExplosionStartAlpha * (1 - smooth)
            )

            if progress >= 1 then
                procExplosionElapsed = nil
                procExplosionFrame:Hide()
                ApplyProcExplosionDimensions(1)
            end
        end

        if procGlowLingerElapsed then
            procGlowLingerElapsed = procGlowLingerElapsed + elapsed
            local progress = math.min(
                1,
                procGlowLingerElapsed / PROC_SCREEN_GLOW_LINGER_DURATION
            )
            local smooth = progress * progress * (3 - 2 * progress)
            procScreenGlowFrame:SetAlpha(
                procGlowLingerStartAlpha * (1 - smooth)
            )
            if progress >= 1 then
                procGlowLingerElapsed = nil
                procScreenGlowFrame:Hide()
            end
        end
        return
    end

    if not procFrame:IsShown() then
        return
    end

    -- A single saved multiplier controls entry burst, Breath, shimmer and
    -- traveling silhouette waves so the complete effect remains synchronized.
    procPulseElapsed = procPulseElapsed + elapsed * GetProcAnimationSpeed()
    procScreenGlowElapsed = procScreenGlowElapsed + elapsed
    local innerWave = (math.sin(procPulseElapsed * 8.50 - 1.57) + 1) / 2
    local outerWave = (math.sin(procPulseElapsed * 5.60 + 0.70) + 1) / 2
    local shimmerWave = (math.sin(procPulseElapsed * 13.00 + 0.45) + 1) / 2
    local entryBurst = 0
    if procPulseElapsed < 0.55 then
        entryBurst = (0.55 - procPulseElapsed) / 0.55
    end

    local pulseScale = 0.985 + innerWave * 0.035 + entryBurst * 0.025
    local innerGlowScale = 1.020 + innerWave * 0.090 + entryBurst * 0.040
    local outerGlowScale = 1.070 + outerWave * 0.140 + entryBurst * 0.060
    local pulseAlpha = (0.78 + innerWave * 0.22) * GetProcDisplayAlpha()

    ApplyProcDimensions(pulseScale, innerGlowScale, outerGlowScale)
    procTexture:SetAlpha(0.88 + shimmerWave * 0.12)
    procGlowInner:SetAlpha(0.12 + innerWave * 0.28 + entryBurst * 0.08)
    procGlowOuter:SetAlpha(0.05 + outerWave * 0.22 + entryBurst * 0.10)

    -- A stronger entry flash makes the proc feel immediate; afterwards the
    -- frame breathes softly with the same speed selected for the main artwork.
    local screenGlowEntry = 0
    if procScreenGlowElapsed > PROC_SCREEN_GLOW_DELAY then
        screenGlowEntry = math.min(
            1,
            (procScreenGlowElapsed - PROC_SCREEN_GLOW_DELAY) /
            PROC_SCREEN_GLOW_FADE_IN
        )
    end
    local screenGlowAlpha = (0.13 + outerWave * 0.16 + entryBurst * 0.24) *
                            GetProcDisplayAlpha() * screenGlowEntry
    procScreenGlowFrame:SetAlpha(screenGlowAlpha)

    local configuredScale = GetProcConfiguredScale()
    local baseWidth = PROC_ALERT_WIDTH * configuredScale
    local baseHeight = PROC_ALERT_HEIGHT * configuredScale
    local waveIndex
    for waveIndex = 1, table.getn(procWaveTextures) do
        local wavePhase = procPulseElapsed * 1.15 + (waveIndex - 1) / 3
        wavePhase = wavePhase - math.floor(wavePhase)
        local waveEnvelope = math.sin(wavePhase * 3.14159)
        local travelScale = 0.55 + wavePhase * 0.72
        local waveTexture = procWaveTextures[waveIndex]
        waveTexture:SetWidth(baseWidth * travelScale)
        waveTexture:SetHeight(baseHeight * travelScale)
        waveTexture:SetAlpha(waveEnvelope * (0.23 - wavePhase * 0.07))
    end

    procFrame:SetAlpha(pulseAlpha)
end

local function SetEnlightenedAura(visible, timeLeft)
    if visible and not settingsMode and
       type(NikiPriestAurasDB) == "table" and
       NikiPriestAurasDB.addonEnabled == false then
        visible = false
    end
    if visible and type(NikiPriestAurasDB) == "table" and
       NikiPriestAurasDB.enlightenedAuraEnabled == false then
        visible = false
    end

    timeLeft = tonumber(timeLeft)
    if timeLeft and timeLeft <= 0 then
        timeLeft = nil
    end

    if visible then
        if not enlightenedAuraFrame:IsShown() then
            enlightenedAuraElapsed = 0
            enlightenedAuraRotation = 0
            enlightenedAuraEntryElapsed = 0
            enlightenedAuraDuration = math.max(
                ENLIGHTENED_DEFAULT_DURATION,
                timeLeft or 0
            )
            enlightenedAuraFrame:SetAlpha(0)
            enlightenedAuraFrame:Show()
        elseif timeLeft and enlightenedAuraTimeLeft and
               timeLeft > enlightenedAuraTimeLeft + 0.50 then
            -- A refreshed Enlightened aura starts its warning cadence again.
            enlightenedAuraElapsed = 0
            enlightenedAuraRotation = 0
            enlightenedAuraEntryElapsed = 0
            enlightenedAuraDuration = math.max(
                ENLIGHTENED_DEFAULT_DURATION,
                timeLeft
            )
        elseif timeLeft and timeLeft > enlightenedAuraDuration then
            enlightenedAuraDuration = timeLeft
        end
        enlightenedAuraTimeLeft = timeLeft
    else
        enlightenedAuraFrame:Hide()
        enlightenedAuraTimeLeft = nil
        enlightenedAuraDuration = ENLIGHTENED_DEFAULT_DURATION
    end
end

-- Vanilla 1.12 has no Texture:SetRotation, so rotate the square texture around
-- its centre through the eight-coordinate SetTexCoord form. Positive angles
-- below move the visible artwork clockwise on screen.
local function SetTextureClockwiseRotation(texture, angle)
    local halfCos = math.cos(angle) * 0.5
    local halfSin = math.sin(angle) * 0.5

    texture:SetTexCoord(
        0.5 - halfCos - halfSin, 0.5 + halfSin - halfCos,
        0.5 - halfCos + halfSin, 0.5 + halfSin + halfCos,
        0.5 + halfCos - halfSin, 0.5 - halfSin - halfCos,
        0.5 + halfCos + halfSin, 0.5 - halfSin + halfCos
    )
end

local function UpdateEnlightenedAuraAnimation(elapsed)
    if not enlightenedAuraFrame:IsShown() then
        return
    end

    enlightenedAuraEntryElapsed = enlightenedAuraEntryElapsed + elapsed

    local duration = enlightenedAuraDuration or ENLIGHTENED_DEFAULT_DURATION
    local remaining = enlightenedAuraTimeLeft
    if not remaining then
        remaining = math.max(0, duration - enlightenedAuraEntryElapsed)
    end
    local progress = 1 - math.max(0, math.min(duration, remaining)) / duration
    -- Smoothstep prevents an abrupt speed change. The pulse stays calm at the
    -- start, then accelerates continuously as the eight-second buff expires.
    local speedProgress = progress * progress * (3 - 2 * progress)
    local pulsesPerSecond = ENLIGHTENED_MIN_PULSES_PER_SECOND +
                            (ENLIGHTENED_MAX_PULSES_PER_SECOND -
                             ENLIGHTENED_MIN_PULSES_PER_SECOND) * speedProgress
    enlightenedAuraElapsed = enlightenedAuraElapsed +
                             elapsed * pulsesPerSecond * 6.283185
    enlightenedAuraRotation = enlightenedAuraRotation +
                               elapsed * ENLIGHTENED_ROTATION_RADIANS_PER_SECOND
    if enlightenedAuraRotation >= 6.283185 then
        enlightenedAuraRotation = enlightenedAuraRotation - 6.283185
    end

    -- All ray layers rotate together, preserving the composed aura while its
    -- independent alpha/scale waves continue to create flowing light.
    SetTextureClockwiseRotation(enlightenedAuraTextureMain, enlightenedAuraRotation)
    SetTextureClockwiseRotation(enlightenedAuraTextureFlow, enlightenedAuraRotation)
    SetTextureClockwiseRotation(enlightenedAuraTextureOuter, enlightenedAuraRotation)

    local breath = (math.sin(enlightenedAuraElapsed - 1.5708) + 1) / 2
    local entry = 0
    if enlightenedAuraEntryElapsed < 0.45 then
        entry = enlightenedAuraEntryElapsed / 0.45
    else
        entry = 1
    end

    -- Keep the real buff atmospheric, but make the manual diagnostic test
    -- deliberately obvious so a missing texture can be distinguished from
    -- failed aura detection on old Vanilla clients.
    local minimumAlpha = 0.110 - progress * 0.060
    local pulseRange = 0.100 + progress * 0.080
    local alpha = minimumAlpha + breath * pulseRange
    if enlightenedTestUntil and GetTime() < enlightenedTestUntil then
        alpha = 0.360 + breath * 0.180
    elseif settingsMode and settingsSelection == "aura" then
        alpha = 0.360 + breath * 0.180
    end
    -- The three centered copies use independent scale and alpha waves. Their
    -- anchor never moves, so the aura only pulses and rotates around the player.
    local mainScale = 0.985 + breath * 0.025
    local flowWave = (math.sin(enlightenedAuraElapsed * 0.73 + 1.10) + 1) / 2
    local outerWave = (math.sin(enlightenedAuraElapsed * 0.47 + 2.20) + 1) / 2
    local configuredScale = GetAuraConfiguredScale()
    local auraWidth = ENLIGHTENED_AURA_WIDTH * configuredScale
    local auraHeight = ENLIGHTENED_AURA_HEIGHT * configuredScale

    enlightenedAuraTextureMain:ClearAllPoints()
    enlightenedAuraTextureMain:SetPoint("CENTER", enlightenedAuraFrame, "CENTER", 0, 0)
    enlightenedAuraTextureMain:SetWidth(auraWidth * mainScale)
    enlightenedAuraTextureMain:SetHeight(auraHeight * mainScale)
    enlightenedAuraTextureMain:SetAlpha(0.72 + breath * 0.28)

    enlightenedAuraTextureFlow:ClearAllPoints()
    enlightenedAuraTextureFlow:SetPoint("CENTER", enlightenedAuraFrame, "CENTER", 0, 0)
    enlightenedAuraTextureFlow:SetWidth(
        auraWidth * (1.005 + flowWave * 0.045)
    )
    enlightenedAuraTextureFlow:SetHeight(
        auraHeight * (1.005 + flowWave * 0.045)
    )
    enlightenedAuraTextureFlow:SetAlpha(0.10 + flowWave * 0.20)

    enlightenedAuraTextureOuter:ClearAllPoints()
    enlightenedAuraTextureOuter:SetPoint("CENTER", enlightenedAuraFrame, "CENTER", 0, 0)
    enlightenedAuraTextureOuter:SetWidth(
        auraWidth * (1.055 + outerWave * 0.075)
    )
    enlightenedAuraTextureOuter:SetHeight(
        auraHeight * (1.055 + outerWave * 0.075)
    )
    enlightenedAuraTextureOuter:SetAlpha(0.05 + outerWave * 0.14)

    enlightenedAuraFrame:SetAlpha(alpha * entry * GetAuraDisplayAlpha())
end

local placementText = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
placementText:SetPoint("TOP", anchor, "BOTTOM", 0, -5)
placementText:SetText(L.dragToMove)
placementText:SetTextColor(1, 0.82, 0)
placementText:Hide()

local procPlacementText = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
procPlacementText:SetPoint("TOP", procFrame, "BOTTOM", 0, -3)
procPlacementText:SetTextColor(1, 0.82, 0)
procPlacementText:Hide()

local function UpdateProcPlacementText()
    local procScale = 100
    local procAlpha = 85
    if type(NikiPriestAurasDB) == "table" then
        procScale = NikiPriestAurasDB.procScale or procScale
        procAlpha = NikiPriestAurasDB.procAlpha or procAlpha
    end
    procPlacementText:SetText(L.procDrag .. tostring(procScale) .. L.procAlpha .. tostring(procAlpha) .. "%")
end

local function HideReminders()
    shieldBlinking = false
    local index
    for index = 1, table.getn(reminderIcons) do
        reminderIcons[index]:Hide()
    end
    SetProcAlert(false, true)
    SetEnlightenedAura(false)
end

local function LayoutReminders(showDispel, showDisease, showFortitude, showInnerFire, showEnlighten, showDivineSpirit, showShield)
    local visibleIcons = {}
    local index

    if showShield then
        table.insert(visibleIcons, shieldIcon)
    end
    if showDispel then
        table.insert(visibleIcons, dispelIcon)
    end
    if showDisease then
        table.insert(visibleIcons, diseaseIcon)
    end
    if showFortitude then
        table.insert(visibleIcons, fortitudeIcon)
    end
    if showDivineSpirit then
        table.insert(visibleIcons, divineSpiritIcon)
    end
    if showInnerFire then
        table.insert(visibleIcons, innerFireIcon)
    end
    if showEnlighten then
        table.insert(visibleIcons, enlightenIcon)
    end

    for index = 1, table.getn(reminderIcons) do
        reminderIcons[index]:ClearAllPoints()
        reminderIcons[index]:Hide()
    end

    local visibleCount = table.getn(visibleIcons)
    local configuredScale = GetIconConfiguredScale()
    local iconSize = ICON_SIZE * configuredScale
    -- Spacing is configured independently from icon size, in UI pixels.
    local iconGap = GetIconConfiguredSpacing()
    if visibleCount == 0 then
        anchor:SetWidth(iconSize)
        anchor:SetHeight(iconSize)
        return
    end

    local totalWidth = visibleCount * iconSize + (visibleCount - 1) * iconGap
    anchor:SetWidth(totalWidth)
    anchor:SetHeight(iconSize)
    local firstOffset = -((totalWidth - iconSize) / 2)

    for index = 1, visibleCount do
        visibleIcons[index]:SetPoint(
            "CENTER",
            anchor,
            "CENTER",
            firstOffset + (index - 1) * (iconSize + iconGap),
            0
        )
        visibleIcons[index]:Show()
    end
end

local function NormalizeSpellId(spellId)
    if spellId and spellId < 0 then
        return spellId + 65536
    end
    return spellId
end

local function IsEnlightenedTexture(texture)
    return texture and
           string.find(string.lower(texture), "spell_holy_powerinfusion")
end

local function IsEnlightenedBuffIndex(buffIndex)
    if buffIndex == nil or buffIndex < 0 then
        return false
    end

    local texture = GetPlayerBuffTexture(buffIndex)
    if not texture then
        return false
    end

    enlightenedScanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    enlightenedScanTooltip:SetPlayerBuff(buffIndex)
    local nameLine = getglobal("NikiPriestAurasEnlightenedScanTooltipTextLeft1")
    local buffName = nameLine and nameLine:GetText() or ""
    enlightenedScanTooltip:Hide()

    if buffName ~= "" then
        return string.lower(buffName) == "enlightened"
    end

    -- Texture fallback for client builds where the hidden tooltip does not
    -- expose a custom aura's name.
    return IsEnlightenedTexture(texture)
end

local function PlayerHasEnlightenedBuff()
    -- Vanilla exposes an internal aura id through GetPlayerBuff. That id, not
    -- the visible zero-based slot, must be passed to the texture and tooltip
    -- functions. Turtle custom auras are most reliable through this path.
    if type(GetPlayerBuff) == "function" and
       type(GetPlayerBuffTexture) == "function" then
        local slot
        for slot = 0, 31 do
            local buffIndex = GetPlayerBuff(slot, "HELPFUL")
            if not buffIndex or buffIndex < 0 then
                break
            end
            if IsEnlightenedBuffIndex(buffIndex) then
                local timeLeft = nil
                if type(GetPlayerBuffTimeLeft) == "function" then
                    timeLeft = GetPlayerBuffTimeLeft(buffIndex)
                end
                return true, timeLeft
            end
        end
    end

    -- Compatibility fallback for clients that expose custom buffs via the
    -- newer UnitBuff return values instead.
    local index
    for index = 1, 32 do
        local texture = UnitBuff("player", index)
        if not texture then
            break
        end

        if IsEnlightenedTexture(texture) then
            return true
        end
    end

    return false
end

local function IsSearingLightTexture(texture)
    if not texture then
        return false
    end

    return string.find(
        string.lower(texture),
        "spell_holy_searinglightpriest"
    ) and true or false
end

local function PlayerHasSearingLightProc()
    -- Use the original Vanilla player-buff API first. On Turtle/SuperWoW the
    -- UnitBuff list can briefly be incomplete while the player is moving,
    -- which used to make the alert repeatedly hide and restart its animation.
    if type(GetPlayerBuff) == "function" and
       type(GetPlayerBuffTexture) == "function" then
        local slot
        for slot = 0, 31 do
            local buffIndex = GetPlayerBuff(slot, "HELPFUL")
            if not buffIndex or buffIndex < 0 then
                break
            end

            if IsSearingLightTexture(GetPlayerBuffTexture(buffIndex)) then
                return true
            end
        end
    end

    -- Keep the extended UnitBuff spell-id path as a compatibility fallback.
    local index
    for index = 1, 32 do
        local texture, stacks, spellId = UnitBuff("player", index)
        if not texture then
            break
        end

        spellId = NormalizeSpellId(spellId)
        if spellId == SEARING_LIGHT_SPELL_ID then
            return true
        end

        if IsSearingLightTexture(texture) then
            return true
        end
    end

    return false
end

local function IsMagicAura(spellId)
    spellId = NormalizeSpellId(spellId)
    if not spellId then
        return false
    end

    if magicDispelCache[spellId] ~= nil then
        return magicDispelCache[spellId]
    end

    local dispelType = nil
    if type(GetSpellRecField) == "function" then
        local ok, value = pcall(GetSpellRecField, spellId, "dispel")
        if ok then
            dispelType = value
        end
    elseif type(GetSpellRec) == "function" then
        local ok, spellData = pcall(GetSpellRec, spellId)
        if ok and spellData then
            dispelType = spellData.dispel
        end
    end

    magicDispelCache[spellId] = (dispelType == MAGIC_DISPEL_TYPE)
    return magicDispelCache[spellId]
end

local function HostileTargetHasMagicBuff()
    local index
    for index = 1, 32 do
        local texture, stacks, spellId = UnitBuff("target", index)
        if not texture then
            break
        end
        if IsMagicAura(spellId) then
            return true
        end
    end
    return false
end

local function GetUnitDispelTypes(unit)
    local hasMagic = false
    local hasDisease = false
    local index

    for index = 1, 16 do
        local texture, stacks, debuffType = UnitDebuff(unit, index)
        if not texture then
            break
        end

        if debuffType == "Magic" then
            hasMagic = true
        elseif debuffType == "Disease" then
            hasDisease = true
        end

        if hasMagic and hasDisease then
            break
        end
    end

    return hasMagic, hasDisease
end

local function RefreshTrackedBuffSpellState()
    enlightenKnown = false
    enlightenSpellTexture = nil
    dispelMagicSpellTexture = nil
    cureDiseaseSpellTexture = nil
    fortitudeSpellTexture = nil
    innerFireSpellTexture = nil
    divineSpiritKnown = false
    divineSpiritSpellTexture = nil
    powerWordShieldKnown = false
    powerWordShieldSpellTexture = nil

    local _, playerClass = UnitClass("player")
    if playerClass ~= "PRIEST" then
        return
    end

    local bookType = BOOKTYPE_SPELL or "spell"
    local spellIndex
    for spellIndex = 1, 512 do
        local spellName = GetSpellName(spellIndex, bookType)
        if not spellName then
            break
        end

        local spellTexture = nil
        if type(GetSpellTexture) == "function" then
            spellTexture = GetSpellTexture(spellIndex, bookType)
        end
        local normalizedName = string.lower(spellName)
        local normalizedTexture = spellTexture and string.lower(spellTexture) or ""

        -- Name detection is exact on the English Turtle client. The icon
        -- fallback keeps this working if the client localizes the spell name.
        if normalizedName == "enlighten" or
           string.find(normalizedTexture, "btnholyscriptures") then
            enlightenKnown = true
            enlightenSpellTexture = spellTexture
        elseif normalizedName == "dispel magic" or
               string.find(normalizedTexture, "spell_holy_dispelmagic") then
            dispelMagicSpellTexture = spellTexture
        elseif normalizedName == "cure disease" or
               string.find(normalizedTexture, "spell_holy_nullifydisease") then
            cureDiseaseSpellTexture = spellTexture
        elseif normalizedName == "power word: fortitude" or
               string.find(normalizedTexture, "spell_holy_wordfortitude") then
            fortitudeSpellTexture = spellTexture
        elseif normalizedName == "inner fire" or
               string.find(normalizedTexture, "spell_holy_innerfire") then
            innerFireSpellTexture = spellTexture
        elseif normalizedName == "divine spirit" or
               string.find(normalizedTexture, "spell_holy_divinespirit") then
            divineSpiritKnown = true
            divineSpiritSpellTexture = spellTexture
        elseif normalizedName == "power word: shield" or
               string.find(normalizedTexture, "spell_holy_powerwordshield") then
            powerWordShieldKnown = true
            powerWordShieldSpellTexture = spellTexture
        end

    end

    ApplyReminderTextureStyle()
end

local function GetPowerWordShieldState()
    if type(GetPlayerBuff) == "function" and
       type(GetPlayerBuffTexture) == "function" then
        local firstBuff = PLAYER_BUFF_START_ID or 0
        local slot
        for slot = 0, 31 do
            local buffIndex = GetPlayerBuff(firstBuff + slot, "HELPFUL")
            if not buffIndex or buffIndex < 0 then
                break
            end

            local texture = GetPlayerBuffTexture(buffIndex)
            if texture then
                local textureName = string.lower(texture)
                if string.find(textureName, "spell_holy_powerwordshield") or
                   (powerWordShieldSpellTexture and
                    textureName == string.lower(powerWordShieldSpellTexture)) then
                    local timeLeft = nil
                    if type(GetPlayerBuffTimeLeft) == "function" then
                        timeLeft = GetPlayerBuffTimeLeft(buffIndex)
                    end
                    return true, timeLeft
                end
            end
        end
    end

    -- Presence fallback for clients that do not expose the Vanilla player
    -- buff timer API. Missing-shield warnings still work in that case.
    local index
    for index = 1, 32 do
        local texture = UnitBuff("player", index)
        if not texture then
            break
        end
        local textureName = string.lower(texture)
        if string.find(textureName, "spell_holy_powerwordshield") or
           (powerWordShieldSpellTexture and
            textureName == string.lower(powerWordShieldSpellTexture)) then
            return true, nil
        end
    end

    return false, nil
end

local function PlayerHasWeakenedSoul()
    local index
    for index = 1, 32 do
        local texture = UnitDebuff("player", index)
        if not texture then
            break
        end

        local textureName = string.lower(texture)
        if string.find(textureName, "spell_holy_ashestoashes") or
           string.find(textureName, "weakenedsoul") then
            return true
        end

        -- The standard texture check is reliable on Vanilla, while the
        -- tooltip name also covers Turtle custom texture replacements.
        if type(enlightenedScanTooltip.SetUnitDebuff) == "function" then
            enlightenedScanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
            enlightenedScanTooltip:ClearLines()
            enlightenedScanTooltip:SetUnitDebuff("player", index)
            local nameLine = getglobal(
                "NikiPriestAurasEnlightenedScanTooltipTextLeft1"
            )
            local debuffName = nameLine and nameLine:GetText() or ""
            enlightenedScanTooltip:Hide()
            local normalizedDebuffName = string.lower(debuffName)
            if normalizedDebuffName == "weakened soul" or
               normalizedDebuffName == "ослабленная душа" then
                return true
            end
        end
    end

    return false
end

local function IsShieldReminderEnabled()
    return type(NikiPriestAurasDB) ~= "table" or
           NikiPriestAurasDB.shieldEnabled ~= false
end

local function IsUnderCreatureAttack()
    return inCombat and
           lastIncomingCreatureAttack and
           GetTime() - lastIncomingCreatureAttack <= INCOMING_ATTACK_TIMEOUT
end

local function PlayerIsOnTaxi()
    return type(UnitOnTaxi) == "function" and
           UnitOnTaxi("player") and true or false
end

local function UpdateShieldBlink()
    if shieldBlinking and shieldIcon:IsShown() and
       not settingsMode and not placementMode and not procPlacementMode then
        -- Weakened Soul prevents recasting the shield. Pulse quickly but
        -- smoothly until the debuff disappears; then the reminder immediately
        -- returns to its configured full opacity to signal that casting is ready.
        local phase = GetTime() / WEAKENED_SOUL_BLINK_INTERVAL
        local fade = (math.sin(phase * 3.14159 - 1.5708) + 1) / 2
        local blinkAlpha = 0.10 + fade * 0.90
        shieldIcon:SetAlpha(GetIconDisplayAlpha() * blinkAlpha)
    elseif shieldIcon:IsShown() then
        shieldIcon:SetAlpha(GetIconDisplayAlpha())
    end
end

local function IsEnlightenBuffTexture(texture)
    if not texture then
        return false
    end

    local textureName = string.lower(texture)
    return string.find(textureName, "btnholyscriptures") or
           (enlightenSpellTexture and
            textureName == string.lower(enlightenSpellTexture))
end

local function UnitHasEnlightenBuff(unit)
    if not UnitExists(unit) then
        return false
    end

    local index
    for index = 1, 32 do
        local texture = UnitBuff(unit, index)
        if not texture then
            break
        end
        if IsEnlightenBuffTexture(texture) then
            return true
        end
    end

    return false
end

local function GroupHasEnlightenBuff()
    if UnitHasEnlightenBuff("player") then
        return true
    end

    local raidCount = GetNumRaidMembers()
    if raidCount and raidCount > 0 then
        local raidIndex
        for raidIndex = 1, raidCount do
            if UnitHasEnlightenBuff("raid" .. raidIndex) then
                return true, nil
            end
        end
        return false
    end

    local partyCount = GetNumPartyMembers()
    if partyCount then
        local partyIndex
        for partyIndex = 1, partyCount do
            if UnitHasEnlightenBuff("party" .. partyIndex) then
                return true
            end
        end
    end

    return false, nil
end

local function GetMissingPlayerBuffs()
    local hasFortitude = false
    local hasInnerFire = false
    local hasEnlighten = false
    local hasDivineSpirit = false
    local index

    for index = 1, 32 do
        local texture = UnitBuff("player", index)
        if not texture then
            break
        end

        local textureName = string.lower(texture)
        if string.find(textureName, "spell_holy_wordfortitude") or
           string.find(textureName, "spell_holy_prayeroffortitude") then
            hasFortitude = true
        elseif string.find(textureName, "spell_holy_innerfire") then
            hasInnerFire = true
        elseif string.find(textureName, "spell_holy_divinespirit") or
               string.find(textureName, "spell_holy_prayerofspirit") or
               (divineSpiritSpellTexture and textureName == string.lower(divineSpiritSpellTexture)) then
            hasDivineSpirit = true
        elseif IsEnlightenBuffTexture(texture) then
            hasEnlighten = true
        end

        if hasFortitude and hasInnerFire and
           (hasEnlighten or not enlightenKnown) and
           (hasDivineSpirit or not divineSpiritKnown) then
            break
        end
    end

    -- Enlighten can be maintained on only one party member. Do not ask the
    -- priest to recast it when the tutelage is already active on an ally.
    if enlightenKnown and not hasEnlighten then
        hasEnlighten = GroupHasEnlightenBuff()
    end

    return not hasFortitude,
           not hasInnerFire,
           enlightenKnown and not hasEnlighten,
           divineSpiritKnown and not hasDivineSpirit
end

local function UpdateReminders()
    if not settingsMode and type(NikiPriestAurasDB) == "table" and
       NikiPriestAurasDB.addonEnabled == false then
        HideReminders()
        return
    end

    if PlayerIsOnTaxi() then
        HideReminders()
        return
    end

    if settingsMode then
        shieldBlinking = false
        if settingsSelection == "icons" then
            SetEnlightenedAura(false)
            SetProcAlert(false, true)
            LayoutReminders(true, true, true, true, true, true, IsShieldReminderEnabled())
        elseif settingsSelection == "aura" then
            LayoutReminders(false, false, false, false, false, false, false)
            SetProcAlert(false, true)
            SetEnlightenedAura(true, ENLIGHTENED_DEFAULT_DURATION)
        else
            SetEnlightenedAura(false)
            LayoutReminders(false, false, false, false, false, false, false)
            SetProcAlert(true)
        end
        UpdateShieldBlink()
        return
    end

    if procPlacementMode then
        shieldBlinking = false
        SetEnlightenedAura(false)
        LayoutReminders(false, false, false, false, false, false, false)
        SetProcAlert(true)
        return
    end

    if placementMode then
        shieldBlinking = false
        SetProcAlert(false, true)
        SetEnlightenedAura(false)
        LayoutReminders(true, false, false, false, false, false, false)
        return
    end

    if UnitIsDeadOrGhost("player") then
        HideReminders()
        return
    end

    local _, playerClass = UnitClass("player")
    local showFortitude = false
    local showInnerFire = false
    local showEnlighten = false
    local showDivineSpirit = false
    local showShield = false
    local blinkShield = false
    local showDispel = false
    local showDisease = false
    local showSearingLight = false
    local showEnlightened = false
    local enlightenedTimeLeft = nil

    if playerClass == "PRIEST" then
        showDispel, showDisease = GetUnitDispelTypes("player")
        local missingFortitude, missingInnerFire, missingEnlighten, missingDivineSpirit = GetMissingPlayerBuffs()
        showInnerFire = missingInnerFire
        showEnlighten = missingEnlighten
        showDivineSpirit = missingDivineSpirit

        if IsShieldReminderEnabled() and
           powerWordShieldKnown and IsUnderCreatureAttack() then
            local hasShield, shieldTimeLeft = GetPowerWordShieldState()
            if not hasShield then
                showShield = true
            elseif shieldTimeLeft and shieldTimeLeft > 0 and
                   shieldTimeLeft <= SHIELD_WARNING_TIME then
                showShield = true
            end
            blinkShield = showShield and PlayerHasWeakenedSoul()
        end
        showSearingLight = PlayerHasSearingLightProc()
        showEnlightened, enlightenedTimeLeft = PlayerHasEnlightenedBuff()
        if procTestUntil and GetTime() < procTestUntil then
            showSearingLight = true
        end
        if enlightenedTestUntil and GetTime() < enlightenedTestUntil then
            showEnlightened = true
            enlightenedTimeLeft = enlightenedTestUntil - GetTime()
        end
        if not inCombat then
            showFortitude = missingFortitude
        end
    end

    if inCombat and UnitExists("target") and not UnitIsDeadOrGhost("target") then
        if UnitCanAttack("player", "target") then
            showDispel = showDispel or HostileTargetHasMagicBuff()
        elseif UnitIsFriend("player", "target") then
            local targetMagic, targetDisease = GetUnitDispelTypes("target")
            showDispel = targetMagic or showDispel
            showDisease = targetDisease or showDisease
        end
    end

    shieldBlinking = blinkShield and showShield
    LayoutReminders(showDispel, showDisease, showFortitude, showInnerFire, showEnlighten, showDivineSpirit, showShield)
    UpdateShieldBlink()
    SetProcAlert(showSearingLight)
    SetEnlightenedAura(showEnlightened, enlightenedTimeLeft)
end

local function PrintMessage(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff80c0ffNikiPriestAuras:|r " .. message)
    end
end

local function InitializeDatabase()
    if type(NikiPriestAurasDB) ~= "table" then
        NikiPriestAurasDB = {}
    end

    if type(NikiPriestAurasDB.x) ~= "number" then
        NikiPriestAurasDB.x = 0
    end
    if type(NikiPriestAurasDB.y) ~= "number" then
        NikiPriestAurasDB.y = 0
    end
    if type(NikiPriestAurasDB.alpha) ~= "number" then
        NikiPriestAurasDB.alpha = 100
    end
    if type(NikiPriestAurasDB.iconScale) ~= "number" then
        NikiPriestAurasDB.iconScale = 100
    end
    if type(NikiPriestAurasDB.iconSpacing) ~= "number" then
        -- Preserve the exact visual gap used by earlier versions on the first
        -- load, then keep it independent from subsequent size changes.
        NikiPriestAurasDB.iconSpacing = math.floor(
            ICON_GAP * (NikiPriestAurasDB.iconScale / 100) + 0.5
        )
    end
    if type(NikiPriestAurasDB.procX) ~= "number" then
        NikiPriestAurasDB.procX = 0
    end
    if type(NikiPriestAurasDB.procY) ~= "number" then
        NikiPriestAurasDB.procY = 155
    end
    if type(NikiPriestAurasDB.procScale) ~= "number" then
        NikiPriestAurasDB.procScale = 100
    end
    if type(NikiPriestAurasDB.procAlpha) ~= "number" then
        NikiPriestAurasDB.procAlpha = 85
    end
    if type(NikiPriestAurasDB.auraX) ~= "number" then
        NikiPriestAurasDB.auraX = 0
    end
    if type(NikiPriestAurasDB.auraY) ~= "number" then
        NikiPriestAurasDB.auraY = 0
    end
    if type(NikiPriestAurasDB.auraScale) ~= "number" then
        NikiPriestAurasDB.auraScale = 100
    end
    if type(NikiPriestAurasDB.auraAlpha) ~= "number" then
        NikiPriestAurasDB.auraAlpha = 100
    end
    if type(NikiPriestAurasDB.enlightenedAuraEnabled) ~= "boolean" then
        NikiPriestAurasDB.enlightenedAuraEnabled = true
    end
    if type(NikiPriestAurasDB.procAnimationSpeed) ~= "number" then
        NikiPriestAurasDB.procAnimationSpeed = 100
    end
    if type(NikiPriestAurasDB.shieldEnabled) ~= "boolean" then
        NikiPriestAurasDB.shieldEnabled = true
    end
    if type(NikiPriestAurasDB.addonEnabled) ~= "boolean" then
        NikiPriestAurasDB.addonEnabled = true
    end
    if NikiPriestAurasDB.shieldFrameMode ~= "pfui" and
       NikiPriestAurasDB.shieldFrameMode ~= "blizzard" then
        -- Preserve the old placement when pfUI is available, but make the
        -- built-in player frame work automatically on a stock UI install.
        if pfUI and pfUI.uf then
            NikiPriestAurasDB.shieldFrameMode = "pfui"
        else
            NikiPriestAurasDB.shieldFrameMode = "blizzard"
        end
    end
    if type(NikiPriestAurasDB.originalReminderTextures) ~= "boolean" then
        NikiPriestAurasDB.originalReminderTextures = false
    end

    if NikiPriestAurasDB.alpha < 0 then
        NikiPriestAurasDB.alpha = 0
    elseif NikiPriestAurasDB.alpha > 100 then
        NikiPriestAurasDB.alpha = 100
    end
    if NikiPriestAurasDB.iconScale < 50 then
        NikiPriestAurasDB.iconScale = 50
    elseif NikiPriestAurasDB.iconScale > 200 then
        NikiPriestAurasDB.iconScale = 200
    end
    if NikiPriestAurasDB.iconSpacing < 0 then
        NikiPriestAurasDB.iconSpacing = 0
    elseif NikiPriestAurasDB.iconSpacing > 100 then
        NikiPriestAurasDB.iconSpacing = 100
    end
    if NikiPriestAurasDB.procScale < 10 then
        NikiPriestAurasDB.procScale = 10
    elseif NikiPriestAurasDB.procScale > 300 then
        NikiPriestAurasDB.procScale = 300
    end
    if NikiPriestAurasDB.procAlpha < 0 then
        NikiPriestAurasDB.procAlpha = 0
    elseif NikiPriestAurasDB.procAlpha > 100 then
        NikiPriestAurasDB.procAlpha = 100
    end
    if NikiPriestAurasDB.auraScale < 25 then
        NikiPriestAurasDB.auraScale = 25
    elseif NikiPriestAurasDB.auraScale > 250 then
        NikiPriestAurasDB.auraScale = 250
    end
    if NikiPriestAurasDB.auraAlpha < 0 then
        NikiPriestAurasDB.auraAlpha = 0
    elseif NikiPriestAurasDB.auraAlpha > 100 then
        NikiPriestAurasDB.auraAlpha = 100
    end
    if NikiPriestAurasDB.procAnimationSpeed < 25 then
        NikiPriestAurasDB.procAnimationSpeed = 25
    elseif NikiPriestAurasDB.procAnimationSpeed > 300 then
        NikiPriestAurasDB.procAnimationSpeed = 300
    end

    anchor:ClearAllPoints()
    anchor:SetPoint("CENTER", UIParent, "CENTER", NikiPriestAurasDB.x, NikiPriestAurasDB.y)
    ApplyIconScale()
    ApplyReminderTextureStyle()
    procFrame:ClearAllPoints()
    procFrame:SetPoint("CENTER", UIParent, "CENTER", NikiPriestAurasDB.procX, NikiPriestAurasDB.procY)
    ApplyProcDimensions(1)
    UpdateProcPlacementText()
    enlightenedAuraFrame:ClearAllPoints()
    enlightenedAuraFrame:SetPoint(
        "CENTER", UIParent, "CENTER",
        NikiPriestAurasDB.auraX, NikiPriestAurasDB.auraY
    )
    ApplyAuraDimensions()

    local index
    for index = 1, table.getn(reminderIcons) do
        reminderIcons[index]:SetAlpha(NikiPriestAurasDB.alpha / 100)
    end
    if procFrame:IsShown() then
        UpdateProcAnimation(0)
    end
end

local function SavePosition()
    if type(NikiPriestAurasDB) ~= "table" then
        NikiPriestAurasDB = {}
    end

    local anchorX, anchorY = anchor:GetCenter()
    local parentX, parentY = UIParent:GetCenter()
    if not anchorX or not anchorY or not parentX or not parentY then
        return
    end

    NikiPriestAurasDB.x = anchorX - parentX
    NikiPriestAurasDB.y = anchorY - parentY

    anchor:ClearAllPoints()
    anchor:SetPoint("CENTER", UIParent, "CENTER", NikiPriestAurasDB.x, NikiPriestAurasDB.y)
end

local function FinishIconDragging()
    if not iconDragging then
        return
    end

    anchor:StopMovingOrSizing()
    iconDragging = false
    SavePosition()
end

local function StartDragging()
    if placementMode or settingsMode then
        GameTooltip:Hide()
        iconDragging = true
        anchor:StartMoving()
    end
end

local function StopDragging()
    FinishIconDragging()
end

dispelIcon:SetScript("OnDragStart", StartDragging)
dispelIcon:SetScript("OnDragStop", StopDragging)
diseaseIcon:SetScript("OnDragStart", StartDragging)
diseaseIcon:SetScript("OnDragStop", StopDragging)
fortitudeIcon:SetScript("OnDragStart", StartDragging)
fortitudeIcon:SetScript("OnDragStop", StopDragging)
innerFireIcon:SetScript("OnDragStart", StartDragging)
innerFireIcon:SetScript("OnDragStop", StopDragging)
enlightenIcon:SetScript("OnDragStart", StartDragging)
enlightenIcon:SetScript("OnDragStop", StopDragging)

-- In the unified settings mode the parent container handles the complete
-- drag lifecycle itself. This avoids a Vanilla client bug where a child icon
-- starts moving its parent but never receives the matching mouse-up event.
anchor:SetScript("OnDragStart", function()
    if settingsMode and settingsSelection == "icons" then
        GameTooltip:Hide()
        iconDragging = true
        anchor:StartMoving()
    end
end)

anchor:SetScript("OnDragStop", function()
    FinishIconDragging()
end)

anchor:SetScript("OnMouseUp", function()
    FinishIconDragging()
end)

local function ApplyConfiguredAlpha()
    local alpha = GetIconDisplayAlpha()

    local index
    for index = 1, table.getn(reminderIcons) do
        reminderIcons[index]:SetAlpha(alpha)
    end
    if procFrame:IsShown() then
        UpdateProcAnimation(0)
    end
end

local function SetPlacementMode(enabled)
    placementMode = enabled and true or false

    if placementMode then
        SetProcAlert(false, true)
        local index
        for index = 1, table.getn(reminderIcons) do
            reminderIcons[index]:EnableMouse(true)
            reminderIcons[index]:SetAlpha(0.50)
            reminderIcons[index].icon:SetDesaturated(1)
        end
        placementText:Show()
        LayoutReminders(true, false, false, false, false, false, false)
        PrintMessage("placement mode enabled. Drag the faded icon, then close the settings window.")
    else
        anchor:StopMovingOrSizing()
        SavePosition()
        local index
        for index = 1, table.getn(reminderIcons) do
            reminderIcons[index]:EnableMouse(false)
            reminderIcons[index].icon:SetDesaturated(nil)
        end
        ApplyConfiguredAlpha()
        placementText:Hide()
        UpdateReminders()
        PrintMessage("position saved; the icon is locked and click-through.")
    end
end

local function SetIconSize(percent, quiet)
    if percent < 50 or percent > 200 then
        PrintMessage("icon size must be from 50 to 200%.")
        return
    end

    if type(NikiPriestAurasDB) ~= "table" then
        NikiPriestAurasDB = {}
    end

    NikiPriestAurasDB.iconScale = percent
    ApplyIconScale()
    UpdateReminders()
    if not quiet then
        PrintMessage("center icon size set to " .. tostring(percent) .. "%.")
    end
end

local function SetIconSpacing(pixels, quiet)
    if pixels < 0 or pixels > 100 then
        PrintMessage("icon spacing must be from 0 to 100 pixels.")
        return
    end

    if type(NikiPriestAurasDB) ~= "table" then
        NikiPriestAurasDB = {}
    end

    NikiPriestAurasDB.iconSpacing = pixels
    UpdateReminders()
    if not quiet then
        PrintMessage("icon spacing set to " .. tostring(pixels) .. " pixels.")
    end
end

local function SetOpacity(percent, quiet)
    if percent < 0 or percent > 100 then
        PrintMessage("opacity must be a number from 0 to 100.")
        return
    end

    if type(NikiPriestAurasDB) ~= "table" then
        NikiPriestAurasDB = {}
    end

    NikiPriestAurasDB.alpha = percent
    if not placementMode then
        ApplyConfiguredAlpha()
    end
    if not quiet then
        PrintMessage("icon opacity set to " .. tostring(percent) .. "%.")
    end
end

local function ResetPosition()
    if type(NikiPriestAurasDB) ~= "table" then
        NikiPriestAurasDB = {}
    end

    NikiPriestAurasDB.x = 0
    NikiPriestAurasDB.y = 0
    anchor:ClearAllPoints()
    anchor:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    UpdateReminders()
    PrintMessage("position reset to the center of the screen.")
end

local function SaveAuraPosition()
    if type(NikiPriestAurasDB) ~= "table" then
        NikiPriestAurasDB = {}
    end

    local frameX, frameY = enlightenedAuraFrame:GetCenter()
    local parentX, parentY = UIParent:GetCenter()
    if not frameX or not frameY or not parentX or not parentY then
        return
    end

    NikiPriestAurasDB.auraX = frameX - parentX
    NikiPriestAurasDB.auraY = frameY - parentY

    enlightenedAuraFrame:ClearAllPoints()
    enlightenedAuraFrame:SetPoint(
        "CENTER", UIParent, "CENTER",
        NikiPriestAurasDB.auraX, NikiPriestAurasDB.auraY
    )
end

local function FinishAuraDragging()
    if not auraDragging then
        return
    end

    enlightenedAuraFrame:StopMovingOrSizing()
    auraDragging = false
    SaveAuraPosition()
end

local function SetAuraSize(percent, quiet)
    if percent < 25 or percent > 250 then
        PrintMessage("Enlightened aura size must be from 25 to 250%.")
        return
    end

    if type(NikiPriestAurasDB) ~= "table" then
        NikiPriestAurasDB = {}
    end

    NikiPriestAurasDB.auraScale = percent
    ApplyAuraDimensions()
    if enlightenedAuraFrame:IsShown() then
        UpdateEnlightenedAuraAnimation(0)
    end
    if not quiet then
        PrintMessage("Enlightened aura size set to " .. tostring(percent) .. "%.")
    end
end

local function SetAuraOpacity(percent, quiet)
    if percent < 0 or percent > 100 then
        PrintMessage("Enlightened aura opacity must be from 0 to 100%.")
        return
    end

    if type(NikiPriestAurasDB) ~= "table" then
        NikiPriestAurasDB = {}
    end

    NikiPriestAurasDB.auraAlpha = percent
    if enlightenedAuraFrame:IsShown() then
        UpdateEnlightenedAuraAnimation(0)
    end
    if not quiet then
        PrintMessage("Enlightened aura opacity set to " .. tostring(percent) .. "%.")
    end
end

local function SaveProcPosition()
    if type(NikiPriestAurasDB) ~= "table" then
        NikiPriestAurasDB = {}
    end

    local frameX, frameY = procFrame:GetCenter()
    local parentX, parentY = UIParent:GetCenter()
    if not frameX or not frameY or not parentX or not parentY then
        return
    end

    NikiPriestAurasDB.procX = frameX - parentX
    NikiPriestAurasDB.procY = frameY - parentY

    procFrame:ClearAllPoints()
    procFrame:SetPoint("CENTER", UIParent, "CENTER", NikiPriestAurasDB.procX, NikiPriestAurasDB.procY)
end

local function FinishProcDragging()
    if not procDragging then
        return
    end

    procFrame:StopMovingOrSizing()
    procDragging = false
    SaveProcPosition()
    if procPlacementMode then
        UpdateProcPlacementText()
    end
end

local function SetProcSize(percent, quiet)
    if percent < 10 or percent > 300 then
        PrintMessage("Searing Light size must be from 10 to 300%.")
        return
    end

    if type(NikiPriestAurasDB) ~= "table" then
        NikiPriestAurasDB = {}
    end

    NikiPriestAurasDB.procScale = percent
    ApplyProcDimensions(1)
    UpdateProcPlacementText()
    if procFrame:IsShown() then
        UpdateProcAnimation(0)
    end
    if not quiet then
        PrintMessage("Searing Light size set to " .. tostring(percent) .. "%.")
    end
end

local function SetProcOpacity(percent, quiet)
    if percent < 0 or percent > 100 then
        PrintMessage("Searing Light opacity must be from 0 to 100%.")
        return
    end

    if type(NikiPriestAurasDB) ~= "table" then
        NikiPriestAurasDB = {}
    end

    NikiPriestAurasDB.procAlpha = percent
    UpdateProcPlacementText()
    if procFrame:IsShown() then
        UpdateProcAnimation(0)
    end
    if not quiet then
        PrintMessage("Searing Light opacity set to " .. tostring(percent) .. "%.")
    end
end

local function SetProcAnimationSpeed(percent, quiet)
    if percent < 25 or percent > 300 then
        PrintMessage("Searing Light animation speed must be from 25 to 300%.")
        return
    end

    if type(NikiPriestAurasDB) ~= "table" then
        NikiPriestAurasDB = {}
    end

    NikiPriestAurasDB.procAnimationSpeed = percent
    if not quiet then
        PrintMessage("Searing Light animation speed set to " .. tostring(percent) .. "%.")
    end
end

local function SetProcPlacementMode(enabled)
    procPlacementMode = enabled and true or false

    if procPlacementMode then
        if placementMode then
            SetPlacementMode(false)
        end
        procTestUntil = nil
        procFrame:EnableMouse(true)
        procFrame:EnableMouseWheel(true)
        UpdateProcPlacementText()
        procPlacementText:Show()
        SetProcAlert(true)
        PrintMessage("Searing Light setup enabled. Drag it; use the wheel for size and Shift+wheel for opacity.")
    else
        if procDragging then
            FinishProcDragging()
        else
            procFrame:StopMovingOrSizing()
            SaveProcPosition()
        end
        procFrame:EnableMouse(false)
        procFrame:EnableMouseWheel(false)
        procPlacementText:Hide()
        SetProcAlert(false, true)
        UpdateReminders()
        PrintMessage("Searing Light position, size and opacity saved; the alert is click-through.")
    end
end

procFrame:SetScript("OnDragStart", function()
    if procPlacementMode or
       (settingsMode and settingsSelection == "proc") then
        procDragging = true
        procFrame:StartMoving()
    end
end)

procFrame:SetScript("OnDragStop", function()
    FinishProcDragging()
end)

procFrame:SetScript("OnMouseUp", function()
    FinishProcDragging()
end)

enlightenedAuraFrame:SetScript("OnDragStart", function()
    if settingsMode and settingsSelection == "aura" then
        auraDragging = true
        enlightenedAuraFrame:StartMoving()
    end
end)

enlightenedAuraFrame:SetScript("OnDragStop", function()
    FinishAuraDragging()
end)

enlightenedAuraFrame:SetScript("OnMouseUp", function()
    FinishAuraDragging()
end)

procFrame:SetScript("OnMouseWheel", function()
    if not procPlacementMode then
        return
    end

    if IsShiftKeyDown() then
        local currentAlpha = NikiPriestAurasDB.procAlpha or 85
        SetProcOpacity(math.max(0, math.min(100, currentAlpha + arg1 * 5)), true)
    else
        local currentScale = NikiPriestAurasDB.procScale or 100
        SetProcSize(math.max(10, math.min(300, currentScale + arg1 * 5)), true)
    end
end)

-- Standalone settings window opened with /npa set.
local settingsFrame = CreateFrame("Frame", "NikiPriestAurasSettingsFrame", UIParent)
settingsFrame:SetWidth(335)
settingsFrame:SetHeight(420)
settingsFrame:SetPoint("CENTER", UIParent, "CENTER", 330, 0)
settingsFrame:SetFrameStrata("DIALOG")
settingsFrame:SetFrameLevel(50)
settingsFrame:SetMovable(true)
settingsFrame:SetClampedToScreen(true)
settingsFrame:EnableMouse(true)
settingsFrame:RegisterForDrag("LeftButton")
settingsFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 32,
    insets = { left = 10, right = 10, top = 10, bottom = 10 }
})
settingsFrame:SetBackdropColor(0.03, 0.04, 0.08, 0.96)

settingsFrame.title = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
settingsFrame.title:SetPoint("TOP", settingsFrame, "TOP", 0, -18)
settingsFrame.title:SetText("NikiPriestAuras")
settingsFrame.title:SetTextColor(1, 0.82, 0.20)

settingsFrame.selectionSection = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
settingsFrame.selectionSection:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", 28, -52)
settingsFrame.selectionSection:SetText(L.configure)
settingsFrame.selectionSection:SetTextColor(0.65, 0.84, 1.00)

local SelectSettingsObject
local refreshingSettingsControls = false
local selectionButtons = {}

local function CreateSelectionButton(name, label, key, x)
    local button = CreateFrame("CheckButton", name, settingsFrame, "UICheckButtonTemplate")
    button:SetWidth(22)
    button:SetHeight(22)
    button:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", x, -67)
    button.selectionKey = key

    local buttonLabel = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    buttonLabel:SetPoint("LEFT", button, "RIGHT", 1, 0)
    buttonLabel:SetText(label)
    buttonLabel:SetTextColor(0.82, 0.90, 1.00)
    button.label = buttonLabel

    button:SetScript("OnClick", function()
        if SelectSettingsObject then
            SelectSettingsObject(this.selectionKey)
        end
    end)
    selectionButtons[key] = button
    return button
end

CreateSelectionButton("NikiPriestAurasSelectIcons", L.icons, "icons", 24)
CreateSelectionButton("NikiPriestAurasSelectAura", L.aura, "aura", 121)
CreateSelectionButton("NikiPriestAurasSelectProc", L.proc, "proc", 215)

settingsFrame.selectedObjectLabel = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
settingsFrame.selectedObjectLabel:SetPoint("TOP", settingsFrame, "TOP", 0, -101)
settingsFrame.selectedObjectLabel:SetTextColor(1.00, 0.82, 0.20)

local shieldEnabledCheckbox = CreateFrame(
    "CheckButton",
    "NikiPriestAurasShieldEnabledCheckbox",
    settingsFrame,
    "UICheckButtonTemplate"
)
shieldEnabledCheckbox:SetWidth(22)
shieldEnabledCheckbox:SetHeight(22)
shieldEnabledCheckbox:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", 184, -274)

shieldEnabledCheckbox.label = shieldEnabledCheckbox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
shieldEnabledCheckbox.label:SetPoint("LEFT", shieldEnabledCheckbox, "RIGHT", 1, 0)
shieldEnabledCheckbox.label:SetText(L.shieldWhileAttacked)
shieldEnabledCheckbox.label:SetTextColor(0.82, 0.90, 1.00)

shieldEnabledCheckbox:SetScript("OnClick", function()
    if type(NikiPriestAurasDB) ~= "table" then
        NikiPriestAurasDB = {}
    end
    NikiPriestAurasDB.shieldEnabled = this:GetChecked() and true or false
    shieldBlinking = false
    UpdateReminders()
end)

local originalTexturesCheckbox = CreateFrame(
    "CheckButton",
    "NikiPriestAurasOriginalTexturesCheckbox",
    settingsFrame,
    "UICheckButtonTemplate"
)
originalTexturesCheckbox:SetWidth(22)
originalTexturesCheckbox:SetHeight(22)
originalTexturesCheckbox:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", 25, -274)

originalTexturesCheckbox.label = originalTexturesCheckbox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
originalTexturesCheckbox.label:SetPoint("LEFT", originalTexturesCheckbox, "RIGHT", 1, 0)
originalTexturesCheckbox.label:SetText(L.originalIcons)
originalTexturesCheckbox.label:SetTextColor(0.82, 0.90, 1.00)

originalTexturesCheckbox:SetScript("OnClick", function()
    if type(NikiPriestAurasDB) ~= "table" then
        NikiPriestAurasDB = {}
    end
    NikiPriestAurasDB.originalReminderTextures =
        this:GetChecked() and true or false
    ApplyReminderTextureStyle()
    UpdateReminders()
end)

settingsFrame.shieldFrameSection = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
settingsFrame.shieldFrameSection:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", 28, -307)
settingsFrame.shieldFrameSection:SetText(L.shieldFrame)
settingsFrame.shieldFrameSection:SetTextColor(0.65, 0.84, 1.00)

local shieldFrameButtons = {}

local function SelectShieldFrameMode(mode)
    if type(NikiPriestAurasDB) ~= "table" then
        NikiPriestAurasDB = {}
    end
    if mode ~= "blizzard" then
        mode = "pfui"
    end
    NikiPriestAurasDB.shieldFrameMode = mode

    shieldFrameButtons.pfui:SetChecked(mode == "pfui" and 1 or nil)
    shieldFrameButtons.blizzard:SetChecked(mode == "blizzard" and 1 or nil)

    if type(NikiPriestAuras_UpdateShieldDisplay) == "function" then
        NikiPriestAuras_UpdateShieldDisplay()
    end
end

local function CreateShieldFrameButton(name, label, mode, x)
    local button = CreateFrame("CheckButton", name, settingsFrame, "UICheckButtonTemplate")
    button:SetWidth(22)
    button:SetHeight(22)
    button:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", x, -322)
    button.shieldFrameMode = mode

    local buttonLabel = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    buttonLabel:SetPoint("LEFT", button, "RIGHT", 1, 0)
    buttonLabel:SetText(label)
    buttonLabel:SetTextColor(0.82, 0.90, 1.00)

    button:SetScript("OnClick", function()
        SelectShieldFrameMode(this.shieldFrameMode)
    end)
    shieldFrameButtons[mode] = button
end

CreateShieldFrameButton(
    "NikiPriestAurasShieldFramePfUI",
    L.shieldFramePfUI,
    "pfui",
    25
)
CreateShieldFrameButton(
    "NikiPriestAurasShieldFrameBlizzard",
    L.shieldFrameBlizzard,
    "blizzard",
    175
)

local function CreateSettingsSlider(name, label, y, minimum, maximum, callback, suffix)
    local slider = CreateFrame("Slider", name, settingsFrame, "OptionsSliderTemplate")
    slider:SetPoint("TOP", settingsFrame, "TOP", 0, y)
    slider:SetWidth(235)
    slider:SetHeight(18)
    slider:SetMinMaxValues(minimum, maximum)
    slider:SetValueStep(1)
    slider.labelText = label
    slider.valueSuffix = suffix or "%"

    local low = getglobal(name .. "Low")
    local high = getglobal(name .. "High")
    if low then low:SetText(tostring(minimum) .. slider.valueSuffix) end
    if high then high:SetText(tostring(maximum) .. slider.valueSuffix) end

    slider:SetScript("OnValueChanged", function()
        local value = math.floor(this:GetValue() + 0.5)
        local text = getglobal(name .. "Text")
        if text then
            text:SetText(label .. ": " .. tostring(value) .. slider.valueSuffix)
        end
        callback(value)
    end)

    return slider
end

local sharedSizeSlider = CreateSettingsSlider(
    "NikiPriestAurasSharedSizeSlider",
    L.size,
    -135,
    10,
    300,
    function(value)
        if refreshingSettingsControls then return end
        if settingsSelection == "icons" then
            SetIconSize(value, true)
        elseif settingsSelection == "aura" then
            SetAuraSize(value, true)
        else
            SetProcSize(value, true)
        end
    end
)

local sharedAlphaSlider = CreateSettingsSlider(
    "NikiPriestAurasSharedAlphaSlider",
    L.opacity,
    -185,
    0,
    100,
    function(value)
        if refreshingSettingsControls then return end
        if settingsSelection == "icons" then
            SetOpacity(value, true)
        elseif settingsSelection == "aura" then
            SetAuraOpacity(value, true)
        else
            SetProcOpacity(value, true)
        end
    end
)

local iconSpacingSlider = CreateSettingsSlider(
    "NikiPriestAurasIconSpacingSlider",
    L.iconSpacing,
    -235,
    0,
    100,
    function(value)
        if not refreshingSettingsControls then
            SetIconSpacing(value, true)
        end
    end,
    L.pixels
)

local procAnimationSpeedSlider = CreateSettingsSlider(
    "NikiPriestAurasProcAnimationSpeedSlider",
    L.animationSpeed,
    -235,
    25,
    300,
    function(value)
        if not refreshingSettingsControls then
            SetProcAnimationSpeed(value, true)
        end
    end
)

local auraEnabledCheckbox = CreateFrame(
    "CheckButton",
    "NikiPriestAurasEnlightenedAuraEnabledCheckbox",
    settingsFrame,
    "UICheckButtonTemplate"
)
auraEnabledCheckbox:SetWidth(22)
auraEnabledCheckbox:SetHeight(22)
auraEnabledCheckbox:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", 45, -229)

auraEnabledCheckbox.label = auraEnabledCheckbox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
auraEnabledCheckbox.label:SetPoint("LEFT", auraEnabledCheckbox, "RIGHT", 1, 0)
auraEnabledCheckbox.label:SetText(L.enlightenedAuraEnabled)
auraEnabledCheckbox.label:SetTextColor(0.82, 0.90, 1.00)

auraEnabledCheckbox:SetScript("OnClick", function()
    if type(NikiPriestAurasDB) ~= "table" then
        NikiPriestAurasDB = {}
    end
    NikiPriestAurasDB.enlightenedAuraEnabled =
        this:GetChecked() and true or false
    UpdateReminders()
end)

settingsFrame.hint = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
settingsFrame.hint:SetPoint("BOTTOM", settingsFrame, "BOTTOM", 0, 45)
settingsFrame.hint:SetText(L.dragHint)
settingsFrame.hint:SetTextColor(0.75, 0.75, 0.75)

settingsFrame.closeButton = CreateFrame("Button", "NikiPriestAurasSettingsClose", settingsFrame, "UIPanelButtonTemplate")
settingsFrame.closeButton:SetWidth(135)
settingsFrame.closeButton:SetHeight(24)
settingsFrame.closeButton:SetPoint("BOTTOM", settingsFrame, "BOTTOM", 0, 14)
settingsFrame.closeButton:SetText(L.lock)
settingsFrame.closeButton:SetScript("OnClick", function()
    settingsFrame:Hide()
end)

settingsFrame.closeX = CreateFrame("Button", "NikiPriestAurasSettingsCloseX", settingsFrame, "UIPanelCloseButton")
settingsFrame.closeX:SetPoint("TOPRIGHT", settingsFrame, "TOPRIGHT", -4, -4)
settingsFrame.closeX:SetScript("OnClick", function()
    settingsFrame:Hide()
end)

local function SetSliderRange(slider, name, minimum, maximum)
    slider:SetMinMaxValues(minimum, maximum)
    local low = getglobal(name .. "Low")
    local high = getglobal(name .. "High")
    if low then low:SetText(tostring(minimum) .. "%") end
    if high then high:SetText(tostring(maximum) .. "%") end
end

local function RefreshSettingsControls()
    if type(NikiPriestAurasDB) ~= "table" then
        return
    end

    refreshingSettingsControls = true
    local key, button
    for key, button in pairs(selectionButtons) do
        button:SetChecked(key == settingsSelection and 1 or nil)
        if key == settingsSelection then
            button.label:SetTextColor(1.00, 0.82, 0.20)
        else
            button.label:SetTextColor(0.82, 0.90, 1.00)
        end
    end

    local size = 100
    local alpha = 100
    if settingsSelection == "icons" then
        settingsFrame.selectedObjectLabel:SetText(L.selectedIcons)
        SetSliderRange(sharedSizeSlider, "NikiPriestAurasSharedSizeSlider", 50, 200)
        size = NikiPriestAurasDB.iconScale or 100
        alpha = NikiPriestAurasDB.alpha or 100
    elseif settingsSelection == "aura" then
        settingsFrame.selectedObjectLabel:SetText(L.selectedAura)
        SetSliderRange(sharedSizeSlider, "NikiPriestAurasSharedSizeSlider", 25, 250)
        size = NikiPriestAurasDB.auraScale or 100
        alpha = NikiPriestAurasDB.auraAlpha or 100
    else
        settingsFrame.selectedObjectLabel:SetText(L.selectedProc)
        SetSliderRange(sharedSizeSlider, "NikiPriestAurasSharedSizeSlider", 10, 300)
        size = NikiPriestAurasDB.procScale or 100
        alpha = NikiPriestAurasDB.procAlpha or 85
    end
    sharedSizeSlider:SetValue(size)
    sharedAlphaSlider:SetValue(alpha)
    iconSpacingSlider:SetValue(NikiPriestAurasDB.iconSpacing or ICON_GAP)

    shieldEnabledCheckbox:SetChecked(NikiPriestAurasDB.shieldEnabled and 1 or nil)
    local shieldFrameMode = NikiPriestAurasDB.shieldFrameMode or "pfui"
    shieldFrameButtons.pfui:SetChecked(shieldFrameMode == "pfui" and 1 or nil)
    shieldFrameButtons.blizzard:SetChecked(shieldFrameMode == "blizzard" and 1 or nil)
    originalTexturesCheckbox:SetChecked(
        NikiPriestAurasDB.originalReminderTextures and 1 or nil
    )
    auraEnabledCheckbox:SetChecked(
        NikiPriestAurasDB.enlightenedAuraEnabled ~= false and 1 or nil
    )
    procAnimationSpeedSlider:SetValue(NikiPriestAurasDB.procAnimationSpeed or 100)
    if settingsSelection == "icons" then
        iconSpacingSlider:Show()
    else
        iconSpacingSlider:Hide()
    end
    if settingsSelection == "proc" then
        procAnimationSpeedSlider:Show()
    else
        procAnimationSpeedSlider:Hide()
    end
    if settingsSelection == "aura" then
        auraEnabledCheckbox:Show()
    else
        auraEnabledCheckbox:Hide()
    end
    refreshingSettingsControls = false
end

local function RestoreConfiguredObjectPositions()
    if type(NikiPriestAurasDB) ~= "table" then
        return
    end

    anchor:ClearAllPoints()
    anchor:SetPoint(
        "CENTER", UIParent, "CENTER",
        NikiPriestAurasDB.x or 0,
        NikiPriestAurasDB.y or 0
    )
    procFrame:ClearAllPoints()
    procFrame:SetPoint(
        "CENTER", UIParent, "CENTER",
        NikiPriestAurasDB.procX or 0,
        NikiPriestAurasDB.procY or 155
    )
    enlightenedAuraFrame:ClearAllPoints()
    enlightenedAuraFrame:SetPoint(
        "CENTER", UIParent, "CENTER",
        NikiPriestAurasDB.auraX or 0,
        NikiPriestAurasDB.auraY or 0
    )
end

local function SetSettingsObjectsUnlocked(enabled)
    local index
    for index = 1, table.getn(reminderIcons) do
        -- The parent anchor owns dragging in this mode; child mouse capture
        -- is disabled so releasing the button cannot be lost between frames.
        reminderIcons[index]:EnableMouse(false)
    end

    anchor:EnableMouse(enabled and settingsSelection == "icons")
    procFrame:EnableMouse(enabled and settingsSelection == "proc")
    enlightenedAuraFrame:EnableMouse(enabled and settingsSelection == "aura")
    procFrame:EnableMouseWheel(false)

    if not enabled then
        if iconDragging then
            FinishIconDragging()
        else
            anchor:StopMovingOrSizing()
        end
        if procDragging then
            FinishProcDragging()
        else
            procFrame:StopMovingOrSizing()
        end
        if auraDragging then
            FinishAuraDragging()
        else
            enlightenedAuraFrame:StopMovingOrSizing()
        end

        -- Opening the settings window temporarily lays out every reminder and
        -- can make a clamped frame shift when its width changes. Do not treat
        -- that automatic shift as a user drag. Restore the last saved centers;
        -- a completed real drag has already updated these values above.
        RestoreConfiguredObjectPositions()
    end
end

SelectSettingsObject = function(selection)
    if selection ~= "icons" and selection ~= "aura" and selection ~= "proc" then
        selection = "icons"
    end

    if selection ~= settingsSelection then
        SetSettingsObjectsUnlocked(false)
        settingsSelection = selection
    end
    RefreshSettingsControls()
    SetSettingsObjectsUnlocked(true)
    UpdateReminders()
    RestoreConfiguredObjectPositions()
end

settingsFrame:SetScript("OnDragStart", function()
    settingsFrame:StartMoving()
end)

settingsFrame:SetScript("OnDragStop", function()
    settingsFrame:StopMovingOrSizing()
end)

settingsFrame:SetScript("OnShow", function()
    settingsMode = true
    if placementMode then
        SetPlacementMode(false)
    end
    if procPlacementMode then
        SetProcPlacementMode(false)
    end
    SetSettingsObjectsUnlocked(true)
    RefreshSettingsControls()
    UpdateReminders()

    -- Refreshing sliders and showing all sample icons must not move the
    -- configured centers merely because /npa set was opened.
    RestoreConfiguredObjectPositions()
end)

settingsFrame:SetScript("OnHide", function()
    SetProcAlert(false, true)
    settingsMode = false
    SetSettingsObjectsUnlocked(false)
    placementText:Hide()
    procPlacementText:Hide()
    ApplyConfiguredAlpha()
    UpdateReminders()
end)

settingsFrame:Hide()
table.insert(UISpecialFrames, "NikiPriestAurasSettingsFrame")

local function OpenSettingsFrame()
    if not settingsFrame:IsShown() then
        settingsFrame:Show()
    end
end

SLASH_NIKIPRIESTAURAS1 = "/npa"
SlashCmdList["NIKIPRIESTAURAS"] = function(message)
    local command = string.lower(message or "")
    command = string.gsub(command, "^%s+", "")
    command = string.gsub(command, "%s+$", "")

    if command == "set" then
        OpenSettingsFrame()
    elseif command == "reset" then
        ResetPosition()
    elseif command == "test" then
        procTestUntil = GetTime() + 10
        SetProcAlert(true)
        PrintMessage("Searing Light alert test enabled for 10 seconds.")
    elseif command == "show" then
        if type(NikiPriestAurasDB) ~= "table" then
            NikiPriestAurasDB = {}
        end
        NikiPriestAurasDB.addonEnabled = true
        UpdateReminders()
        if type(NikiPriestAuras_UpdateShieldDisplay) == "function" then
            NikiPriestAuras_UpdateShieldDisplay()
        end
        PrintMessage(L.addonShown)
    elseif command == "hide" then
        if type(NikiPriestAurasDB) ~= "table" then
            NikiPriestAurasDB = {}
        end
        NikiPriestAurasDB.addonEnabled = false
        procTestUntil = nil
        enlightenedTestUntil = nil
        if settingsFrame:IsShown() then
            settingsFrame:Hide()
        end
        HideReminders()
        if type(NikiPriestAuras_UpdateShieldDisplay) == "function" then
            NikiPriestAuras_UpdateShieldDisplay()
        end
        PrintMessage(L.addonHidden)
    else
        PrintMessage(L.commands)
    end
end

anchor:RegisterEvent("VARIABLES_LOADED")
anchor:RegisterEvent("PLAYER_ENTERING_WORLD")
anchor:RegisterEvent("PLAYER_TARGET_CHANGED")
anchor:RegisterEvent("PLAYER_REGEN_DISABLED")
anchor:RegisterEvent("PLAYER_REGEN_ENABLED")
anchor:RegisterEvent("PLAYER_DEAD")
anchor:RegisterEvent("PLAYER_ALIVE")
anchor:RegisterEvent("PLAYER_CONTROL_LOST")
anchor:RegisterEvent("PLAYER_CONTROL_GAINED")
anchor:RegisterEvent("UNIT_AURA")
anchor:RegisterEvent("PLAYER_AURAS_CHANGED")
anchor:RegisterEvent("UNIT_FACTION")
anchor:RegisterEvent("UNIT_HEALTH")
anchor:RegisterEvent("SPELLS_CHANGED")
anchor:RegisterEvent("LEARNED_SPELL_IN_TAB")
anchor:RegisterEvent("CHARACTER_POINTS_CHANGED")
anchor:RegisterEvent("PARTY_MEMBERS_CHANGED")
anchor:RegisterEvent("RAID_ROSTER_UPDATE")
anchor:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS")
anchor:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES")
anchor:RegisterEvent("CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE")

anchor:SetScript("OnEvent", function()
    if event == "VARIABLES_LOADED" then
        InitializeDatabase()
        RefreshTrackedBuffSpellState()
    elseif event == "SPELLS_CHANGED" or
           event == "LEARNED_SPELL_IN_TAB" or
           event == "CHARACTER_POINTS_CHANGED" then
        RefreshTrackedBuffSpellState()
    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
    elseif event == "CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS" or
           event == "CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES" or
           event == "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE" then
        lastIncomingCreatureAttack = GetTime()
    elseif event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_DEAD" then
        inCombat = false
        lastIncomingCreatureAttack = nil
    elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_ALIVE" then
        inCombat = UnitAffectingCombat("player") and true or false
        lastIncomingCreatureAttack = nil
        RefreshTrackedBuffSpellState()
    elseif event == "UNIT_AURA" then
        local auraUnit = arg1 or ""
        local isGroupUnit = string.sub(auraUnit, 1, 5) == "party" or
                            string.sub(auraUnit, 1, 4) == "raid"
        if auraUnit ~= "target" and auraUnit ~= "player" and
           not (enlightenKnown and isGroupUnit) then
            return
        end
    elseif (event == "UNIT_FACTION" or event == "UNIT_HEALTH") and arg1 ~= "target" then
        return
    end

    UpdateReminders()
end)

-- UNIT_AURA is normally enough, but polling keeps the reminder reliable with
-- old Vanilla unit-frame event behavior and custom Turtle WoW auras.
anchor:SetScript("OnUpdate", function()
    -- Derive elapsed time from the game clock instead of trusting the global
    -- Vanilla arg1 value. Some injected client extensions overwrite arg1
    -- during movement-related callbacks, freezing time-based UI animation.
    local now = GetTime()
    local elapsed = tonumber(arg1) or 0
    if animationLastUpdateTime then
        local clockElapsed = now - animationLastUpdateTime
        if clockElapsed >= 0 and clockElapsed <= 0.50 then
            elapsed = clockElapsed
        end
    end
    animationLastUpdateTime = now

    UpdateProcAnimation(elapsed)
    UpdateEnlightenedAuraAnimation(elapsed)
    UpdateShieldBlink()

    -- PLAYER_CONTROL_LOST/GAINED normally fires for taxi travel. Polling the
    -- state as well keeps this reliable on older Turtle/Vanilla client builds.
    local onTaxi = PlayerIsOnTaxi()
    if onTaxi then
        if not wasOnTaxi then
            wasOnTaxi = true
            HideReminders()
        end
        return
    elseif wasOnTaxi then
        wasOnTaxi = false
        UpdateReminders()
    end

    if procTestUntil and GetTime() >= procTestUntil then
        procTestUntil = nil
        UpdateReminders()
    end
    if enlightenedTestUntil and GetTime() >= enlightenedTestUntil then
        enlightenedTestUntil = nil
        UpdateReminders()
    end

    -- Searing Light gets its own fast poll because some Turtle 1.18 aura
    -- updates arrive later than the standard Vanilla UNIT_AURA event.
    if not settingsMode and not placementMode and not procPlacementMode then
        procUpdateElapsed = procUpdateElapsed + elapsed
        if procUpdateElapsed >= PROC_UPDATE_INTERVAL and
           (inCombat or procFrame:IsShown() or enlightenedAuraFrame:IsShown() or
            procTestUntil or enlightenedTestUntil) then
            procUpdateElapsed = 0

            local showProc = false
            local showEnlightened = false
            local _, playerClass = UnitClass("player")
            if playerClass == "PRIEST" and not UnitIsDeadOrGhost("player") then
                showProc = PlayerHasSearingLightProc()
                local enlightenedTimeLeft
                showEnlightened, enlightenedTimeLeft = PlayerHasEnlightenedBuff()
                if procTestUntil and GetTime() < procTestUntil then
                    showProc = true
                end
                if enlightenedTestUntil and GetTime() < enlightenedTestUntil then
                    showEnlightened = true
                    enlightenedTimeLeft = enlightenedTestUntil - GetTime()
                end
                SetEnlightenedAura(showEnlightened, enlightenedTimeLeft)
            else
                SetEnlightenedAura(false)
            end
            SetProcAlert(showProc)
        end
    end

    if not inCombat and not procFrame:IsShown() and not enlightenedAuraFrame:IsShown() then
        return
    end

    updateElapsed = updateElapsed + elapsed
    if updateElapsed >= UPDATE_INTERVAL then
        updateElapsed = 0
        UpdateReminders()
    end
end)

HideReminders()

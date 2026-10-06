local _, PH = ...

local UI = PH.UI
local Colors = UI.Colors

local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local UnitFactionGroup = UnitFactionGroup
local IsPlayerSpell = IsPlayerSpell
local C_Spell_GetSpellCooldown = C_Spell.GetSpellCooldown
local C_Spell_GetSpellName = C_Spell.GetSpellName
local C_Timer_After = C_Timer.After
local C_Timer_NewTicker = C_Timer.NewTicker
local GetTime = GetTime
local C_Item_GetItemCooldown = C_Item.GetItemCooldown
local C_Item_GetItemInfoInstant = C_Item.GetItemInfoInstant
local GameTooltip = GameTooltip
local ipairs = ipairs
local max, min, floor = math.max, math.min, math.floor
local format = string.format
local unpack = unpack

local ROW_HEIGHT = 36
local ROW_SPACING = 42
local ICON_SIZE = 32
local ICON_ZOOM = 0.08
local GCD_THRESHOLD = 1.5
local COOLDOWN_THROTTLE = 0.5
local MAX_RECENTS = 10
local FALLBACK_SPELL_ICON = 136243
local ICON_BORDER_BACKDROP = { edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 }
local STAR_PATH = [[Interface\AddOns\PortalHub\Media\favorite_star]]
local NEW_TAG = "  |cff19ff19NEW|r"

PH.ROW_SPACING = ROW_SPACING
PH.ICON_SIZE = ICON_SIZE
PH.ICON_ZOOM = ICON_ZOOM
PH.ICON_BORDER_BACKDROP = ICON_BORDER_BACKDROP
PH.STAR_PATH = STAR_PATH
PH.FALLBACK_SPELL_ICON = FALLBACK_SPELL_ICON

function PH.SelectSpellID(entry)
    if entry.spellIDs then
        local fallback
        for _, id in ipairs(entry.spellIDs) do
            if IsPlayerSpell(id) then return id end
            if not fallback and C_Spell_GetSpellName(id) then fallback = id end
        end
        return fallback or entry.spellIDs[1]
    end
    if entry.spellIDAlliance or entry.spellIDHorde then
        local faction = UnitFactionGroup("player")
        if faction == "Alliance" then return entry.spellIDAlliance end
        if faction == "Horde" then return entry.spellIDHorde end
    end
    return entry.spellID
end

function PH.IsKnown(spellID)
    return spellID and IsPlayerSpell(spellID) or false
end

function PH.SpellExists(spellID)
    return (spellID and C_Spell_GetSpellName(spellID) ~= nil) or false
end

function PH.EntryAvailable(entry)
    return PH.SpellExists(PH.SelectSpellID(entry))
end

function PH.ResolveCurrentSeason()
    local data = PH.DungeonPortalData
    if data.expansions["Current Season"] then return end

    local currentIndex = #data.seasons
    for i, season in ipairs(data.seasons) do
        if not season.gateSpellID or PH.SpellExists(season.gateSpellID) then
            currentIndex = i
            break
        end
    end
    data.expansions["Current Season"] = data.seasons[currentIndex].dungeons

    local insertAt = 2
    for i = currentIndex + 1, #data.seasons do
        local season = data.seasons[i]
        data.expansions[season.name] = season.dungeons
        table.insert(data.expansionOrder, insertAt, season.name)
        insertAt = insertAt + 1
    end
end

function PH.GetItemIcon(itemID)
    local _, _, _, _, icon = C_Item_GetItemInfoInstant(itemID)
    return icon or 134400
end

function PH.SafeSetAttr(frame, key, value)
    if not InCombatLockdown() then
        frame:SetAttribute(key, value)
    end
end

function PH.IsFavorite(id)
    return PortalHubDB.favorites[id] or false
end

function PH.ToggleFavorite(id)
    if PortalHubDB.favorites[id] then
        PortalHubDB.favorites[id] = nil
    else
        PortalHubDB.favorites[id] = true
    end
end

function PH.LabelText(id, name)
    if PH.NewEntries[id] and not PortalHubDB.usedNew[id] then
        return name .. NEW_TAG
    end
    return name
end

function PH.RecordUse(id, name, action, tab)
    if PH.NewEntries[id] then PortalHubDB.usedNew[id] = true end
    local recents = PortalHubDB.recents
    for i = #recents, 1, -1 do
        if recents[i].id == id then table.remove(recents, i) end
    end
    table.insert(recents, 1, { id = id, name = name, action = action, tab = tab })
    for i = #recents, MAX_RECENTS + 1, -1 do recents[i] = nil end
end

local function FormatCooldownText(start, duration)
    local remaining = (start + duration) - GetTime()
    if remaining <= 0 then return "" end
    if remaining >= 3600 then
        return format("%dh %dm", floor(remaining / 3600), floor((remaining % 3600) / 60))
    elseif remaining >= 60 then
        return format("%dm %ds", floor(remaining / 60), floor(remaining % 60))
    end
    return format("%ds", floor(remaining))
end

local function ApplyCooldownTime(cooldownFrame, start, duration, timerText)
    if duration > GCD_THRESHOLD then
        cooldownFrame:SetCooldown(start, duration)
        if timerText then timerText:SetText(FormatCooldownText(start, duration)) end
    else
        cooldownFrame:Clear()
        if timerText then timerText:SetText("") end
    end
end

function PH.ApplyCooldown(cooldownFrame, spellID)
    local info = C_Spell_GetSpellCooldown(spellID)
    ApplyCooldownTime(cooldownFrame, info.startTime, info.duration)
end

function PH.ApplyItemCooldown(row)
    local start, duration = C_Item_GetItemCooldown(row._itemID)
    ApplyCooldownTime(row._cooldown, start, duration, row._timerText)
end

function PH.SetRowAvailable(row, isAvailable)
    if isAvailable then
        row._iconTex:SetDesaturated(false)
        row._iconTex:SetAlpha(1)
        row._label:SetTextColor(unpack(Colors.text.primary))
    else
        row._iconTex:SetDesaturated(true)
        row._iconTex:SetAlpha(0.4)
        row._label:SetTextColor(unpack(Colors.text.disabled))
        row._cooldown:Clear()
        row._timerText:SetText("")
        if row._star then row._star:Hide() end
        PH.SafeSetAttr(row, "type", nil)
    end
end

function PH.FinishScrollLayout(scrollChild, scroll, updateThumb, lastY)
    scrollChild:SetHeight(max(1, -lastY + 8))
    scroll:SetVerticalScroll(0)
    updateThumb()
end

function PH.SortFavoritesFirst(list)
    table.sort(list, function(a, b)
        local aFav = PH.IsFavorite(a._entryID)
        local bFav = PH.IsFavorite(b._entryID)
        if aFav ~= bFav then return aFav end
        return a._name < b._name
    end)
end

function PH.LayoutRows(rows, scrollChild, scroll, updateThumb, searchQuery)
    local isSearching = searchQuery and searchQuery ~= ""
    local y = 0
    for _, row in ipairs(rows) do
        local match = not isSearching or row._name:lower():find(searchQuery, 1, true)
        if match then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, y)
            row:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, y)
            row:Show()
            y = y - ROW_SPACING
        else
            row:Hide()
        end
    end
    scrollChild:SetHeight(max(1, -y + 8))
    scroll:SetVerticalScroll(0)
    C_Timer_After(0.01, updateThumb)
end

function PH.SetupRowBase(parent)
    local row = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
    row:SetHeight(ROW_HEIGHT)

    local hoverBg = row:CreateTexture(nil, "BACKGROUND")
    hoverBg:SetAllPoints()
    hoverBg:SetColorTexture(1, 1, 1, 0)
    row._hoverBg = hoverBg

    return row
end

function PH.CreateRowPool(scrollChild, createRow)
    local pool = {}
    local used = 0

    local function Acquire()
        used = used + 1
        local row = pool[used]
        if row then
            row:Show()
            return row
        end
        row = createRow(scrollChild)
        pool[used] = row
        return row
    end

    local function ReleaseAll()
        for i = 1, used do
            pool[i]:Hide()
            pool[i]:ClearAllPoints()
        end
        used = 0
    end

    return { Acquire = Acquire, ReleaseAll = ReleaseAll, pool = pool }
end

function PH.SetupItemRow(scrollChild)
    local row = PH.SetupRowBase(scrollChild)

    row._iconTex = row:CreateTexture(nil, "ARTWORK")
    row._iconTex:SetSize(ICON_SIZE, ICON_SIZE)
    row._iconTex:SetPoint("LEFT", 6, 0)
    row._iconTex:SetTexCoord(ICON_ZOOM, 1 - ICON_ZOOM, ICON_ZOOM, 1 - ICON_ZOOM)

    local border = CreateFrame("Frame", nil, row, "BackdropTemplate")
    border:SetPoint("TOPLEFT", row._iconTex, -1, 1)
    border:SetPoint("BOTTOMRIGHT", row._iconTex, 1, -1)
    border:SetBackdrop(ICON_BORDER_BACKDROP)
    border:SetBackdropBorderColor(0, 0, 0, 1)

    row._cooldown = CreateFrame("Cooldown", nil, row, "CooldownFrameTemplate")
    row._cooldown:SetAllPoints(row._iconTex)
    row._cooldown:SetDrawEdge(false)
    row._cooldown:SetDrawSwipe(true)
    row._cooldown:SetHideCountdownNumbers(false)

    C_Timer_After(0, function()
        local countdown = row._cooldown:GetCountdownFontString()
        countdown:ClearAllPoints()
        countdown:SetPoint("CENTER", row._cooldown, "CENTER", 0, 0)
        countdown:SetFont(UI.Font, 12, "OUTLINE")
    end)

    row._label = row:CreateFontString(nil, "OVERLAY")
    row._label:SetFont(UI.Font, 13, "")
    row._label:SetPoint("LEFT", row._iconTex, "RIGHT", 12, 0)
    row._label:SetPoint("RIGHT", row, "RIGHT", -80, 0)
    row._label:SetJustifyH("LEFT")

    row._timerText = row:CreateFontString(nil, "OVERLAY")
    row._timerText:SetFont(UI.Font, 11, "")
    row._timerText:SetPoint("RIGHT", row, "RIGHT", -36, 0)
    row._timerText:SetJustifyH("RIGHT")
    row._timerText:SetTextColor(unpack(Colors.text.muted))

    return row
end

local function ApplyStarColor(star)
    local tex = star:GetNormalTexture()
    if PH.IsFavorite(star._entryID) then
        tex:SetVertexColor(1, 0.82, 0, 1)
    else
        tex:SetVertexColor(0.3, 0.3, 0.3, 0.5)
    end
end

local function StarOnClick(self)
    PH.ToggleFavorite(self._entryID)
    ApplyStarColor(self)
    if self._relayout then self._relayout() end
end

local function StarOnEnter(self)
    if not PH.IsFavorite(self._entryID) then
        self:GetNormalTexture():SetVertexColor(1, 0.82, 0, 0.6)
    end
end

function PH.SetupFavButton(row, entryID, relayoutFn)
    local star = row._star
    if not star then
        star = CreateFrame("Button", nil, row)
        star:SetSize(16, 16)
        star:SetPoint("RIGHT", -8, 0)
        star:SetNormalTexture(STAR_PATH)
        star:SetFrameLevel(row:GetFrameLevel() + 5)
        star:SetScript("OnClick", StarOnClick)
        star:SetScript("OnEnter", StarOnEnter)
        star:SetScript("OnLeave", ApplyStarColor)
        row._star = star
    end
    star:Show()
    star._entryID = entryID
    star._relayout = relayoutFn
    ApplyStarColor(star)
end

function PH.BindHoverScripts(row)
    row:SetScript("OnEnter", function(self)
        local kind = self._tooltipKind
        if not kind then return end
        self._hoverBg:SetColorTexture(1, 1, 1, 0.04)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if kind == "spell" then
            GameTooltip:SetSpellByID(self._tooltipID)
        elseif kind == "toy" then
            GameTooltip:SetToyByItemID(self._tooltipID)
        elseif kind == "item" then
            GameTooltip:SetItemByID(self._tooltipID)
        end
        if self._showDualClickHint then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Left-click: Portal (Group)", 0.5, 1, 0.5)
            GameTooltip:AddLine("Right-click: Teleport (Solo)", 0.3, 0.8, 1)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(self)
        if self._tooltipKind then
            self._hoverBg:SetColorTexture(1, 1, 1, 0)
        end
        GameTooltip:Hide()
    end)
end

local CARD_ICON_SIZE = 36

local ROLE_ATLAS = {
    TANK    = "roleicon-tank",
    HEALER  = "roleicon-healer",
    DAMAGER = "roleicon-dps",
}

PH.KEYSTONE_CARD_HEIGHT = 56
PH.KEYSTONE_CARD_GAP = 6
PH.NEUTRAL_CLASS_COLOR = { r = 0.7, g = 0.7, b = 0.7 }

local function GetScoreColor(score)
    if RaiderIO and RaiderIO.GetScoreColor then
        local r, g, b = RaiderIO.GetScoreColor(score)
        if r then return r, g, b end
    end
    local color = C_ChallengeMode.GetDungeonScoreRarityColor(score)
    if color then return color.r, color.g, color.b end
end

function PH.CreateKeystoneCard(parent)
    local card = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate, BackdropTemplate")
    card:SetHeight(PH.KEYSTONE_CARD_HEIGHT)
    card:SetBackdrop(UI.BACKDROP)
    card:SetBackdropColor(unpack(Colors.bg.light))
    card:SetBackdropBorderColor(unpack(Colors.border.dark))

    local hoverBg = card:CreateTexture(nil, "BORDER")
    hoverBg:SetPoint("TOPLEFT", 1, -1)
    hoverBg:SetPoint("BOTTOMRIGHT", -1, 1)
    hoverBg:SetColorTexture(1, 1, 1, 0)
    card._hoverBg = hoverBg

    local dungeonIcon = card:CreateTexture(nil, "ARTWORK")
    dungeonIcon:SetSize(CARD_ICON_SIZE, CARD_ICON_SIZE)
    dungeonIcon:SetPoint("LEFT", 10, 0)
    dungeonIcon:SetTexCoord(ICON_ZOOM, 1 - ICON_ZOOM, ICON_ZOOM, 1 - ICON_ZOOM)
    card._dungeonIcon = dungeonIcon

    local iconBorder = CreateFrame("Frame", nil, card, "BackdropTemplate")
    iconBorder:SetPoint("TOPLEFT", dungeonIcon, -1, 1)
    iconBorder:SetPoint("BOTTOMRIGHT", dungeonIcon, 1, -1)
    iconBorder:SetBackdrop(ICON_BORDER_BACKDROP)
    iconBorder:SetBackdropBorderColor(0, 0, 0, 0.8)
    card._iconBorder = iconBorder

    local roleIcon = card:CreateTexture(nil, "OVERLAY")
    roleIcon:SetSize(14, 14)
    roleIcon:SetPoint("BOTTOMRIGHT", dungeonIcon, 4, -4)
    card._roleIcon = roleIcon

    local textAnchor = CreateFrame("Frame", nil, card)
    textAnchor:SetSize(1, 1)
    textAnchor:SetPoint("LEFT", dungeonIcon, "RIGHT", 10, 0)
    card._textAnchor = textAnchor

    local nameLabel = card:CreateFontString(nil, "OVERLAY")
    nameLabel:SetFont(UI.Font, 13, "")
    nameLabel:SetPoint("BOTTOMLEFT", textAnchor, "LEFT", 0, 1)
    nameLabel:SetPoint("RIGHT", card, "RIGHT", -75, 0)
    nameLabel:SetJustifyH("LEFT")
    nameLabel:SetWordWrap(false)
    card._nameLabel = nameLabel

    local dungeonLabel = card:CreateFontString(nil, "OVERLAY")
    dungeonLabel:SetFont(UI.Font, 11, "")
    dungeonLabel:SetPoint("TOPLEFT", textAnchor, "LEFT", 0, -1)
    dungeonLabel:SetJustifyH("LEFT")
    dungeonLabel:SetWordWrap(false)
    card._dungeonLabel = dungeonLabel

    local ratingAnchor = CreateFrame("Frame", nil, card)
    ratingAnchor:SetSize(1, 1)
    ratingAnchor:SetPoint("RIGHT", -30, 0)

    local ratingHeader = card:CreateFontString(nil, "OVERLAY")
    ratingHeader:SetFont(UI.Font, 9, "")
    ratingHeader:SetPoint("BOTTOM", ratingAnchor, "TOP", 0, 0)
    ratingHeader:SetJustifyH("CENTER")
    ratingHeader:SetTextColor(unpack(Colors.text.disabled))
    ratingHeader:SetText("IO")

    local ratingText = card:CreateFontString(nil, "OVERLAY")
    ratingText:SetFont(UI.Font, 13, "")
    ratingText:SetPoint("TOP", ratingAnchor, "BOTTOM", 0, 0)
    ratingText:SetJustifyH("CENTER")
    card._ratingText = ratingText

    local accentLine = card:CreateTexture(nil, "OVERLAY")
    accentLine:SetWidth(2)
    accentLine:SetPoint("TOPLEFT", 1, -1)
    accentLine:SetPoint("BOTTOMLEFT", 1, 1)
    accentLine:Hide()
    card._accentLine = accentLine

    return card
end

function PH.PopulateKeystoneCard(card, info)
    local hasPortal = (info.portalSpellID and IsPlayerSpell(info.portalSpellID)) or false
    card._info = info
    card._hasPortal = hasPortal

    if info.portalSpellID then
        card._dungeonIcon:SetTexture(C_Spell.GetSpellTexture(info.portalSpellID) or FALLBACK_SPELL_ICON)
        card._dungeonIcon:SetDesaturated(not hasPortal)
        card._dungeonIcon:SetAlpha(hasPortal and 1 or 0.5)
        card._dungeonIcon:Show()
        card._iconBorder:Show()
    else
        card._dungeonIcon:Hide()
        card._iconBorder:Hide()
    end

    local atlas = info.role and ROLE_ATLAS[info.role]
    if atlas then
        card._roleIcon:SetAtlas(atlas)
        card._roleIcon:Show()
    else
        card._roleIcon:Hide()
    end

    if hasPortal then
        card._accentLine:SetColorTexture(UI.GetAccent())
        card._accentLine:Show()
    else
        card._accentLine:Hide()
    end

    if info.keystoneName and info.keystoneLevel then
        card._dungeonLabel:SetText(format("+%d %s", info.keystoneLevel, info.keystoneName))
        card._dungeonLabel:SetTextColor(unpack(Colors.text.secondary))
    else
        card._dungeonLabel:SetText("No key")
        card._dungeonLabel:SetTextColor(unpack(Colors.text.disabled))
    end

    card._textAnchor:ClearAllPoints()
    if info.portalSpellID then
        card._textAnchor:SetPoint("LEFT", card._dungeonIcon, "RIGHT", 10, 0)
    else
        card._textAnchor:SetPoint("LEFT", card, "LEFT", 12, 0)
    end

    local score = info.rating
    card._ratingText:SetText(format("%d", score))
    if score > 0 then
        local r, g, b = GetScoreColor(score)
        if r then
            card._ratingText:SetTextColor(r, g, b)
        else
            card._ratingText:SetTextColor(unpack(Colors.text.primary))
        end
    else
        card._ratingText:SetTextColor(unpack(Colors.text.disabled))
    end

    return hasPortal
end

local FLASH_DURATION = 0.35
local FLASH_PEAK = 0.22

local function FlashOnUpdate(self)
    local t = (GetTime() - self._flashStart) / FLASH_DURATION
    local bg = self._hoverBg
    if t >= 1 then
        self:SetScript("OnUpdate", nil)
        bg:SetColorTexture(1, 1, 1, self:IsMouseOver() and 0.04 or 0)
        return
    end
    local fade = (1 - t) * (1 - t)
    bg:SetColorTexture(self._flashR, self._flashG, self._flashB, FLASH_PEAK * fade)
end

function PH.FlashRow(row)
    UI.CastTracker.MarkPending(row)
    row._flashR, row._flashG, row._flashB = UI.GetAccent()
    row._flashStart = GetTime()
    row:SetScript("OnUpdate", FlashOnUpdate)
end

function PH.CreateScrollArea(parent)
    local SCROLLBAR_WIDTH = 6
    local THUMB_MIN_HEIGHT = 30
    local SCROLLBAR_BACKDROP = { bgFile = "Interface\\Buttons\\WHITE8x8" }

    local wrapper = CreateFrame("Frame", nil, parent)
    wrapper:SetAllPoints()

    local scroll = CreateFrame("ScrollFrame", nil, wrapper)
    scroll:SetPoint("TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", -(SCROLLBAR_WIDTH + 4), 0)
    scroll:EnableMouse(true)
    scroll:EnableMouseWheel(true)

    local child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(1)
    child:SetHeight(1)
    scroll:SetScrollChild(child)

    local function SyncWidth()
        if InCombatLockdown() then return end
        local w = scroll:GetWidth()
        if w > 0 then child:SetWidth(w) end
    end
    C_Timer_After(0, SyncWidth)
    scroll:HookScript("OnSizeChanged", SyncWidth)

    local track = CreateFrame("Frame", nil, wrapper, "BackdropTemplate")
    track:SetWidth(SCROLLBAR_WIDTH)
    track:SetPoint("TOPRIGHT", 0, 0)
    track:SetPoint("BOTTOMRIGHT", 0, 0)
    track:SetBackdrop(SCROLLBAR_BACKDROP)
    track:SetBackdropColor(1, 1, 1, 0.03)

    local thumb = CreateFrame("Frame", nil, track, "BackdropTemplate")
    thumb:SetWidth(SCROLLBAR_WIDTH)
    thumb:SetHeight(THUMB_MIN_HEIGHT)
    thumb:SetBackdrop(SCROLLBAR_BACKDROP)
    thumb:SetBackdropColor(1, 1, 1, 0.15)
    thumb:SetPoint("TOP", track, "TOP", 0, 0)
    thumb:EnableMouse(true)
    thumb:SetMovable(true)

    thumb:SetScript("OnEnter", function(self) self:SetBackdropColor(1, 1, 1, 0.3) end)
    thumb:SetScript("OnLeave", function(self)
        if not self:GetScript("OnUpdate") then
            self:SetBackdropColor(1, 1, 1, 0.15)
        end
    end)

    local dragStartY, dragStartScroll = 0, 0

    local function DragOnUpdate(self)
        local currentY = select(2, GetCursorPosition()) / self:GetEffectiveScale()
        local delta = dragStartY - currentY
        local maxScroll = scroll:GetVerticalScrollRange()
        if maxScroll <= 0 then return end
        local thumbRange = track:GetHeight() - thumb:GetHeight()
        if thumbRange <= 0 then return end
        local scrollDelta = (delta / thumbRange) * maxScroll
        scroll:SetVerticalScroll(max(0, min(maxScroll, dragStartScroll + scrollDelta)))
    end

    thumb:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        dragStartY = select(2, GetCursorPosition()) / self:GetEffectiveScale()
        dragStartScroll = scroll:GetVerticalScroll()
        self:SetBackdropColor(1, 1, 1, 0.4)
        self:SetScript("OnUpdate", DragOnUpdate)
    end)

    thumb:SetScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil)
        if self:IsMouseOver() then
            self:SetBackdropColor(1, 1, 1, 0.3)
        else
            self:SetBackdropColor(1, 1, 1, 0.15)
        end
    end)

    scroll:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll()
        local maxScroll = self:GetVerticalScrollRange()
        local step = ROW_SPACING * 3
        self:SetVerticalScroll(max(0, min(maxScroll, current - (delta * step))))
    end)

    local function UpdateThumb()
        local maxScroll = scroll:GetVerticalScrollRange()
        if maxScroll <= 0 then
            thumb:Hide()
            return
        end
        thumb:Show()
        local trackH = track:GetHeight()
        local visibleRatio = scroll:GetHeight() / (scroll:GetHeight() + maxScroll)
        local thumbH = max(THUMB_MIN_HEIGHT, trackH * visibleRatio)
        thumb:SetHeight(thumbH)
        local thumbRange = trackH - thumbH
        local thumbPos = (scroll:GetVerticalScroll() / maxScroll) * thumbRange
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", track, "TOP", 0, -thumbPos)
    end

    scroll:SetScript("OnVerticalScroll", UpdateThumb)
    scroll:SetScript("OnScrollRangeChanged", UpdateThumb)
    C_Timer_After(0.05, UpdateThumb)

    return scroll, child, UpdateThumb
end

local function RemoveFromList(list, pool)
    local lookup = {}
    for i = 1, #pool do lookup[pool[i]] = true end
    local writeIndex = 0
    for i = 1, #list do
        if not lookup[list[i]] then
            writeIndex = writeIndex + 1
            list[writeIndex] = list[i]
        end
    end
    for i = writeIndex + 1, #list do list[i] = nil end
end

function PH.Throttle(delay, fn)
    local pending = false
    return function()
        if pending then return end
        pending = true
        C_Timer_After(delay, function()
            pending = false
            fn()
        end)
    end
end

local spellRows = {}

local function RefreshSpellCooldowns()
    for i = 1, #spellRows do
        local row = spellRows[i]
        if row:IsShown() and row._spellID then
            PH.ApplyCooldown(row._cooldown, row._spellID)
        end
    end
end

local spellTickFrame = CreateFrame("Frame")
spellTickFrame:SetScript("OnEvent", PH.Throttle(COOLDOWN_THROTTLE, RefreshSpellCooldowns))

function PH.TrackRow(row)
    spellRows[#spellRows + 1] = row
end

function PH.UntrackSpellRows(pool)
    RemoveFromList(spellRows, pool)
end

function PH.StartTracking()
    spellTickFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    RefreshSpellCooldowns()
end

function PH.StopTracking()
    spellTickFrame:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
end

local itemRows = {}

local function RefreshItemCooldowns()
    for i = 1, #itemRows do
        local row = itemRows[i]
        if row:IsShown() and row._itemID then
            PH.ApplyItemCooldown(row)
        end
    end
end

local itemTickFrame = CreateFrame("Frame")
itemTickFrame:SetScript("OnEvent", PH.Throttle(COOLDOWN_THROTTLE, RefreshItemCooldowns))

function PH.RegisterItemCooldownRows(rows)
    for i = 1, #rows do
        itemRows[#itemRows + 1] = rows[i]
    end
end

function PH.UnregisterItemCooldownRows(pool)
    RemoveFromList(itemRows, pool)
end

local itemTicker

function PH.StartItemTracking()
    itemTickFrame:RegisterEvent("BAG_UPDATE_COOLDOWN")
    itemTickFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    itemTicker = itemTicker or C_Timer_NewTicker(1, RefreshItemCooldowns)
    RefreshItemCooldowns()
end

function PH.StopItemTracking()
    itemTickFrame:UnregisterEvent("BAG_UPDATE_COOLDOWN")
    itemTickFrame:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    if itemTicker then
        itemTicker:Cancel()
        itemTicker = nil
    end
end

local function BuildListedSet()
    local set = {}
    for _, toy in ipairs(PH.TransmogToys) do set[toy.id] = true end
    for _, toy in ipairs(PH.HearthToys) do set[toy.id] = true end
    for _, item in ipairs(PH.HearthItems) do set[item.id] = true end
    for id in pairs(PortalHubDB.customToys) do set[id] = true end
    for id in pairs(PortalHubDB.customHearths) do set[id] = true end
    return set
end

function PH.CreateAddToyButton(parent, tooltipText, onClick)
    local addButton = CreateFrame("Button", nil, parent)
    addButton:SetSize(28, 28)

    local bg = addButton:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, 0.06)

    local label = addButton:CreateFontString(nil, "OVERLAY")
    label:SetFont(UI.Font, 16, "")
    label:SetPoint("CENTER", 0, 1)
    label:SetText("+")
    label:SetTextColor(unpack(Colors.text.muted))

    addButton:SetScript("OnEnter", function(self)
        bg:SetColorTexture(1, 1, 1, 0.12)
        label:SetTextColor(unpack(Colors.text.primary))
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(tooltipText)
        GameTooltip:Show()
    end)
    addButton:SetScript("OnLeave", function()
        bg:SetColorTexture(1, 1, 1, 0.06)
        label:SetTextColor(unpack(Colors.text.muted))
        GameTooltip:Hide()
    end)
    addButton:SetScript("OnClick", onClick)
    return addButton
end

function PH.SetupToyRemoveButton(row, toyID, store, refreshFn)
    if not row._removeBtn then
        local btn = CreateFrame("Button", nil, row)
        btn:SetSize(16, 16)
        btn:SetPoint("RIGHT", row, "RIGHT", -56, 0)
        btn:SetFrameLevel(row:GetFrameLevel() + 5)
        local label = btn:CreateFontString(nil, "OVERLAY")
        label:SetFont(UI.Font, 13, "OUTLINE")
        label:SetPoint("CENTER", 0, 0)
        label:SetText("x")
        label:SetTextColor(0.5, 0.5, 0.5, 0.8)
        btn._text = label
        btn:SetScript("OnEnter", function(self)
            self._text:SetTextColor(1, 0.3, 0.3, 1)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Remove custom toy", 1, 0.3, 0.3)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function(self)
            self._text:SetTextColor(0.5, 0.5, 0.5, 0.8)
            GameTooltip:Hide()
        end)
        row._removeBtn = btn
    end

    local btn = row._removeBtn
    btn:Show()
    btn:SetScript("OnClick", function()
        store[toyID] = nil
        PortalHubDB.favorites[toyID] = nil
        refreshFn()
    end)
end

function PH.BuildToyAddOverlay(parent, store, refreshFn)
    local Controls = UI.Controls

    local overlay = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    overlay:SetAllPoints()
    overlay:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    overlay:SetBackdropColor(0.02, 0.02, 0.02, 1)
    overlay:SetFrameLevel(parent:GetFrameLevel() + 50)
    overlay:Hide()

    local hint = overlay:CreateFontString(nil, "OVERLAY")
    hint:SetFont(UI.Font, 11, "")
    hint:SetPoint("TOPLEFT", 4, -8)
    hint:SetPoint("TOPRIGHT", -20, -8)
    hint:SetText("Search your toys by name or paste an item ID.")
    hint:SetTextColor(unpack(Colors.text.muted))
    hint:SetJustifyH("LEFT")

    local closeButton = Controls.CloseButton(overlay, 16, function()
        overlay:Hide()
        refreshFn()
    end)
    closeButton:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", -2, -4)

    local searchInput = CreateFrame("EditBox", nil, overlay, "BackdropTemplate")
    searchInput:SetPoint("TOPLEFT", overlay, "TOPLEFT", 4, -46)
    searchInput:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", -4, -46)
    searchInput:SetHeight(28)
    searchInput:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    searchInput:SetBackdropColor(0, 0, 0, 0.3)
    searchInput:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.5)
    searchInput:SetFont(UI.Font, 12, "")
    searchInput:SetTextColor(unpack(Colors.text.primary))
    searchInput:SetTextInsets(8, 8, 0, 0)
    searchInput:SetAutoFocus(false)
    searchInput:SetMaxLetters(200)

    local placeholder = searchInput:CreateFontString(nil, "OVERLAY")
    placeholder:SetFont(UI.Font, 12, "")
    placeholder:SetPoint("LEFT", 8, 0)
    placeholder:SetText("Toy name or item ID...")
    placeholder:SetTextColor(unpack(Colors.text.muted))

    searchInput:SetScript("OnEditFocusGained", function() placeholder:Hide() end)
    searchInput:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then placeholder:Show() end
    end)
    searchInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local resultArea = CreateFrame("Frame", nil, overlay)
    resultArea:SetPoint("TOPLEFT", searchInput, "BOTTOMLEFT", 0, -8)
    resultArea:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", 0, 0)

    local resultScroll, resultChild, resultUpdateThumb = PH.CreateScrollArea(resultArea)

    local function CreateResultRow(rowParent)
        local row = CreateFrame("Button", nil, rowParent)
        row:SetHeight(32)

        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, 0)
        row._bg = bg

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(24, 24)
        icon:SetPoint("LEFT", 6, 0)
        icon:SetTexCoord(ICON_ZOOM, 1 - ICON_ZOOM, ICON_ZOOM, 1 - ICON_ZOOM)
        row._icon = icon

        local label = row:CreateFontString(nil, "OVERLAY")
        label:SetFont(UI.Font, 12, "")
        label:SetPoint("LEFT", icon, "RIGHT", 8, 0)
        label:SetPoint("RIGHT", row, "RIGHT", -60, 0)
        label:SetJustifyH("LEFT")
        label:SetTextColor(unpack(Colors.text.primary))
        row._label = label

        local addLabel = row:CreateFontString(nil, "OVERLAY")
        addLabel:SetFont(UI.Font, 11, "")
        addLabel:SetPoint("RIGHT", -8, 0)
        addLabel:SetJustifyH("RIGHT")
        addLabel:SetText("|cff00cc00Add|r")
        row._addLabel = addLabel

        row:SetScript("OnEnter", function(self)
            self._bg:SetColorTexture(1, 1, 1, 0.04)
            if not self._listed then self._addLabel:SetText("|cff00ff00Add|r") end
            if self._toyID then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetToyByItemID(self._toyID)
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function(self)
            self._bg:SetColorTexture(1, 1, 1, 0)
            self._addLabel:SetText(self._listed and "|cff666666Listed|r" or "|cff00cc00Add|r")
            GameTooltip:Hide()
        end)

        return row
    end

    local resultPool = PH.CreateRowPool(resultChild, CreateResultRow)

    local statusText = resultChild:CreateFontString(nil, "OVERLAY")
    statusText:SetFont(UI.Font, 12, "")
    statusText:SetPoint("TOP", 0, -20)
    statusText:SetTextColor(unpack(Colors.text.muted))
    statusText:SetJustifyH("CENTER")
    statusText:Hide()

    local function SearchToys(text)
        resultPool.ReleaseAll()
        statusText:Hide()

        if text == "" then
            resultChild:SetHeight(1)
            resultUpdateThumb()
            return
        end

        local linkID = string.match(text, "item:(%d+)")
        if linkID then text = linkID end

        local listed = BuildListedSet()
        local asNumber = tonumber(text)
        local results = {}

        if asNumber then
            if listed[asNumber] then
                statusText:SetText("This toy is already in your list.")
                statusText:Show()
            elseif PlayerHasToy(asNumber) then
                local _, name, icon = C_ToyBox.GetToyInfo(asNumber)
                if name then
                    results[#results + 1] = { id = asNumber, name = name, icon = icon }
                end
            else
                local _, name = C_ToyBox.GetToyInfo(asNumber)
                statusText:SetText(name and "You don't own this toy." or "No toy found with that ID.")
                statusText:Show()
            end
        else
            local query = text:lower()
            for i = 1, C_ToyBox.GetNumToys() do
                local itemID = C_ToyBox.GetToyFromIndex(i)
                if itemID and itemID > 0 and PlayerHasToy(itemID) then
                    local _, name, icon = C_ToyBox.GetToyInfo(itemID)
                    if name and name:lower():find(query, 1, true) then
                        results[#results + 1] = { id = itemID, name = name, icon = icon, listed = listed[itemID] }
                    end
                end
                if #results >= 50 then break end
            end
            table.sort(results, function(a, b) return a.name < b.name end)
        end

        if #results == 0 and not statusText:IsShown() then
            statusText:SetText("No matching toys found.")
            statusText:Show()
        end

        local y = 0
        for _, toy in ipairs(results) do
            local row = resultPool.Acquire()
            row._icon:SetTexture(toy.icon or PH.GetItemIcon(toy.id))
            row._label:SetText(toy.name)
            row._toyID = toy.id
            row._listed = toy.listed
            row._addLabel:SetText(toy.listed and "|cff666666Listed|r" or "|cff00cc00Add|r")
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", resultChild, "TOPLEFT", 0, y)
            row:SetPoint("TOPRIGHT", resultChild, "TOPRIGHT", 0, y)
            row:SetScript("OnClick", function()
                if toy.listed then return end
                store[toy.id] = { id = toy.id, name = toy.name }
                SearchToys(searchInput:GetText())
            end)
            y = y - 36
        end

        PH.FinishScrollLayout(resultChild, resultScroll, resultUpdateThumb, y)
    end

    local QueueSearch = PH.Throttle(0.3, function() SearchToys(searchInput:GetText()) end)

    searchInput:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        if self:GetText() == "" then placeholder:Show() else placeholder:Hide() end
        QueueSearch()
    end)

    searchInput:SetScript("OnEnterPressed", function(self) SearchToys(self:GetText()) end)

    overlay:SetScript("OnShow", function()
        searchInput:SetText("")
        placeholder:Show()
        resultPool.ReleaseAll()
        statusText:Hide()
        resultChild:SetHeight(1)
        C_Timer_After(0.05, function() searchInput:SetFocus() end)
    end)

    return overlay
end

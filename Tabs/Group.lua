local _, PH = ...

local UI = PH.UI
local Colors = UI.Colors
local Controls = UI.Controls

local CreateFrame = CreateFrame
local UnitExists = UnitExists
local UnitName = UnitName
local UnitClass = UnitClass
local UnitIsConnected = UnitIsConnected
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local UnitIsUnit = UnitIsUnit
local GetNumGroupMembers = GetNumGroupMembers
local IsInRaid = IsInRaid
local IsInGroup = IsInGroup
local InCombatLockdown = InCombatLockdown
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local GameTooltip = GameTooltip
local unpack = unpack
local ipairs = ipairs
local pairs = pairs

local ROLE_ORDER = { TANK = 1, HEALER = 2, DAMAGER = 3, NONE = 4 }

local portalLookup

local function BuildPortalLookup()
    portalLookup = {}
    local data = PH.DungeonPortalData
    for _, expName in ipairs(data.expansionOrder) do
        local dungeons = data.expansions[expName]
        if dungeons then
            for _, entry in ipairs(dungeons) do
                local spellID = PH.SelectSpellID(entry)
                local key = entry.name:lower()
                if spellID and PH.EntryAvailable(entry) and not portalLookup[key] then
                    portalLookup[key] = spellID
                end
            end
        end
    end
end

local function FindPortalSpell(dungeonName)
    if not portalLookup then BuildPortalLookup() end
    if not dungeonName then return nil end
    local low = dungeonName:lower()
    if portalLookup[low] then return portalLookup[low] end
    for portalName, spellID in pairs(portalLookup) do
        if low:find(portalName, 1, true) or portalName:find(low, 1, true) then
            return spellID
        end
    end
    return nil
end

local function GetRIOScore(unit)
    if RaiderIO and RaiderIO.GetProfile then
        local profile = RaiderIO.GetProfile(unit)
        if profile and profile.mythicKeystoneProfile then
            return profile.mythicKeystoneProfile.currentScore or 0
        end
    end
    return 0
end

PH.FindPortalSpell = FindPortalSpell

local partyKeystones = {}
PH._partyKeystones = partyKeystones

local LKS = LibStub("LibKeystone")

LKS.Register(PH, function(keyLevel, keyChallengeMapID, playerRating, sender, channel)
    if channel ~= "PARTY" then return end
    local name = sender and sender:match("^([^-]+)") or sender
    if not name then return end
    if keyLevel and keyLevel > 0 and keyChallengeMapID and keyChallengeMapID > 0 then
        partyKeystones[name] = {
            level = keyLevel,
            mapID = keyChallengeMapID,
            name = C_ChallengeMode.GetMapUIInfo(keyChallengeMapID),
            rating = playerRating,
        }
    else
        partyKeystones[name] = nil
    end
    if PH.GroupTab.ThrottledRefresh then
        PH.GroupTab.ThrottledRefresh()
    end
end)

PH.GroupTab = {}

local function GetGroupUnits()
    if not IsInGroup() then return { "player" } end
    local units = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do units[i] = "raid" .. i end
    else
        units[1] = "player"
        for i = 1, GetNumGroupMembers() - 1 do units[i + 1] = "party" .. i end
    end
    return units
end

local function GetMemberInfo(unit)
    local info = { unit = unit }
    info.name = UnitName(unit) or "?"
    info.connected = UnitIsConnected(unit)
    info.dead = UnitIsDeadOrGhost(unit)

    local _, classToken = UnitClass(unit)
    info.classColor = (classToken and RAID_CLASS_COLORS[classToken]) or PH.NEUTRAL_CLASS_COLOR
    info.role = UnitGroupRolesAssigned(unit) or "NONE"

    local rating = GetRIOScore(unit)
    if rating == 0 then
        local summary = C_PlayerInfo.GetPlayerMythicPlusRatingSummary(unit)
        rating = summary and summary.currentSeasonScore or 0
    end
    info.rating = rating

    if UnitIsUnit(unit, "player") then
        local ownedLevel = C_MythicPlus.GetOwnedKeystoneLevel()
        local ownedMapID = C_MythicPlus.GetOwnedKeystoneChallengeMapID()
        if ownedLevel and ownedMapID then
            info.keystoneName = C_ChallengeMode.GetMapUIInfo(ownedMapID)
            info.keystoneLevel = ownedLevel
        end
    else
        local keystone = partyKeystones[info.name]
        if keystone and keystone.level and keystone.level > 0 then
            info.keystoneName = keystone.name
            info.keystoneLevel = keystone.level
        end
    end

    if info.keystoneName then
        info.portalSpellID = FindPortalSpell(info.keystoneName)
    end

    return info
end

local SUBTAB_HEIGHT = 38

function PH.GroupTab.Build(parent)
    local partyView = CreateFrame("Frame", nil, parent)
    partyView:SetPoint("TOPLEFT", 0, -SUBTAB_HEIGHT)
    partyView:SetPoint("BOTTOMRIGHT", 0, 0)

    local altsView = CreateFrame("Frame", nil, parent)
    altsView:SetPoint("TOPLEFT", 0, -SUBTAB_HEIGHT)
    altsView:SetPoint("BOTTOMRIGHT", 0, 0)
    altsView:Hide()

    PH.AltsTab.Build(altsView)

    local emptyLabel = partyView:CreateFontString(nil, "OVERLAY")
    emptyLabel:SetFont(UI.Font, 13, "")
    emptyLabel:SetPoint("CENTER", 0, 20)
    emptyLabel:SetTextColor(unpack(Colors.text.muted))
    emptyLabel:SetText("Join a group to see party members here.")

    local rioWarning = partyView:CreateFontString(nil, "OVERLAY")
    rioWarning:SetFont(UI.Font, 10, "")
    rioWarning:SetPoint("BOTTOMLEFT", 0, 2)
    rioWarning:SetTextColor(unpack(Colors.text.disabled))

    local scrollArea = CreateFrame("Frame", nil, partyView)
    scrollArea:SetPoint("TOPLEFT", 0, 0)
    scrollArea:SetPoint("BOTTOMRIGHT", 0, 16)

    local scroll, scrollChild, updateThumb = PH.CreateScrollArea(scrollArea)

    local function CardOnEnter(self)
        self:SetBackdropBorderColor(unpack(Colors.border.light))
        local info = self._info
        if not info then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetUnit(info.unit)
        if self._hasPortal then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Click to teleport", 0.5, 1, 0.5)
        elseif info.portalSpellID then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Portal not learned", 1, 0.5, 0.5)
        end
        GameTooltip:Show()
    end

    local function CardOnLeave(self)
        self:SetBackdropBorderColor(unpack(Colors.border.dark))
        if self._hoverBg then self._hoverBg:SetColorTexture(1, 1, 1, 0) end
        GameTooltip:Hide()
    end

    local function CardPostClick(self)
        if self._hasPortal then PH.FlashRow(self) end
    end

    local function CreateCard(cardParent)
        local card = PH.CreateKeystoneCard(cardParent)
        card:RegisterForClicks("LeftButtonDown")
        card:SetScript("OnEnter", CardOnEnter)
        card:SetScript("OnLeave", CardOnLeave)
        card:SetScript("PostClick", CardPostClick)
        return card
    end

    local cardPool = PH.CreateRowPool(scrollChild, CreateCard)

    local function PopulateCard(card, info)
        local hasPortal = PH.PopulateKeystoneCard(card, info)

        local nameText = info.name
        if not info.connected then
            nameText = nameText .. "  |cffff4444offline|r"
        elseif info.dead then
            nameText = nameText .. "  |cffff8800dead|r"
        end
        card._nameLabel:SetText(nameText)
        card._nameLabel:SetTextColor(info.classColor.r, info.classColor.g, info.classColor.b)

        if hasPortal then
            PH.SafeSetAttr(card, "type", "spell")
            PH.SafeSetAttr(card, "unit", "player")
            PH.SafeSetAttr(card, "spell", info.portalSpellID)
        else
            PH.SafeSetAttr(card, "type", nil)
            PH.SafeSetAttr(card, "spell", nil)
        end
    end

    local function Refresh()
        if InCombatLockdown() then return end
        cardPool.ReleaseAll()

        local hasRIO = RaiderIO and RaiderIO.GetProfile
        rioWarning:SetText(hasRIO and "" or "Install RaiderIO for full M+ data")

        local infos = {}
        for _, unit in ipairs(GetGroupUnits()) do
            if UnitExists(unit) then
                infos[#infos + 1] = GetMemberInfo(unit)
            end
        end

        table.sort(infos, function(a, b)
            local orderA = ROLE_ORDER[a.role] or 4
            local orderB = ROLE_ORDER[b.role] or 4
            if orderA ~= orderB then return orderA < orderB end
            return a.name < b.name
        end)

        local hasMembers = #infos > 0
        emptyLabel:SetShown(not hasMembers)
        scrollArea:SetShown(hasMembers)

        local y = 0
        for _, info in ipairs(infos) do
            local card = cardPool.Acquire()
            PopulateCard(card, info)
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, y)
            card:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, y)
            y = y - (PH.KEYSTONE_CARD_HEIGHT + PH.KEYSTONE_CARD_GAP)
        end

        PH.FinishScrollLayout(scrollChild, scroll, updateThumb, y)
    end

    local ThrottledRefresh = PH.Throttle(0.3, function()
        if partyView:IsVisible() then Refresh() end
    end)

    local RequestKeystones = PH.Throttle(1, function()
        if IsInGroup() then LKS.Request("PARTY") end
    end)

    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("PLAYER_ROLES_ASSIGNED")
    eventFrame:RegisterEvent("ROLE_CHANGED_INFORM")
    eventFrame:RegisterEvent("UNIT_CONNECTION")
    eventFrame:RegisterEvent("PARTY_MEMBER_ENABLE")
    eventFrame:RegisterEvent("PARTY_MEMBER_DISABLE")
    eventFrame:SetScript("OnEvent", function(_, event)
        if event == "GROUP_ROSTER_UPDATE" then RequestKeystones() end
        ThrottledRefresh()
    end)

    local function RefreshActive()
        if altsView:IsShown() then
            PH.AltsTab.Refresh()
        else
            Refresh()
        end
    end

    local dropdown = Controls.Dropdown(parent, nil, { "Party", "Alts" }, "Party", function(val)
        if val == "Alts" then
            partyView:Hide()
            altsView:Show()
        else
            altsView:Hide()
            partyView:Show()
        end
    end, nil, 120)
    dropdown:SetPoint("TOPLEFT", 0, -2)

    partyView:SetScript("OnShow", function()
        if not InCombatLockdown() then Refresh() end
    end)
    altsView:SetScript("OnShow", function()
        if not InCombatLockdown() then PH.AltsTab.Refresh() end
    end)

    PH.GroupTab.Refresh = RefreshActive
    PH.GroupTab.ThrottledRefresh = ThrottledRefresh
    PH.GroupTab.RequestKeystones = RequestKeystones
end

local _, PH = ...

local UI = PH.UI
local Colors = UI.Colors

local CreateFrame = CreateFrame
local UnitName = UnitName
local UnitClass = UnitClass
local GetRealmName = GetRealmName
local InCombatLockdown = InCombatLockdown
local IsControlKeyDown = IsControlKeyDown
local GetServerTime = GetServerTime
local C_MythicPlus = C_MythicPlus
local C_ChallengeMode = C_ChallengeMode
local C_PlayerInfo = C_PlayerInfo
local C_DateAndTime = C_DateAndTime
local C_Timer_After = C_Timer.After
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local GameTooltip = GameTooltip
local unpack = unpack
local ipairs = ipairs
local pairs = pairs
local format = string.format

PH.AltsTab = {}

local function CharKey()
    local name = UnitName("player")
    local realm = GetRealmName()
    return name .. "-" .. realm, name, realm
end

local function CaptureOwnKey()
    if not PortalHubDB then return end
    PortalHubDB.altKeys = PortalHubDB.altKeys or {}
    local key, name, realm = CharKey()
    local store = PortalHubDB.altKeys
    local entry = store[key] or {}

    local _, classToken = UnitClass("player")
    entry.name = name
    entry.realm = realm
    entry.class = classToken

    local summary = C_PlayerInfo.GetPlayerMythicPlusRatingSummary("player")
    entry.rating = (summary and summary.currentSeasonScore) or 0

    local level = C_MythicPlus.GetOwnedKeystoneLevel()
    local mapID = C_MythicPlus.GetOwnedKeystoneChallengeMapID()
    if level and level > 0 and mapID and mapID > 0 then
        entry.keyLevel = level
        entry.keyName = C_ChallengeMode.GetMapUIInfo(mapID)
        local resetIn = C_DateAndTime.GetSecondsUntilWeeklyReset()
        entry.keyReset = GetServerTime() + (resetIn or 0)
    else
        entry.keyLevel = nil
        entry.keyName = nil
        entry.keyReset = nil
    end

    store[key] = entry
end

local ThrottledCapture = PH.Throttle(1, CaptureOwnKey)

local captureFrame = CreateFrame("Frame")
captureFrame:RegisterEvent("PLAYER_LOGIN")
captureFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
captureFrame:RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE")
captureFrame:RegisterEvent("BAG_UPDATE_DELAYED")
captureFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        C_MythicPlus.RequestMapInfo()
        C_Timer_After(2, ThrottledCapture)
    else
        ThrottledCapture()
    end
end)

function PH.AltsTab.Build(parent)
    local emptyLabel = parent:CreateFontString(nil, "OVERLAY")
    emptyLabel:SetFont(UI.Font, 13, "")
    emptyLabel:SetPoint("CENTER", 0, 20)
    emptyLabel:SetTextColor(unpack(Colors.text.muted))
    emptyLabel:SetText("Log into your characters to record their keys.")

    local scrollArea = CreateFrame("Frame", nil, parent)
    scrollArea:SetPoint("TOPLEFT", 0, 0)
    scrollArea:SetPoint("BOTTOMRIGHT", 0, 0)

    local scroll, scrollChild, updateThumb = PH.CreateScrollArea(scrollArea)

    local function CardOnEnter(self)
        self:SetBackdropBorderColor(unpack(Colors.border.light))
        local info = self._info
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(info.displayName, info.classColor.r, info.classColor.g, info.classColor.b)
        if info.keystoneName and info.keystoneLevel then
            GameTooltip:AddLine(format("+%d %s", info.keystoneLevel, info.keystoneName), 0.9, 0.9, 0.9)
        else
            GameTooltip:AddLine("No key", 0.6, 0.6, 0.6)
        end
        if info.rating > 0 then
            GameTooltip:AddLine("Rating: " .. info.rating, 0.8, 0.8, 0.8)
        end
        if self._hasPortal then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Click to teleport", 0.5, 1, 0.5)
        elseif info.portalSpellID then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Portal not learned", 1, 0.5, 0.5)
        end
        if not info.isCurrent then
            GameTooltip:AddLine("Ctrl + right-click to remove", 0.5, 0.5, 0.5)
        end
        GameTooltip:Show()
    end

    local function CardOnLeave(self)
        self:SetBackdropBorderColor(unpack(Colors.border.dark))
        self._hoverBg:SetColorTexture(1, 1, 1, 0)
        GameTooltip:Hide()
    end

    local function CardPostClick(self, button)
        if button == "RightButton" then
            if IsControlKeyDown() and not self._isCurrent then
                PortalHubDB.altKeys[self._storeKey] = nil
                C_Timer_After(0, PH.AltsTab.Refresh)
            end
            return
        end
        if self._hasPortal then PH.FlashRow(self) end
    end

    local function CreateCard(cardParent)
        local card = PH.CreateKeystoneCard(cardParent)
        card:RegisterForClicks("LeftButtonDown", "RightButtonUp")
        card:SetScript("OnEnter", CardOnEnter)
        card:SetScript("OnLeave", CardOnLeave)
        card:SetScript("PostClick", CardPostClick)
        return card
    end

    local cardPool = PH.CreateRowPool(scrollChild, CreateCard)

    local function PopulateCard(card, info)
        local hasPortal = PH.PopulateKeystoneCard(card, info)
        card._storeKey = info.storeKey
        card._isCurrent = info.isCurrent

        local nameText = info.displayName
        if info.isCurrent then nameText = nameText .. "  |cff888888(you)|r" end
        card._nameLabel:SetText(nameText)
        card._nameLabel:SetTextColor(info.classColor.r, info.classColor.g, info.classColor.b)

        if hasPortal then
            PH.SafeSetAttr(card, "type1", "spell")
            PH.SafeSetAttr(card, "unit1", "player")
            PH.SafeSetAttr(card, "spell1", info.portalSpellID)
        else
            PH.SafeSetAttr(card, "type1", nil)
            PH.SafeSetAttr(card, "spell1", nil)
        end
    end

    local function Refresh()
        if InCombatLockdown() then return end
        CaptureOwnKey()
        cardPool.ReleaseAll()

        local now = GetServerTime()
        local curKey = CharKey()
        local myRealm = GetRealmName()

        local list = {}
        for storeKey, e in pairs(PortalHubDB.altKeys) do
            local validKey = e.keyLevel and now < e.keyReset
            list[#list + 1] = {
                storeKey = storeKey,
                name = e.name,
                displayName = e.realm == myRealm and e.name or e.name .. "-" .. e.realm,
                classColor = RAID_CLASS_COLORS[e.class],
                rating = e.rating,
                keystoneName = validKey and e.keyName or nil,
                keystoneLevel = validKey and e.keyLevel or nil,
                portalSpellID = validKey and e.keyName and PH.FindPortalSpell(e.keyName) or nil,
                isCurrent = storeKey == curKey,
            }
        end

        table.sort(list, function(a, b)
            local ak = a.keystoneLevel or -1
            local bk = b.keystoneLevel or -1
            if ak ~= bk then return ak > bk end
            if a.rating ~= b.rating then return a.rating > b.rating end
            return a.name < b.name
        end)

        local hasAny = #list > 0
        emptyLabel:SetShown(not hasAny)
        scrollArea:SetShown(hasAny)

        local y = 0
        for _, info in ipairs(list) do
            local card = cardPool.Acquire()
            PopulateCard(card, info)
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, y)
            card:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, y)
            y = y - (PH.KEYSTONE_CARD_HEIGHT + PH.KEYSTONE_CARD_GAP)
        end

        PH.FinishScrollLayout(scrollChild, scroll, updateThumb, y)
    end

    PH.AltsTab.Refresh = Refresh
end

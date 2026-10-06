local _, PH = ...

local UI = PH.UI
local Controls = UI.Controls
local Colors = UI.Colors
local LDB = LibStub("LibDataBroker-1.1")
local LDBIcon = LibStub("LibDBIcon-1.0")

local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local UnitClass = UnitClass
local UnitName = UnitName
local C_Timer_After = C_Timer.After
local GetTime = GetTime
local SetBinding = SetBinding
local GetBindingKey = GetBindingKey
local SaveBindings = SaveBindings
local GetCurrentBindingSet = GetCurrentBindingSet
local GameTooltip = GameTooltip
local IsInGroup = IsInGroup
local IsInRaid = IsInRaid
local GetNumGroupMembers = GetNumGroupMembers
local SendChatMessage = SendChatMessage
local ipairs = ipairs
local pairs = pairs
local format = string.format

local HOUSING_SPELL_ID = 1233637
local PANEL_WIDTH = 500
local PANEL_HEIGHT = 620
local FADE_DURATION = 0.12

local panel
local isShown = false

local portalSpellNames = {}

local fadeFrame = CreateFrame("Frame")
local fadeShow, fadeStart

local function FadeOnUpdate()
    local progress = math.min((GetTime() - fadeStart) / FADE_DURATION, 1)
    local eased = 1 - (1 - progress) ^ 3
    panel:SetAlpha(fadeShow and eased or 1 - eased)
    if progress >= 1 then
        fadeFrame:SetScript("OnUpdate", nil)
        if not fadeShow then panel:Hide() end
    end
end

local function AnimatePanel(show)
    fadeShow = show
    fadeStart = GetTime()
    if show then panel:Show() end
    fadeFrame:SetScript("OnUpdate", FadeOnUpdate)
end

local function BuildHouseButton(parent, title)
    local button = CreateFrame("Button", "PortalHubHouseButton", parent, "SecureActionButtonTemplate")
    button:SetSize(20, 20)
    button:SetPoint("LEFT", title, "RIGHT", 4, 0)
    button:RegisterForClicks("LeftButtonUp")
    button:SetAttribute("useOnKeyDown", false)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetAtlas("homestone-minimap-icon-innerglow", false)
    icon:SetAlpha(0.85)

    local border = CreateFrame("Frame", nil, button, "BackdropTemplate")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetBackdrop(PH.ICON_BORDER_BACKDROP)
    border:SetBackdropBorderColor(0, 0, 0, 0)

    button:SetScript("OnEnter", function(self)
        icon:SetAlpha(1)
        border:SetBackdropBorderColor(unpack(Colors.border.light))
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetSpellByID(HOUSING_SPELL_ID)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Click to teleport home", 0.5, 1, 0.5)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        icon:SetAlpha(0.85)
        border:SetBackdropBorderColor(0, 0, 0, 0)
        GameTooltip:Hide()
    end)
    button:SetScript("PostClick", function(self)
        if self:GetAttribute("type") ~= "teleporthome" then return end
        PH.RecordUse(HOUSING_SPELL_ID, "Teleport Home", "spell", "housing")
    end)

    local pendingHouse
    local combatWatcher = CreateFrame("Frame")

    local function ApplyHouse(house)
        button:SetAttribute("type", nil)
        button:SetAttribute("house-neighborhood-guid", nil)
        button:SetAttribute("house-guid", nil)
        button:SetAttribute("house-plot-id", nil)
        if house and house.neighborhoodGUID and house.houseGUID and house.plotID then
            button:SetAttribute("type", "teleporthome")
            button:SetAttribute("house-neighborhood-guid", house.neighborhoodGUID)
            button:SetAttribute("house-guid", house.houseGUID)
            button:SetAttribute("house-plot-id", house.plotID)
        end
    end

    combatWatcher:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        if pendingHouse then
            ApplyHouse(pendingHouse)
            pendingHouse = nil
        end
    end)

    local function OnHouses(houses)
        local house = houses and houses[1]
        if InCombatLockdown() then
            pendingHouse = house
            combatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
        else
            ApplyHouse(house)
        end
    end

    EventUtil.RegisterOnceFrameEventAndCallback("PLAYER_HOUSE_LIST_UPDATED", OnHouses)
    C_Housing.GetPlayerOwnedHouses()
end

local function BuildTabDefs()
    local _, playerClass = UnitClass("player")
    local defs = {
        { key = "Portals", label = "Portals", module = PH.PortalsTab },
    }
    if playerClass == "MAGE" then
        defs[#defs + 1] = { key = "Mage", label = "Mage", module = PH.MageTab }
    end
    defs[#defs + 1] = { key = "Hearths", label = "Hearths", module = PH.HearthsTab }
    defs[#defs + 1] = {
        key = "Group", label = "M+", module = PH.GroupTab,
        onShow = function() PH.GroupTab.RequestKeystones() end,
    }
    defs[#defs + 1] = { key = "Transmog",  label = "Transmog",  module = PH.TransmogTab }
    defs[#defs + 1] = { key = "Favorites", label = "Favorites", module = PH.FavoritesTab }
    defs[#defs + 1] = { key = "Settings",  label = "Settings",  module = PH.SettingsTab, pinned = true }
    return defs
end

local function BuildPanel()
    if panel then return end

    panel = UI.NewFrame(UIParent, {
        width = PANEL_WIDTH, height = PANEL_HEIGHT,
        bg = Colors.bg.dark, border = Colors.border.default,
    })
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    panel:SetFrameStrata("FULLSCREEN_DIALOG")
    panel:SetFrameLevel(300)
    panel:SetClampedToScreen(true)
    panel:Hide()

    _G["PortalHub_MainFrame"] = panel

    local title = panel:CreateFontString(nil, "OVERLAY")
    title:SetFont(UI.Font, 14, "")
    title:SetText("|cff6D00FDPortalHub|r")
    title:SetTextColor(unpack(Colors.text.primary))
    title:SetPoint("TOPLEFT", 16, -16)

    BuildHouseButton(panel, title)

    local separator = panel:CreateTexture(nil, "ARTWORK")
    separator:SetHeight(1)
    separator:SetPoint("TOPLEFT", 16, -40)
    separator:SetPoint("TOPRIGHT", -16, -40)
    separator:SetColorTexture(unpack(Colors.border.light))

    local closeButton = Controls.CloseButton(panel, 24, function() PH.Hide() end)
    closeButton:SetPoint("RIGHT", panel, "TOPRIGHT", -10, -22)

    local content = CreateFrame("Frame", nil, panel)
    content:SetPoint("TOPLEFT", 16, -52)
    content:SetPoint("BOTTOMRIGHT", -16, 20)

    local version = C_AddOns.GetAddOnMetadata("PortalHub", "Version")
    local versionText = panel:CreateFontString(nil, "OVERLAY")
    versionText:SetFont(UI.Font, 12, "")
    versionText:SetPoint("BOTTOMLEFT", 12, 8)
    versionText:SetText("v" .. version)
    versionText:SetTextColor(unpack(Colors.text.muted))

    local tabDefs = BuildTabDefs()
    local tabsByKey = {}
    for _, def in ipairs(tabDefs) do
        local tabPanel = CreateFrame("Frame", nil, content)
        tabPanel:SetPoint("TOPLEFT", 0, -40)
        tabPanel:SetPoint("BOTTOMRIGHT", 0, 0)
        tabPanel:Hide()
        tabsByKey[def.key] = { def = def, panel = tabPanel }

        def.module.Build(tabPanel)
        if def.module.Refresh then
            local onShow = def.onShow
            tabPanel:SetScript("OnShow", function()
                if onShow then onShow() end
                def.module.Refresh()
            end)
        end
    end

    local currentTabBar
    local visibleTabs
    local selectedKey
    local tabBarCache = {}

    local function OnTabSelected(index)
        selectedKey = visibleTabs[index].def.key
        for _, entry in ipairs(visibleTabs) do entry.panel:Hide() end
        visibleTabs[index].panel:Show()
    end

    local function RebuildTabBar()
        if InCombatLockdown() then return end

        visibleTabs = {}
        for _, def in ipairs(tabDefs) do
            if def.pinned or not PortalHubDB.hiddenTabs[def.key] then
                visibleTabs[#visibleTabs + 1] = tabsByKey[def.key]
            end
        end

        local selectedIndex = 1
        for i, entry in ipairs(visibleTabs) do
            if entry.def.key == selectedKey then
                selectedIndex = i
                break
            end
        end
        selectedKey = visibleTabs[selectedIndex].def.key

        if currentTabBar then currentTabBar:Hide() end

        local labels = {}
        for i, entry in ipairs(visibleTabs) do labels[i] = entry.def.label end

        local cacheKey = table.concat(labels, "\1")
        local bar = tabBarCache[cacheKey]
        if bar then
            bar:SetSelected(selectedIndex)
            bar:Show()
        else
            bar = Controls.TabLineBar(content, labels, selectedIndex, OnTabSelected, content:GetWidth())
            bar:SetPoint("TOPLEFT", 0, 0)
            tabBarCache[cacheKey] = bar
        end
        currentTabBar = bar

        for _, entry in pairs(tabsByKey) do entry.panel:Hide() end
        visibleTabs[selectedIndex].panel:Show()
    end

    PH.RebuildTabBar = RebuildTabBar
    RebuildTabBar()

    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
    panel:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    tinsert(UISpecialFrames, "PortalHub_MainFrame")

    panel:SetScript("OnHide", function()
        isShown = false
        PH.StopTracking()
        PH.StopItemTracking()
        UI.CastTracker.Stop()
    end)
end

function PH.Show()
    if isShown then return end
    if InCombatLockdown() then
        print("|cff6D00FDPortalHub:|r Cannot open during combat")
        return
    end
    BuildPanel()
    isShown = true
    if PH._spellsDirty then
        PH._spellsDirty = false
        PH.RefreshSpellTabs()
    end
    if PH._toysDirty then
        PH._toysDirty = false
        PH.RefreshToyTabs()
    end
    PH.StartTracking()
    PH.StartItemTracking()
    AnimatePanel(true)
end

function PH.Hide()
    if not isShown then return end
    isShown = false
    AnimatePanel(false)
end

function PH.Toggle()
    if isShown then PH.Hide() else PH.Show() end
end

function PH.PrintKeys()
    local inGroup = IsInGroup()
    local function out(msg)
        if inGroup then
            SendChatMessage(msg, "PARTY")
        else
            print(msg)
        end
    end

    out("PortalHub - Party Keys:")

    local playerName = UnitName("player")
    local ownedLevel = C_MythicPlus.GetOwnedKeystoneLevel()
    local ownedMapID = C_MythicPlus.GetOwnedKeystoneChallengeMapID()
    if ownedLevel and ownedLevel > 0 and ownedMapID then
        out(format("%s: +%d %s", playerName, ownedLevel, C_ChallengeMode.GetMapUIInfo(ownedMapID) or "?"))
    else
        out(format("%s: No key", playerName))
    end

    local members = {}
    if inGroup then
        local prefix = IsInRaid() and "raid" or "party"
        for i = 1, GetNumGroupMembers() do
            local name = UnitName(prefix .. i)
            if name then members[name] = true end
        end
    end

    for name, data in pairs(PH._partyKeystones) do
        if members[name] and name ~= playerName and data.level and data.level > 0 then
            out(format("%s: +%d %s", name, data.level, data.name or "?"))
        end
    end
end

function PH.CheckPortalData()
    local data = PH.DungeonPortalData
    print(format("|cff6D00FDPortalHub:|r portal data check (client %s)", (GetBuildInfo())))

    local missing, seen = 0, {}
    for _, expName in ipairs(data.expansionOrder) do
        for _, entry in ipairs(data.expansions[expName]) do
            local spellID = PH.SelectSpellID(entry)
            if spellID and not seen[spellID] then
                seen[spellID] = true
                if not C_Spell.GetSpellName(spellID) then
                    missing = missing + 1
                    print(format("  |cffff4444not in client:|r %s [%s] spell %d", entry.name, expName, spellID))
                end
            end
        end
    end
    if missing == 0 then
        print("  all portal spells exist in this client")
    end

    local newest = data.seasons[1]
    if data.expansions["Current Season"] == newest.dungeons then
        print("  Current Season = newest lineup; entries resolve to:")
    else
        print("  newest season lineup (|cffffaa00gated off on this client|r) resolves to:")
    end
    for _, entry in ipairs(newest.dungeons) do
        local spellID = PH.SelectSpellID(entry)
        local name = spellID and C_Spell.GetSpellName(spellID)
        print(format("    %s -> %s", entry.name, name or "|cffff4444(missing)|r"))
    end
end

function PH.RefreshSpellTabs()
    PH.PortalsTab.Refresh()
    if PH.MageTab.Refresh then PH.MageTab.Refresh() end
end

function PH.RefreshToyTabs()
    PH.HearthsTab.Refresh()
    PH.TransmogTab.Refresh()
end

local function MakeThrottledRefresh(dirtyKey, refreshFn)
    local pending = false
    return function()
        if not isShown then
            PH[dirtyKey] = true
            return
        end
        if pending then return end
        pending = true
        C_Timer_After(0.5, function()
            pending = false
            if isShown then
                refreshFn()
            else
                PH[dirtyKey] = true
            end
        end)
    end
end

local refreshHandlers = {
    SPELLS_CHANGED = MakeThrottledRefresh("_spellsDirty", PH.RefreshSpellTabs),
    TOYS_UPDATED = MakeThrottledRefresh("_toysDirty", PH.RefreshToyTabs),
}

local eventFrame = CreateFrame("Frame")
for event in pairs(refreshHandlers) do eventFrame:RegisterEvent(event) end
eventFrame:SetScript("OnEvent", function(_, event) refreshHandlers[event]() end)

local announceFrame = CreateFrame("Frame")
announceFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
announceFrame:SetScript("OnEvent", function(_, _, _, _, spellID)
    if not (PortalHubDB.announce and portalSpellNames[spellID]) then return end
    local channel = IsInRaid() and "RAID" or IsInGroup() and "PARTY"
    if channel then
        SendChatMessage("Portal: " .. portalSpellNames[spellID], channel)
    end
end)

local toggleButton = CreateFrame("Button", "PortalHub_ToggleButton", UIParent)
toggleButton:SetSize(1, 1)
toggleButton:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -100, 100)
toggleButton:RegisterForClicks("AnyDown")
toggleButton:SetScript("OnClick", function() PH.Toggle() end)

local BIND_ACTION = "CLICK PortalHub_ToggleButton:LeftButton"

local function ApplyBinding(key)
    if InCombatLockdown() then return false end
    local prev1, prev2 = GetBindingKey(BIND_ACTION)
    if prev1 then SetBinding(prev1) end
    if prev2 then SetBinding(prev2) end
    if key and key ~= "NONE" then
        return SetBinding(key, BIND_ACTION)
    end
    return true
end

function PH.ApplyKeybind(key)
    if not ApplyBinding(key) then return false end
    SaveBindings(GetCurrentBindingSet())
    return true
end

local minimapBroker = LDB:NewDataObject("PortalHub", {
    type = "launcher",
    text = "PortalHub",
    icon = [[Interface\AddOns\PortalHub\Media\portalhub_icon]],
    OnClick = function(_, btn)
        if btn == "LeftButton" then PH.Toggle() end
    end,
    OnTooltipShow = function(tooltip)
        tooltip:AddLine("|cff6D00FDPortalHub|r", 1, 1, 1)
        tooltip:AddLine("Left-click to toggle", 0.7, 0.7, 0.7)
    end,
})

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    PortalHubDB = PortalHubDB or {}
    PortalHubDB.minimap = PortalHubDB.minimap or {}
    PortalHubDB.keybind = PortalHubDB.keybind or "NONE"
    PortalHubDB.favorites = PortalHubDB.favorites or {}
    PortalHubDB.recents = PortalHubDB.recents or {}
    PortalHubDB.customToys = PortalHubDB.customToys or {}
    PortalHubDB.customHearths = PortalHubDB.customHearths or {}
    PortalHubDB.hiddenTabs = PortalHubDB.hiddenTabs or {}
    PortalHubDB.altKeys = PortalHubDB.altKeys or {}
    if PortalHubDB.announce == nil then PortalHubDB.announce = false end
    if PortalHubDB.showUnowned == nil then PortalHubDB.showUnowned = false end

    PH.ResolveCurrentSeason()

    for _, entry in ipairs(PH.MagePortalData) do
        if entry.portalID then
            portalSpellNames[entry.portalID] = entry.name
        end
    end

    LDBIcon:Register("PortalHub", minimapBroker, PortalHubDB.minimap)
    ApplyBinding(PortalHubDB.keybind)

    SLASH_PORTALHUB1 = "/ph"
    SLASH_PORTALHUB2 = "/portalhub"
    SlashCmdList["PORTALHUB"] = function(msg)
        if msg and msg:lower():match("^%s*check") then
            PH.CheckPortalData()
        else
            PH.Toggle()
        end
    end

    SLASH_PORTALHUBKEYS1 = "/keys"
    SLASH_PORTALHUBKEYS2 = "/key"
    SlashCmdList["PORTALHUBKEYS"] = PH.PrintKeys

    hooksecurefunc("SendChatMessage", function(msg)
        if not msg then return end
        local low = msg:lower()
        if low == "!keys" or low == "!key" then
            C_Timer_After(0, PH.PrintKeys)
        end
    end)
end)

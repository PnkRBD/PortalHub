local _, PH = ...

local UI = PH.UI
local Colors = UI.Colors

local ipairs = ipairs
local pairs = pairs
local CreateFrame = CreateFrame
local C_Spell_GetSpellTexture = C_Spell.GetSpellTexture
local PlayerHasToy = PlayerHasToy
local GetItemCount = C_Item.GetItemCount
local IsPlayerSpell = IsPlayerSpell
local UnitFactionGroup = UnitFactionGroup
local InCombatLockdown = InCombatLockdown
local unpack = unpack

PH.FavoritesTab = {}

local function CollectFavorites()
    local results = {}
    local favs = PortalHubDB.favorites
    local faction = UnitFactionGroup("player")
    local seen = {}
    local dungeonData = PH.DungeonPortalData

    for _, expName in ipairs(dungeonData.expansionOrder) do
        local dungeons = dungeonData.expansions[expName]
        if dungeons then
            for _, entry in ipairs(dungeons) do
                local spellID = PH.SelectSpellID(entry)
                if spellID and favs[spellID] and not seen[spellID] and IsPlayerSpell(spellID) then
                    seen[spellID] = true
                    results[#results + 1] = {
                        id = spellID, favKey = spellID, name = entry.name,
                        action = "spell", tab = "portals",
                    }
                end
            end
        end
    end

    for _, entry in ipairs(PH.MagePortalData) do
        if not entry.faction or entry.faction == faction then
            local favID = entry.portalID or entry.teleportID
            if favs[favID] then
                local castID = (entry.portalID and IsPlayerSpell(entry.portalID) and entry.portalID)
                    or (entry.teleportID and IsPlayerSpell(entry.teleportID) and entry.teleportID)
                if castID then
                    results[#results + 1] = {
                        id = castID, favKey = favID, name = entry.name,
                        action = "spell", tab = "mage",
                    }
                end
            end
        end
    end

    for _, item in ipairs(PH.HearthItems) do
        if favs[item.id] and GetItemCount(item.id) > 0 then
            results[#results + 1] = {
                id = item.id, favKey = item.id, name = item.name,
                action = "item", tab = "hearths",
            }
        end
    end

    for _, toy in ipairs(PH.HearthToys) do
        if favs[toy.id] and PlayerHasToy(toy.id) then
            results[#results + 1] = {
                id = toy.id, favKey = toy.id, name = toy.name,
                action = "toy", tab = "hearths",
            }
        end
    end

    for id, toy in pairs(PortalHubDB.customHearths) do
        if favs[id] and PlayerHasToy(id) then
            results[#results + 1] = {
                id = id, favKey = id, name = toy.name,
                action = "toy", tab = "hearths",
            }
        end
    end

    for _, toy in ipairs(PH.TransmogToys) do
        if favs[toy.id] and PlayerHasToy(toy.id) then
            results[#results + 1] = {
                id = toy.id, favKey = toy.id, name = toy.name,
                action = "toy", tab = "transmog",
            }
        end
    end

    for id, toy in pairs(PortalHubDB.customToys) do
        if favs[id] and PlayerHasToy(id) then
            results[#results + 1] = {
                id = id, favKey = id, name = toy.name,
                action = "toy", tab = "transmog",
            }
        end
    end

    return results
end

local function CollectRecents()
    local results = {}
    local favs = PortalHubDB.favorites
    for _, entry in ipairs(PortalHubDB.recents) do
        if #results >= 10 then break end
        if not favs[entry.id] then
            local available
            if entry.action == "spell" then
                available = IsPlayerSpell(entry.id)
            elseif entry.action == "toy" then
                available = PlayerHasToy(entry.id)
            else
                available = GetItemCount(entry.id) > 0
            end
            if available then
                results[#results + 1] = entry
            end
        end
    end
    return results
end

local function GetEntryIcon(entry)
    if entry.action == "spell" then
        return C_Spell_GetSpellTexture(entry.id) or PH.FALLBACK_SPELL_ICON
    end
    return PH.GetItemIcon(entry.id)
end

function PH.FavoritesTab.Build(parent)
    local scrollArea = CreateFrame("Frame", nil, parent)
    scrollArea:SetPoint("TOPLEFT", 0, -4)
    scrollArea:SetPoint("BOTTOMRIGHT", 0, 0)

    local scroll, scrollChild, updateThumb = PH.CreateScrollArea(scrollArea)

    local function CreateFavoriteRow(rowParent)
        local row = PH.SetupRowBase(rowParent)

        row._icon = row:CreateTexture(nil, "ARTWORK")
        row._icon:SetSize(PH.ICON_SIZE, PH.ICON_SIZE)
        row._icon:SetPoint("LEFT", 6, 0)
        row._icon:SetTexCoord(PH.ICON_ZOOM, 1 - PH.ICON_ZOOM, PH.ICON_ZOOM, 1 - PH.ICON_ZOOM)

        row._border = CreateFrame("Frame", nil, row, "BackdropTemplate")
        row._border:SetPoint("TOPLEFT", row._icon, -1, 1)
        row._border:SetPoint("BOTTOMRIGHT", row._icon, 1, -1)
        row._border:SetBackdrop(PH.ICON_BORDER_BACKDROP)
        row._border:SetBackdropBorderColor(0, 0, 0, 1)

        row._label = row:CreateFontString(nil, "OVERLAY")
        row._label:SetFont(UI.Font, 13, "")
        row._label:SetPoint("LEFT", row._icon, "RIGHT", 12, 0)
        row._label:SetPoint("RIGHT", row, "RIGHT", -50, 0)
        row._label:SetJustifyH("LEFT")

        row._tabHint = row:CreateFontString(nil, "OVERLAY")
        row._tabHint:SetFont(UI.Font, 10, "")
        row._tabHint:SetPoint("RIGHT", -10, 0)
        row._tabHint:SetJustifyH("RIGHT")
        row._tabHint:SetTextColor(unpack(Colors.text.muted))

        PH.BindHoverScripts(row)
        row:RegisterForClicks("LeftButtonDown")
        row:SetScript("PreClick", function(self)
            local action = self._action
            if action == "spell" then
                PH.SafeSetAttr(self, "type", "spell")
                PH.SafeSetAttr(self, "unit", "player")
                PH.SafeSetAttr(self, "spell", self._entryID)
            elseif action == "toy" then
                PH.SafeSetAttr(self, "type", "toy")
                PH.SafeSetAttr(self, "toy", self._entryID)
            elseif action == "item" then
                PH.SafeSetAttr(self, "type", "item")
                PH.SafeSetAttr(self, "item", self._name)
            end
        end)
        row:SetScript("PostClick", function(self)
            if not self._action then return end
            PH.FlashRow(self)
            PH.RecordUse(self._entryID, self._name, self._action, self._tabName)
        end)
        return row
    end

    local pool = PH.CreateRowPool(scrollChild, CreateFavoriteRow)

    local function AcquireRow()
        local row = pool.Acquire()
        row._icon:Show()
        row._border:Show()
        if row._unfavBtn then row._unfavBtn:Hide() end
        return row
    end

    local function SetupAsHeader(row, text)
        row._icon:Hide()
        row._border:Hide()
        row._label:ClearAllPoints()
        row._label:SetPoint("LEFT", 6, 0)
        row._label:SetText(text)
        row._tabHint:SetText("")
        row._action = nil
        row._tooltipKind = nil
        PH.SafeSetAttr(row, "type", nil)
        row._hoverBg:SetColorTexture(1, 1, 1, 0)
    end

    local function SetupAsEntry(row, entry)
        row._icon:SetTexture(GetEntryIcon(entry))
        row._label:ClearAllPoints()
        row._label:SetPoint("LEFT", row._icon, "RIGHT", 12, 0)
        row._label:SetPoint("RIGHT", row, "RIGHT", -50, 0)
        row._label:SetText(entry.name)
        row._label:SetTextColor(unpack(Colors.text.primary))
        row._tabHint:ClearAllPoints()
        row._tabHint:SetPoint("RIGHT", -10, 0)
        row._tabHint:SetText(entry.tab)

        row._entryID = entry.id
        row._name = entry.name
        row._action = entry.action
        row._tabName = entry.tab
        row._tooltipKind = entry.action
        row._tooltipID = entry.id
    end

    local function AddUnfavButton(row, favKey, refreshFn)
        if not row._unfavBtn then
            local button = CreateFrame("Button", nil, row)
            button:SetSize(16, 16)
            button:SetPoint("RIGHT", -8, 0)
            button:SetNormalTexture(PH.STAR_PATH)
            button:GetNormalTexture():SetVertexColor(1, 0.82, 0, 1)
            button:SetFrameLevel(row:GetFrameLevel() + 5)
            row._unfavBtn = button
        end

        row._tabHint:ClearAllPoints()
        row._tabHint:SetPoint("RIGHT", -30, 0)

        local button = row._unfavBtn
        button:Show()
        button:SetScript("OnClick", function()
            PH.ToggleFavorite(favKey)
            refreshFn()
        end)
        button:SetScript("OnEnter", function(self)
            self:GetNormalTexture():SetVertexColor(1, 0.4, 0.4, 1)
        end)
        button:SetScript("OnLeave", function(self)
            self:GetNormalTexture():SetVertexColor(1, 0.82, 0, 1)
        end)
    end

    local emptyText = scrollArea:CreateFontString(nil, "OVERLAY")
    emptyText:SetFont(UI.Font, 12, "")
    emptyText:SetPoint("TOP", 0, -40)
    emptyText:SetTextColor(unpack(Colors.text.muted))
    emptyText:SetText("No favorites yet. Star items on other tabs\nto see them here. Recently used items\nwill also appear below.")
    emptyText:SetJustifyH("CENTER")
    emptyText:Hide()

    local function PlaceRow(row, y)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, y)
        row:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, y)
    end

    local function Refresh()
        if InCombatLockdown() then return end
        pool.ReleaseAll()

        local favorites = CollectFavorites()
        local recents = CollectRecents()
        local hasContent = #favorites > 0 or #recents > 0
        local y = 0

        if #favorites > 0 then
            local header = AcquireRow()
            SetupAsHeader(header, "|cffFFD700Favorites|r")
            PlaceRow(header, y)
            y = y - 30

            for _, entry in ipairs(favorites) do
                local row = AcquireRow()
                SetupAsEntry(row, entry)
                AddUnfavButton(row, entry.favKey, Refresh)
                PlaceRow(row, y)
                y = y - PH.ROW_SPACING
            end
        end

        if #recents > 0 then
            y = y - 8
            local header = AcquireRow()
            SetupAsHeader(header, "|cffAAAAAARecently Used|r")
            PlaceRow(header, y)
            y = y - 30

            for _, entry in ipairs(recents) do
                local row = AcquireRow()
                SetupAsEntry(row, entry)
                PlaceRow(row, y)
                y = y - PH.ROW_SPACING
            end
        end

        emptyText:SetShown(not hasContent)
        PH.FinishScrollLayout(scrollChild, scroll, updateThumb, y)
    end

    PH.FavoritesTab.Refresh = Refresh
end

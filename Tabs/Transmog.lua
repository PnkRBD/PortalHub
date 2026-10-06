local _, PH = ...

local UI = PH.UI
local Controls = UI.Controls

local ipairs = ipairs
local pairs = pairs
local CreateFrame = CreateFrame
local PlayerHasToy = PlayerHasToy
local InCombatLockdown = InCombatLockdown

PH.TransmogTab = {}

local function CollectAvailable()
    local showUnowned = PortalHubDB.showUnowned
    local list = {}
    local seen = {}
    for _, toy in ipairs(PH.TransmogToys) do
        local owned = PlayerHasToy(toy.id)
        if showUnowned or owned then
            list[#list + 1] = { id = toy.id, name = toy.name, owned = owned }
            seen[toy.id] = true
        end
    end
    for id, toy in pairs(PortalHubDB.customToys) do
        if not seen[id] then
            local owned = PlayerHasToy(id)
            if showUnowned or owned then
                list[#list + 1] = { id = id, name = toy.name, owned = owned }
            end
        end
    end
    return list
end

function PH.TransmogTab.Build(parent)
    local currentSearch = ""

    local scrollArea = CreateFrame("Frame", nil, parent)
    scrollArea:SetPoint("TOPLEFT", 0, -46)
    scrollArea:SetPoint("BOTTOMRIGHT", 0, 0)

    local scroll, scrollChild, updateThumb = PH.CreateScrollArea(scrollArea)

    local function CreateTransmogRow(rowParent)
        local row = PH.SetupItemRow(rowParent)
        PH.BindHoverScripts(row)
        row:RegisterForClicks("LeftButtonDown")
        row:SetScript("PreClick", function(self)
            if not self._owned then return end
            PH.SafeSetAttr(self, "type", "toy")
            PH.SafeSetAttr(self, "toy", self._entryID)
        end)
        row:SetScript("PostClick", function(self)
            if not self._owned then return end
            PH.FlashRow(self)
            PH.RecordUse(self._entryID, self._name, "toy", "transmog")
        end)
        return row
    end

    local pool = PH.CreateRowPool(scrollChild, CreateTransmogRow)

    local function AcquireRow()
        local row = pool.Acquire()
        if row._removeBtn then row._removeBtn:Hide() end
        return row
    end

    local function Refresh()
        if InCombatLockdown() then return end
        pool.ReleaseAll()
        PH.UnregisterItemCooldownRows(pool.pool)

        local activeRows = {}
        for _, entry in ipairs(CollectAvailable()) do
            local row = AcquireRow()
            row._iconTex:SetTexture(PH.GetItemIcon(entry.id))
            row._label:SetText(entry.name)
            row._name = entry.name
            row._entryID = entry.id
            row._owned = entry.owned
            row._tooltipKind = "toy"
            row._tooltipID = entry.id

            if entry.owned then
                PH.SetRowAvailable(row, true)
                row._itemID = entry.id
                PH.ApplyItemCooldown(row)
                PH.SetupFavButton(row, entry.id, Refresh)

                if PortalHubDB.customToys[entry.id] then
                    PH.SetupToyRemoveButton(row, entry.id, PortalHubDB.customToys, Refresh)
                end
            else
                PH.SetRowAvailable(row, false)
                row._itemID = nil
            end

            activeRows[#activeRows + 1] = row
        end

        PH.SortFavoritesFirst(activeRows)
        PH.LayoutRows(activeRows, scrollChild, scroll, updateThumb, currentSearch:lower())
        PH.RegisterItemCooldownRows(activeRows)
    end

    local searchBox = Controls.SearchBox(parent, "Search transmog toys...", function(text)
        currentSearch = text
        Refresh()
    end, 210)
    searchBox:SetPoint("TOPLEFT", 0, 0)

    local overlay
    local addButton = PH.CreateAddToyButton(parent, "Add custom toy", function()
        if not overlay then overlay = PH.BuildToyAddOverlay(parent, PortalHubDB.customToys, Refresh) end
        if overlay:IsShown() then
            overlay:Hide()
            Refresh()
        else
            overlay:Show()
        end
    end)
    addButton:SetPoint("LEFT", searchBox, "RIGHT", 8, 0)

    PH.TransmogTab.Refresh = Refresh
end

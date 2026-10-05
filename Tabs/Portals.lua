local _, PH = ...

local UI = PH.UI
local Controls = UI.Controls

local ipairs = ipairs
local table_sort = table.sort
local CreateFrame = CreateFrame
local C_Spell_GetSpellTexture = C_Spell.GetSpellTexture
local InCombatLockdown = InCombatLockdown

PH.PortalsTab = {}

local CONTROL_WIDTH = 210
local CONTROL_GAP = 8

function PH.PortalsTab.Build(parent)
    local data = PH.DungeonPortalData
    local selectedExpansion = "Current Season"
    local currentSearch = ""

    local expansionItems = {}
    for _, expName in ipairs(data.expansionOrder) do
        local dungeons = data.expansions[expName]
        if dungeons then
            for _, entry in ipairs(dungeons) do
                if PH.EntryAvailable(entry) then
                    expansionItems[#expansionItems + 1] = expName
                    break
                end
            end
        end
    end

    local scrollArea = CreateFrame("Frame", nil, parent)
    scrollArea:SetPoint("TOPLEFT", 0, -46)
    scrollArea:SetPoint("BOTTOMRIGHT", 0, 0)

    local scroll, scrollChild, updateThumb = PH.CreateScrollArea(scrollArea)

    local function CreatePortalRow(rowParent)
        local row = PH.SetupItemRow(rowParent)
        PH.BindHoverScripts(row)
        row:RegisterForClicks("LeftButtonDown")
        row:SetScript("PostClick", function(self)
            if not self._spellID then return end
            PH.FlashRow(self)
            PH.RecordUse(self._spellID, self._name, "spell", "portals")
        end)
        return row
    end

    local pool = PH.CreateRowPool(scrollChild, CreatePortalRow)

    local function CollectEntries()
        local query = currentSearch:lower()
        if query == "" then
            local src = data.expansions[selectedExpansion] or {}
            local entries = {}
            for _, entry in ipairs(src) do
                if PH.EntryAvailable(entry) then
                    entries[#entries + 1] = entry
                end
            end
            return entries
        end

        local entries = {}
        local seen = {}
        for _, expName in ipairs(data.expansionOrder) do
            local dungeons = data.expansions[expName]
            if dungeons then
                for _, entry in ipairs(dungeons) do
                    local key = PH.SelectSpellID(entry) or entry.name
                    if not seen[key] and PH.EntryAvailable(entry)
                        and entry.name:lower():find(query, 1, true) then
                        seen[key] = true
                        entries[#entries + 1] = entry
                    end
                end
            end
        end
        return entries
    end

    local function Refresh()
        if InCombatLockdown() then return end
        pool.ReleaseAll()
        PH.UntrackSpellRows(pool.pool)

        local entries = CollectEntries()

        table_sort(entries, function(a, b)
            local aID, bID = PH.SelectSpellID(a), PH.SelectSpellID(b)
            local aFav = aID and PH.IsFavorite(aID)
            local bFav = bID and PH.IsFavorite(bID)
            if aFav ~= bFav then return aFav end
            return a.name < b.name
        end)

        local y = 0
        for _, entry in ipairs(entries) do
            local spellID = PH.SelectSpellID(entry)
            local learned = PH.IsKnown(spellID)
            local row = pool.Acquire()

            row._iconTex:SetTexture(entry.icon or C_Spell_GetSpellTexture(spellID) or PH.FALLBACK_SPELL_ICON)
            row._label:SetText(entry.name)
            row._timerText:SetText("")
            row._name = entry.name
            row._entryID = spellID
            row._tooltipKind = "spell"
            row._tooltipID = spellID

            if learned then
                PH.SetRowAvailable(row, true)
                row._spellID = spellID
                PH.SafeSetAttr(row, "type", "spell")
                PH.SafeSetAttr(row, "unit", "player")
                PH.SafeSetAttr(row, "spell", spellID)
                PH.ApplyCooldown(row._cooldown, spellID)
                PH.TrackRow(row)
                PH.SetupFavButton(row, spellID, Refresh)
            else
                PH.SetRowAvailable(row, false)
                row._spellID = nil
            end

            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, y)
            row:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, y)
            y = y - PH.ROW_SPACING
        end

        PH.FinishScrollLayout(scrollChild, scroll, updateThumb, y)
    end

    local searchBox = Controls.SearchBox(parent, "Search portals...", function(text)
        currentSearch = text or ""
        Refresh()
    end, CONTROL_WIDTH)

    local dropdown = Controls.Dropdown(parent, nil, expansionItems, selectedExpansion, function(val)
        selectedExpansion = val
        currentSearch = ""
        searchBox:SetValue("")
        Refresh()
    end, nil, CONTROL_WIDTH)
    dropdown:SetPoint("TOPLEFT", 0, 0)

    searchBox:SetPoint("LEFT", dropdown, "RIGHT", CONTROL_GAP, 0)

    PH.PortalsTab.Refresh = Refresh
end

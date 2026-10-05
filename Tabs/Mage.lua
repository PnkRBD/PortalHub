local _, PH = ...

local UI = PH.UI
local Colors = UI.Colors

local ipairs = ipairs
local CreateFrame = CreateFrame
local C_Spell_GetSpellTexture = C_Spell.GetSpellTexture
local UnitFactionGroup = UnitFactionGroup
local unpack = unpack
local InCombatLockdown = InCombatLockdown

PH.MageTab = {}

local function ResolveClickedSpell(row, button)
    if button == "RightButton" and row._knowsTeleport then
        return row._teleportID
    elseif button == "LeftButton" and row._knowsPortal then
        return row._portalID
    end
    return nil
end

function PH.MageTab.Build(parent)
    local data = PH.MagePortalData

    local hint = parent:CreateFontString(nil, "OVERLAY")
    hint:SetFont(UI.Font, 11, "")
    hint:SetPoint("TOPLEFT", 6, -6)
    hint:SetText("L-click: Portal (group)  \u{2022}  R-click: Teleport (solo)")
    hint:SetTextColor(unpack(Colors.text.muted))

    local scrollArea = CreateFrame("Frame", nil, parent)
    scrollArea:SetPoint("TOPLEFT", 0, -28)
    scrollArea:SetPoint("BOTTOMRIGHT", 0, 0)

    local scroll, scrollChild, updateThumb = PH.CreateScrollArea(scrollArea)

    local function CreateMageRow(rowParent)
        local row = PH.SetupItemRow(rowParent)
        PH.BindHoverScripts(row)
        row:RegisterForClicks("LeftButtonDown", "RightButtonDown")
        row:SetScript("PreClick", function(self, button, down)
            if not down then return end
            local spell = ResolveClickedSpell(self, button)
            if spell then
                PH.SafeSetAttr(self, "type", "spell")
                PH.SafeSetAttr(self, "unit", "player")
                PH.SafeSetAttr(self, "spell", spell)
                self._spellID = spell
            end
        end)
        row:SetScript("PostClick", function(self, button)
            local spell = ResolveClickedSpell(self, button)
            if not spell then return end
            PH.FlashRow(self)
            PH.RecordUse(spell, self._name, "spell", "mage")
        end)
        return row
    end

    local pool = PH.CreateRowPool(scrollChild, CreateMageRow)

    local function Refresh()
        if InCombatLockdown() then return end
        pool.ReleaseAll()
        PH.UntrackSpellRows(pool.pool)

        local faction = UnitFactionGroup("player")
        local y = 0

        for _, entry in ipairs(data) do
            if not entry.faction or entry.faction == faction then
                local knowsTeleport = PH.IsKnown(entry.teleportID)
                local knowsPortal = PH.IsKnown(entry.portalID)
                local iconSpell = (knowsPortal and entry.portalID)
                    or (knowsTeleport and entry.teleportID)
                    or entry.portalID or entry.teleportID

                local row = pool.Acquire()
                row._iconTex:SetTexture(C_Spell_GetSpellTexture(iconSpell) or PH.FALLBACK_SPELL_ICON)
                row._label:SetText(entry.name)
                row._name = entry.name
                row._tooltipKind = "spell"
                row._tooltipID = iconSpell
                row._knowsPortal = knowsPortal
                row._knowsTeleport = knowsTeleport
                row._portalID = entry.portalID
                row._teleportID = entry.teleportID
                row._showDualClickHint = knowsPortal and knowsTeleport or nil

                if knowsPortal or knowsTeleport then
                    PH.SetRowAvailable(row, true)

                    if knowsTeleport and not knowsPortal and entry.portalID then
                        row._timerText:SetText("|cff80ccff(TP only)|r")
                    elseif knowsPortal and not knowsTeleport and entry.teleportID then
                        row._timerText:SetText("|cffff80ff(Portal only)|r")
                    else
                        row._timerText:SetText("")
                    end

                    local primarySpell = (knowsPortal and entry.portalID) or (knowsTeleport and entry.teleportID)
                    row._spellID = primarySpell
                    PH.ApplyCooldown(row._cooldown, primarySpell)
                    PH.TrackRow(row)
                    PH.SetupFavButton(row, entry.portalID or entry.teleportID)
                else
                    PH.SetRowAvailable(row, false)
                    row._spellID = nil
                end

                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, y)
                row:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, y)
                y = y - PH.ROW_SPACING
            end
        end

        PH.FinishScrollLayout(scrollChild, scroll, updateThumb, y)
    end

    PH.MageTab.Refresh = Refresh
end

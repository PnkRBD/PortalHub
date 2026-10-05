local _, PH = ...

local UI = PH.UI
local Controls = UI.Controls
local Colors = UI.Colors
local LDBIcon = LibStub("LibDBIcon-1.0")

local unpack = unpack
local ipairs = ipairs
local UnitClass = UnitClass

PH.SettingsTab = {}

local TAB_TOGGLES = {
    { key = "Portals",   label = "Portals" },
    { key = "Mage",      label = "Mage", mageOnly = true },
    { key = "Hearths",   label = "Hearths" },
    { key = "Group",     label = "M+ (party & alt keys)" },
    { key = "Transmog",  label = "Transmog toys" },
    { key = "Favorites", label = "Favorites" },
}

function PH.SettingsTab.Build(parent)
    local keybindWidget
    keybindWidget = Controls.Keybind(parent, "Toggle Keybind", PortalHubDB.keybind, function(key)
        if PH.ApplyKeybind(key) then
            PortalHubDB.keybind = key
        else
            keybindWidget:SetValue(PortalHubDB.keybind)
        end
    end, 468)
    keybindWidget:SetPoint("TOPLEFT", 0, -10)

    local minimapCheck = Controls.SparkToggle(parent, "Show minimap button", not PortalHubDB.minimap.hide, function(checked)
        PortalHubDB.minimap.hide = not checked
        if checked then
            LDBIcon:Show("PortalHub")
        else
            LDBIcon:Hide("PortalHub")
        end
    end)
    minimapCheck:SetPoint("TOPLEFT", keybindWidget, "BOTTOMLEFT", 0, -16)

    local announceCheck = Controls.SparkToggle(parent, "Announce mage portals to party/raid", PortalHubDB.announce, function(checked)
        PortalHubDB.announce = checked
    end)
    announceCheck:SetPoint("TOPLEFT", minimapCheck, "BOTTOMLEFT", 0, -8)

    local unownedCheck = Controls.SparkToggle(parent, "Show unowned hearths and transmog toys", PortalHubDB.showUnowned, function(checked)
        PortalHubDB.showUnowned = checked
        PH.HearthsTab.Refresh()
        PH.TransmogTab.Refresh()
    end)
    unownedCheck:SetPoint("TOPLEFT", announceCheck, "BOTTOMLEFT", 0, -8)

    local tabsHeader = parent:CreateFontString(nil, "OVERLAY")
    tabsHeader:SetFont(UI.Font, 12, "")
    tabsHeader:SetText("Visible tabs")
    tabsHeader:SetTextColor(unpack(Colors.text.secondary))
    tabsHeader:SetPoint("TOPLEFT", unownedCheck, "BOTTOMLEFT", 0, -18)

    local _, playerClass = UnitClass("player")
    local isMage = playerClass == "MAGE"

    local anchor = tabsHeader
    local offset = -8
    for _, def in ipairs(TAB_TOGGLES) do
        if not def.mageOnly or isMage then
            local check = Controls.SparkToggle(parent, def.label, not PortalHubDB.hiddenTabs[def.key], function(checked)
                PortalHubDB.hiddenTabs[def.key] = (not checked) or nil
                PH.RebuildTabBar()
            end)
            check:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, offset)
            anchor = check
            offset = -6
        end
    end
end

local _, PH = ...

local UI = PH.UI

local CastTracker = {}
UI.CastTracker = CastTracker

local FILL_ALPHA = 0.25

local pendingFrame
local activeFrame, castStart, castEnd

local function EnsureFill(frame)
    if frame._phCastFill then return frame._phCastFill end
    local fill = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    fill:SetPoint("TOPLEFT", 0, 0)
    fill:SetPoint("BOTTOMLEFT", 0, 0)
    fill:SetWidth(0)
    fill:Hide()
    frame._phCastFill = fill
    return fill
end

local function Clear()
    if activeFrame and activeFrame._phCastFill then
        activeFrame._phCastFill:Hide()
        activeFrame._phCastFill:SetWidth(0)
    end
    activeFrame = nil
    pendingFrame = nil
end

function CastTracker.MarkPending(frame)
    pendingFrame = frame
end

function CastTracker.Stop()
    Clear()
end

local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function(self)
    if not activeFrame or not activeFrame:IsShown() then
        Clear()
        self:Hide()
        return
    end
    local duration = castEnd - castStart
    if duration <= 0 then return end
    local progress = math.min(1, (GetTime() - castStart) / duration)
    activeFrame._phCastFill:SetWidth(math.max(1, activeFrame:GetWidth() * progress))
end)

local events = CreateFrame("Frame")
events:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
events:SetScript("OnEvent", function(_, event, unit)
    if unit ~= "player" then return end

    if event == "UNIT_SPELLCAST_START" then
        local frame = pendingFrame
        if not frame or not frame:IsShown() then return end
        local _, _, _, startMs, endMs = UnitCastingInfo("player")
        if not startMs or not endMs then return end
        Clear()
        local fill = EnsureFill(frame)
        local r, g, b = UI.GetAccent()
        fill:SetColorTexture(r, g, b, FILL_ALPHA)
        fill:SetWidth(1)
        fill:Show()
        activeFrame = frame
        castStart = startMs / 1000
        castEnd = endMs / 1000
        driver:Show()
    else
        Clear()
        driver:Hide()
    end
end)

local _, PH = ...

local UI = {}
PH.UI = UI
UI.Controls = {}

UI.Font = "Fonts\\FRIZQT__.TTF"
UI.FONT_SIZE = 11
UI.ROW_HEIGHT = 28
UI.LABEL_OFFSET = 22
UI.WHITE = "Interface\\Buttons\\WHITE8x8"

UI.BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
}

local Colors = {
    bg = {
        dark  = { 0.025, 0.03, 0.035, 0.98 },
        light = { 0.05, 0.055, 0.06, 0.98 },
        input = { 0.06, 0.065, 0.07, 1 },
    },
    border = {
        dark    = { 0.06, 0.06, 0.06, 1 },
        default = { 0.12, 0.12, 0.12, 1 },
        light   = { 0.18, 0.18, 0.18, 1 },
        input   = { 0.15, 0.15, 0.15, 1 },
    },
    text = {
        primary   = { 1, 1, 1, 1 },
        secondary = { 0.7, 0.7, 0.7, 1 },
        muted     = { 0.5, 0.5, 0.5, 1 },
        disabled  = { 0.35, 0.35, 0.35, 1 },
    },
    button = {
        normal = { 0.05, 0.055, 0.06, 0.98 },
        hover  = { 0.08, 0.085, 0.09, 0.98 },
    },
    control = {
        disabled = { 0.1, 0.1, 0.1, 1 },
    },
}
UI.Colors = Colors

function UI.GetAccent()
    local _, class = UnitClass("player")
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b, 1 end
    return 0.45, 0.85, 0.65, 1
end
Colors.GetAccent = UI.GetAccent

function UI.NewFrame(parent, opts)
    opts = opts or {}
    local f = CreateFrame(opts.frameType or "Frame", nil, parent, "BackdropTemplate")
    f:SetBackdrop(UI.BACKDROP)
    local bg = opts.bg or Colors.bg.dark
    local border = opts.border or Colors.border.dark
    f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
    f:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
    if opts.width then f:SetWidth(opts.width) end
    if opts.height then f:SetHeight(opts.height) end
    return f
end

function UI.CreateTex(parent, r, g, b, a)
    local tex = parent:CreateTexture(nil, "ARTWORK")
    tex:SetTexture(UI.WHITE)
    tex:SetVertexColor(r or 1, g or 1, b or 1, a or 1)
    return tex
end

local deferFrame = CreateFrame("Frame")
deferFrame:Hide()
local deferred = {}
deferFrame:SetScript("OnUpdate", function(self)
    self:Hide()
    for i = 1, #deferred do
        local fn = deferred[i]
        deferred[i] = nil
        fn()
    end
end)
function UI.Defer(fn)
    deferred[#deferred + 1] = fn
    deferFrame:Show()
end

local MENU_ANIM_DURATION = 0.12

function UI.ShowMenuAnimated(menu)
    menu:SetAlpha(0)
    menu:Show()
    local start = GetTime()
    menu:SetScript("OnUpdate", function(self)
        local t = (GetTime() - start) / MENU_ANIM_DURATION
        if t >= 1 then
            self:SetAlpha(1)
            self:SetScript("OnUpdate", nil)
        else
            self:SetAlpha(1 - (1 - t) * (1 - t))
        end
    end)
end

function UI.HideMenuAnimated(menu)
    if not menu:IsShown() then return end
    local startA = menu:GetAlpha()
    local start = GetTime()
    menu:SetScript("OnUpdate", function(self)
        local t = (GetTime() - start) / MENU_ANIM_DURATION
        if t >= 1 then
            self:SetScript("OnUpdate", nil)
            self:Hide()
        else
            self:SetAlpha(startA * (1 - (1 - (1 - t) * (1 - t))))
        end
    end)
end

function UI.ScrollLogic(scrollFrame, child, track, thumb, opts)
    opts = opts or {}
    local step = opts.step or 40
    local scrollMax = 0
    local shown = false
    local math_max, math_min, math_floor = math.max, math.min, math.floor

    local function UpdateThumb()
        local childH = child:GetHeight() or 0
        local viewH = scrollFrame:GetHeight() or 0
        local range = math_max(0, childH - viewH)
        scrollMax = range
        local needs = range > 1
        if needs ~= shown then
            shown = needs
            thumb:SetShown(needs)
            track:SetShown(needs)
            if not needs then scrollFrame:SetVerticalScroll(0) end
            if opts.onShow then opts.onShow(needs) end
        end
        if needs then
            local trackH = track:GetHeight()
            if trackH > 0 then
                local thumbH = math_max(20, math_min(trackH - 4, trackH * (viewH / childH)))
                thumb:SetHeight(thumbH)
                local scroll = math_min(scrollFrame:GetVerticalScroll(), range)
                thumb:ClearAllPoints()
                thumb:SetPoint("TOP", track, "TOP", 0, -(scroll / range) * (trackH - thumbH))
            end
        end
    end

    local function DoScroll(delta)
        if scrollMax <= 0 then return end
        local cur = scrollFrame:GetVerticalScroll()
        scrollFrame:SetVerticalScroll(math_floor(math_max(0, math_min(scrollMax, cur - delta * step)) + 0.5))
        UpdateThumb()
    end

    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(_, d) DoScroll(d) end)

    local dragStart, dragScrollStart
    local function DragOnUpdate()
        if not dragStart or scrollMax <= 0 then return end
        local y = select(2, GetCursorPosition()) / UIParent:GetEffectiveScale()
        local trackH = track:GetHeight() - thumb:GetHeight()
        if trackH <= 0 then return end
        local delta = (dragStart - y) / trackH * scrollMax
        scrollFrame:SetVerticalScroll(math_floor(math_max(0, math_min(scrollMax, dragScrollStart + delta)) + 0.5))
        UpdateThumb()
    end
    thumb:SetScript("OnMouseDown", function(_, btn)
        if btn ~= "LeftButton" then return end
        dragStart = select(2, GetCursorPosition()) / UIParent:GetEffectiveScale()
        dragScrollStart = scrollFrame:GetVerticalScroll()
        thumb:SetScript("OnUpdate", DragOnUpdate)
    end)
    thumb:SetScript("OnMouseUp", function()
        dragStart = nil
        thumb:SetScript("OnUpdate", nil)
    end)
    thumb:HookScript("OnHide", function()
        dragStart = nil
        thumb:SetScript("OnUpdate", nil)
    end)

    track:EnableMouse(true)
    track:SetScript("OnMouseDown", function(self, btn)
        if btn ~= "LeftButton" or scrollMax <= 0 then return end
        local y = select(2, GetCursorPosition()) / UIParent:GetEffectiveScale()
        local ratio = (self:GetTop() - y) / self:GetHeight()
        scrollFrame:SetVerticalScroll(math_floor(ratio * scrollMax + 0.5))
        UpdateThumb()
    end)

    return {
        UpdateThumb = UpdateThumb,
        DoScroll = DoScroll,
    }
end

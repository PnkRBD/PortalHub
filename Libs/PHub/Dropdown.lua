local _, PH = ...

local UI = PH.UI
local Controls = UI.Controls
local T = UI.Colors
local unpack = unpack

local MENU_ROW_HEIGHT = 22
local MENU_MAX_VISIBLE = 10

function Controls.Dropdown(parent, items, selected, callback, width)
    local value = selected

    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width, UI.ROW_HEIGHT)

    local btn = UI.NewFrame(container, {
        frameType = "Button",
        bg = T.bg.input, border = T.border.input,
        width = width, height = UI.ROW_HEIGHT,
    })
    btn:SetPoint("BOTTOMLEFT")

    local btnText = btn:CreateFontString(nil, "OVERLAY")
    btnText:SetFont(UI.Font, 12, "")
    btnText:SetPoint("LEFT", 10, 0)
    btnText:SetPoint("RIGHT", -25, 0)
    btnText:SetJustifyH("LEFT")
    btnText:SetTextColor(unpack(T.text.secondary))
    btnText:SetText(value)

    local expandIcon = btn:CreateFontString(nil, "OVERLAY")
    expandIcon:SetFont(UI.Font, 14, "")
    expandIcon:SetPoint("RIGHT", -10, 0)
    expandIcon:SetText("+")
    expandIcon:SetTextColor(UI.GetAccent())

    local menu = UI.NewFrame(UIParent, { bg = T.bg.dark, border = T.border.light, width = width, height = 100 })
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetFrameLevel(400)
    menu:SetClampedToScreen(true)
    menu:Hide()

    local scrollFrame = CreateFrame("ScrollFrame", nil, menu)
    scrollFrame:SetPoint("TOPLEFT", 2, -2)
    scrollFrame:SetPoint("BOTTOMRIGHT", -2, 2)
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(width - 4)
    scrollFrame:SetScrollChild(scrollChild)

    local scrollTrack = CreateFrame("Frame", nil, menu, "BackdropTemplate")
    scrollTrack:SetWidth(6)
    scrollTrack:SetPoint("TOPRIGHT", -2, -2)
    scrollTrack:SetPoint("BOTTOMRIGHT", -2, 2)
    scrollTrack:SetBackdrop({ bgFile = UI.WHITE })
    scrollTrack:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    scrollTrack:Hide()

    local scrollThumb = CreateFrame("Frame", nil, scrollTrack, "BackdropTemplate")
    scrollThumb:SetWidth(6)
    scrollThumb:SetBackdrop({ bgFile = UI.WHITE })
    scrollThumb:SetBackdropColor(0.4, 0.4, 0.4, 1)
    scrollThumb:SetPoint("TOP")
    scrollThumb:SetHeight(20)

    local scrollLogic = UI.ScrollLogic(scrollFrame, scrollChild, scrollTrack, scrollThumb, {
        step = MENU_ROW_HEIGHT * 2,
        onShow = function(needs)
            scrollFrame:SetPoint("BOTTOMRIGHT", needs and -10 or -2, 2)
        end,
    })
    menu:EnableMouseWheel(true)
    menu:SetScript("OnMouseWheel", function(_, d) scrollLogic.DoScroll(d) end)

    local function PositionMenu()
        menu:ClearAllPoints()
        local bottom = btn:GetBottom()
        if not bottom or bottom < menu:GetHeight() + 50 then
            menu:SetPoint("BOTTOMLEFT", btn, "TOPLEFT", 0, 2)
        else
            menu:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
        end
    end

    local rowPool = {}
    local function GetRow(index)
        if rowPool[index] then
            rowPool[index]:Show()
            return rowPool[index]
        end
        local row = CreateFrame("Button", nil, scrollChild)
        row:SetHeight(MENU_ROW_HEIGHT)
        row.text = row:CreateFontString(nil, "OVERLAY")
        row.text:SetFont(UI.Font, 11, "")
        row.text:SetPoint("LEFT", 6, 0)
        row.hl = UI.CreateTex(row, UI.GetAccent())
        row.hl:SetAllPoints()
        row.hl:SetDrawLayer("BACKGROUND")
        row.hl:SetAlpha(0.18)
        row.hl:Hide()
        row.hover = row:CreateTexture(nil, "BACKGROUND", nil, 1)
        row.hover:SetAllPoints()
        row.hover:SetColorTexture(unpack(T.bg.light))
        row.hover:Hide()
        row:SetScript("OnEnter", function(s)
            s.hover:Show()
            s.text:SetTextColor(1, 1, 1)
        end)
        row:SetScript("OnLeave", function(s)
            s.hover:Hide()
            if not s._selected then s.text:SetTextColor(unpack(T.text.secondary)) end
        end)
        rowPool[index] = row
        return row
    end

    local function CloseMenu()
        local left, top = menu:GetLeft(), menu:GetTop()
        if left and top then
            menu:ClearAllPoints()
            menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        end
        UI.HideMenuAnimated(menu)
        expandIcon:SetText("+")
    end

    local function BuildMenu()
        for _, row in ipairs(rowPool) do row:Hide() end
        local y = 0
        local mw = btn:GetWidth()
        menu:SetWidth(mw)
        scrollChild:SetWidth(mw - 4)
        for i, val in ipairs(items) do
            local row = GetRow(i)
            row:SetPoint("TOPLEFT", 0, -y)
            row:SetPoint("TOPRIGHT", 0, -y)
            row.text:SetText(val)
            local isSelected = val == value
            row._selected = isSelected
            row.hl:SetShown(isSelected)
            row.text:SetTextColor(unpack(isSelected and T.text.primary or T.text.secondary))
            row:SetScript("OnClick", function()
                value = val
                btnText:SetText(value)
                CloseMenu()
                callback(val)
            end)
            y = y + MENU_ROW_HEIGHT
        end
        scrollChild:SetHeight(y)
        menu:SetHeight(math.min(#items, MENU_MAX_VISIBLE) * MENU_ROW_HEIGHT + 8)
        scrollFrame:SetVerticalScroll(0)
        C_Timer.After(0, scrollLogic.UpdateThumb)
    end

    btn:SetScript("OnClick", function()
        if menu:IsShown() then
            CloseMenu()
        else
            BuildMenu()
            PositionMenu()
            UI.ShowMenuAnimated(menu)
            expandIcon:SetText("\226\136\146")
        end
    end)
    btn:SetScript("OnEnter", function(s) s:SetBackdropBorderColor(UI.GetAccent()) end)
    btn:SetScript("OnLeave", function(s) s:SetBackdropBorderColor(unpack(T.border.input)) end)

    local checkFrame = CreateFrame("Frame")
    checkFrame:Hide()
    checkFrame:SetScript("OnUpdate", function(cf)
        if not (btn:IsMouseOver() or menu:IsMouseOver()) then
            if IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton") then
                CloseMenu()
                cf:Hide()
            end
        end
    end)
    menu:SetScript("OnShow", function(self)
        self:Raise()
        checkFrame:Show()
    end)
    menu:SetScript("OnHide", function() checkFrame:Hide() end)

    return container
end

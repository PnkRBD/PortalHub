local _, PH = ...

local UI = PH.UI
local Controls = UI.Controls
local T = UI.Colors
local FS = UI.FONT_SIZE
local RH = UI.ROW_HEIGHT
local LABEL_OFFSET = UI.LABEL_OFFSET
local unpack = unpack

function Controls.Text(parent, text, size, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(UI.Font, size or FS, "")
    fs:SetText(text or "")
    fs:SetTextColor(unpack(color or T.text.primary))
    return fs
end

function Controls.ClearButton(parent, size, callback)
    size = size or 18
    local f = CreateFrame("Button", nil, parent)
    f:SetSize(size, size)
    local mr, mg, mb = unpack(T.text.muted)
    local x = f:CreateFontString(nil, "OVERLAY")
    x:SetFont(UI.Font, math.floor(size * 0.85), "")
    x:SetText("\195\151")
    x:SetPoint("CENTER")
    x:SetTextColor(mr, mg, mb, 1)
    f:SetScript("OnSizeChanged", function(s)
        x:SetFont(UI.Font, math.floor(s:GetHeight() * 0.85), "")
    end)
    f:SetScript("OnClick", function() if callback then callback() end end)
    f:HookScript("OnEnter", function() x:SetTextColor(1, 1, 1, 1) end)
    f:HookScript("OnLeave", function() x:SetTextColor(mr, mg, mb, 1) end)
    return f
end

function Controls.CloseButton(parent, size, callback)
    size = size or 24
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(size, size)
    local x = btn:CreateFontString(nil, "OVERLAY")
    x:SetFont(UI.Font, size * 0.7, "")
    x:SetPoint("CENTER")
    x:SetText("\195\151")
    x:SetTextColor(unpack(T.text.muted))
    btn:SetScript("OnEnter", function() x:SetTextColor(1, 0.4, 0.4, 1) end)
    btn:SetScript("OnLeave", function() x:SetTextColor(unpack(T.text.muted)) end)
    btn:SetScript("OnClick", function() if callback then callback() end end)
    return btn
end

function Controls.Button(parent, text, width)
    width = width or 100
    local f = UI.NewFrame(parent, {
        frameType = "Button",
        bg = T.button.normal, border = T.border.default,
        width = width, height = RH,
    })

    local accentLine = UI.CreateTex(f, UI.GetAccent())
    accentLine:SetDrawLayer("OVERLAY")
    accentLine:SetPoint("BOTTOMLEFT", 1, 1)
    accentLine:SetPoint("BOTTOMRIGHT", -1, 1)
    accentLine:SetHeight(2)
    accentLine:SetAlpha(0)

    f:HookScript("OnEnter", function(s)
        s:SetBackdropColor(unpack(T.button.hover))
        accentLine:SetAlpha(1)
    end)
    f:HookScript("OnLeave", function(s)
        s:SetBackdropColor(unpack(T.button.normal))
        accentLine:SetAlpha(0)
    end)

    local label = Controls.Text(f, text or "")
    label:SetPoint("CENTER")
    f:SetScript("OnMouseDown", function(s) if s:IsEnabled() then label:SetPoint("CENTER", 1, -1) end end)
    f:SetScript("OnMouseUp", function() label:SetPoint("CENTER", 0, 0) end)

    function f:SetText(t)
        label:SetText(t)
        local w = label:GetStringWidth() + 24
        if w > f:GetWidth() then f:SetWidth(w) end
    end
    function f:GetText() return label:GetText() end
    f.text = label
    return f
end

function Controls.SearchBox(parent, placeholder, callback, width)
    width = width or 250
    local container = UI.NewFrame(parent, { bg = T.bg.input, border = T.border.input, width = width, height = RH })

    local function SetHovered(hovered)
        if hovered then
            container:SetBackdropBorderColor(UI.GetAccent())
        else
            container:SetBackdropBorderColor(unpack(T.border.input))
        end
    end
    container:SetScript("OnEnter", function() SetHovered(true) end)
    container:SetScript("OnLeave", function() SetHovered(false) end)

    local icon = container:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16)
    icon:SetPoint("LEFT", 10, 0)
    icon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    icon:SetVertexColor(unpack(T.text.muted))

    local clearBtn = Controls.ClearButton(container, 20)
    clearBtn:SetPoint("RIGHT", -6, 0)
    clearBtn:SetScript("OnEnter", function() SetHovered(true) end)
    clearBtn:SetScript("OnLeave", function() SetHovered(false) end)
    clearBtn:Hide()

    local box = CreateFrame("EditBox", nil, container)
    box:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    box:SetPoint("RIGHT", clearBtn, "LEFT", -6, 0)
    box:SetHeight(20)
    box:SetAutoFocus(false)
    box:SetFont(UI.Font, 12, "")
    box:SetTextColor(unpack(T.text.primary))
    box:SetScript("OnEnter", function() SetHovered(true) end)
    box:SetScript("OnLeave", function() if not box:HasFocus() then SetHovered(false) end end)
    box:SetScript("OnEditFocusGained", function() SetHovered(true) end)
    box:SetScript("OnEditFocusLost", function() SetHovered(false) end)

    local ph = box:CreateFontString(nil, "OVERLAY")
    ph:SetFont(UI.Font, 12, "")
    ph:SetPoint("LEFT")
    ph:SetText(placeholder or "Search...")
    ph:SetTextColor(unpack(T.text.muted))

    clearBtn:SetScript("OnClick", function()
        box:SetText("")
        box:ClearFocus()
        ph:Show()
        clearBtn:Hide()
        if callback then callback("") end
    end)
    box:SetScript("OnTextChanged", function(s)
        local t = s:GetText()
        ph:SetShown(t == "")
        clearBtn:SetShown(t ~= "")
        if callback then callback(t) end
    end)
    box:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)

    function container:GetValue() return box:GetText() end
    function container:SetValue(val)
        box:SetText(val or "")
        ph:SetShown(val == "" or val == nil)
        clearBtn:SetShown(val and val ~= "")
    end
    container.editbox = box
    return container
end

local propagateWaiter
local function SafeSetPropagateKeyboardInput(frame, value)
    if InCombatLockdown() then
        if not propagateWaiter then
            propagateWaiter = CreateFrame("Frame")
            propagateWaiter.pending = {}
            propagateWaiter:SetScript("OnEvent", function(self)
                self:UnregisterAllEvents()
                for f, v in pairs(self.pending) do
                    if f.SetPropagateKeyboardInput then f:SetPropagateKeyboardInput(v) end
                    self.pending[f] = nil
                end
            end)
        end
        propagateWaiter.pending[frame] = value
        propagateWaiter:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
        frame:SetPropagateKeyboardInput(value)
    end
end

function Controls.Keybind(parent, label, key, callback, width)
    width = width or 280
    local state = { key = key or "NONE", listening = false }
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width, label and (RH + LABEL_OFFSET) or RH)
    if label then
        Controls.Text(container, label, FS, T.text.primary):SetPoint("TOPLEFT")
    end

    local row = UI.NewFrame(container, { bg = T.bg.input, border = T.border.input, width = width, height = RH })
    row:SetPoint("BOTTOMLEFT")
    row:SetPoint("BOTTOMRIGHT")

    local btnH = RH - 6
    local btnW = math.floor(width * 0.3)
    local editBtn = Controls.Button(row, "Edit Keybind", btnW)
    editBtn:SetSize(btnW, btnH)
    editBtn:SetPoint("RIGHT", -3, 0)
    local clearBtn = Controls.ClearButton(row, btnH - 4)
    clearBtn:SetPoint("RIGHT", editBtn, "LEFT", -4, 0)

    local keyText = row:CreateFontString(nil, "OVERLAY")
    keyText:SetFont(UI.Font, 12, "")
    keyText:SetPoint("LEFT", 10, 0)
    keyText:SetPoint("RIGHT", clearBtn, "LEFT", -6, 0)
    keyText:SetJustifyH("LEFT")
    keyText:SetTextColor(unpack(T.text.primary))

    local listener = CreateFrame("Frame", nil, UIParent)
    listener:EnableKeyboard(true)
    listener:Hide()
    listener:SetScript("OnShow", function(s) SafeSetPropagateKeyboardInput(s, true) end)

    local function UpdateDisplay()
        if state.listening then
            keyText:SetText("Press a key...")
            keyText:SetTextColor(1, 1, 1, 1)
            row:SetBackdropBorderColor(0.9, 0.2, 0.2, 1)
            editBtn:SetText("Cancel")
            clearBtn:Hide()
        else
            keyText:SetText(state.key == "NONE" and "Not bound" or state.key)
            keyText:SetTextColor(unpack(T.text.primary))
            row:SetBackdropBorderColor(unpack(T.border.input))
            editBtn:SetText("Edit Keybind")
            clearBtn:SetShown(state.key ~= "NONE")
        end
    end

    clearBtn:SetScript("OnClick", function()
        state.key = "NONE"
        UpdateDisplay()
        if callback then callback(state.key) end
    end)

    row:EnableMouse(true)
    row:SetScript("OnEnter", function(s) if not state.listening then s:SetBackdropBorderColor(UI.GetAccent()) end end)
    row:SetScript("OnLeave", function(s) if not state.listening then s:SetBackdropBorderColor(unpack(T.border.input)) end end)

    listener:SetScript("OnKeyDown", function(self, k)
        if not state.listening then return end
        if k == "LSHIFT" or k == "RSHIFT" or k == "LCTRL" or k == "RCTRL" or k == "LALT" or k == "RALT" then return end
        SafeSetPropagateKeyboardInput(self, false)
        if k ~= "ESCAPE" then
            local m = ""
            if IsShiftKeyDown() then m = m .. "SHIFT-" end
            if IsControlKeyDown() then m = m .. "CTRL-" end
            if IsAltKeyDown() then m = m .. "ALT-" end
            state.key = m .. k
            if callback then callback(state.key) end
        end
        state.listening = false
        self:Hide()
        UpdateDisplay()
    end)

    editBtn:SetScript("OnClick", function()
        if InCombatLockdown() then return end
        state.listening = not state.listening
        listener:SetShown(state.listening)
        UpdateDisplay()
    end)

    UpdateDisplay()
    function container:GetValue() return state.key end
    function container:SetValue(val) state.key = val or "NONE"; UpdateDisplay() end
    return container
end

local ANIM_DURATION = 0.14
local function Lerp(a, b, t) return a + (b - a) * t end

function Controls.SparkToggle(parent, label, checked, callback, indentLevel, enabled)
    local indentPx = (indentLevel or 0) * 20
    if enabled == nil then enabled = true end
    local state = { enabled = checked or false, disabled = not enabled }

    local LED = 14
    local HALO_OVERFLOW = 2
    local OUTER = LED + HALO_OVERFLOW * 2
    local SPARK_COUNT = 7
    local SPARK_TRAVEL = 13

    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(math.max(label and 200 or OUTER, OUTER + indentPx), OUTER)

    local track = CreateFrame("Button", nil, container)
    track:SetAllPoints()

    local halo = track:CreateTexture(nil, "BACKGROUND")
    halo:SetTexture(UI.WHITE)
    halo:SetSize(OUTER, OUTER)
    halo:SetPoint("CENTER", track, "LEFT", indentPx + OUTER / 2, 0)

    local ring = CreateFrame("Frame", nil, track, "BackdropTemplate")
    ring:SetSize(LED, LED)
    ring:SetPoint("LEFT", track, "LEFT", indentPx + HALO_OVERFLOW, 0)
    ring:SetBackdrop(UI.BACKDROP)

    local fill = ring:CreateTexture(nil, "ARTWORK")
    fill:SetTexture(UI.WHITE)
    fill:SetSize(LED - 4, LED - 4)
    fill:SetPoint("CENTER")

    local sparks = {}
    for i = 1, SPARK_COUNT do
        local angle = (i - 1) * (math.pi * 2 / SPARK_COUNT) - math.pi / 2
        local spark = track:CreateTexture(nil, "OVERLAY")
        spark:SetTexture(UI.WHITE)
        spark:SetSize(2, 2)
        spark:SetPoint("CENTER", ring, "CENTER")
        spark:SetAlpha(0)
        spark:SetBlendMode("ADD")

        local group = spark:CreateAnimationGroup()
        local move = group:CreateAnimation("Translation")
        move:SetOffset(math.cos(angle) * SPARK_TRAVEL, math.sin(angle) * SPARK_TRAVEL)
        move:SetDuration(0.45)
        move:SetSmoothing("OUT")
        move:SetOrder(1)
        local fadeIn = group:CreateAnimation("Alpha")
        fadeIn:SetFromAlpha(0); fadeIn:SetToAlpha(1)
        fadeIn:SetDuration(0.05); fadeIn:SetOrder(1)
        local fadeOut = group:CreateAnimation("Alpha")
        fadeOut:SetFromAlpha(1); fadeOut:SetToAlpha(0)
        fadeOut:SetDuration(0.4); fadeOut:SetStartDelay(0.05); fadeOut:SetOrder(1)

        sparks[i] = { tex = spark, group = group }
    end

    local function FireSparks()
        if state.disabled then return end
        local r, g, b = UI.GetAccent()
        for _, s in ipairs(sparks) do
            s.tex:SetVertexColor(r, g, b, 1)
            s.group:Stop()
            s.group:Play()
        end
    end

    local labelFs
    if label then
        labelFs = Controls.Text(container, label, FS, T.text.primary)
        labelFs:SetPoint("LEFT", ring, "RIGHT", 8, 0)
    end

    local progress = state.enabled and 1 or 0
    local lastEnabled = state.enabled

    local function Render()
        if state.enabled and not lastEnabled then FireSparks() end
        lastEnabled = state.enabled

        if state.disabled then
            ring:SetBackdropColor(0.05, 0.05, 0.05, 1)
            ring:SetBackdropBorderColor(unpack(T.border.dark))
            fill:SetVertexColor(0.18, 0.18, 0.18, 0.6)
            halo:SetVertexColor(0, 0, 0, 0)
            if labelFs then labelFs:SetTextColor(unpack(T.text.disabled)) end
            return
        end

        local r, g, b = UI.GetAccent()
        ring:SetBackdropColor(Lerp(0.05, r * 0.7, progress), Lerp(0.05, g * 0.7, progress), Lerp(0.05, b * 0.7, progress), 1)
        ring:SetBackdropBorderColor(Lerp(0.22, r, progress), Lerp(0.22, g, progress), Lerp(0.22, b, progress), 1)
        fill:SetVertexColor(Lerp(0.13, r, progress), Lerp(0.13, g, progress), Lerp(0.13, b, progress), Lerp(0.4, 1, progress))
        halo:SetVertexColor(r, g, b, 0.32 * progress)
        if labelFs then labelFs:SetTextColor(unpack(state.enabled and T.text.primary or T.text.muted)) end
    end

    local function Snap()
        container:SetScript("OnUpdate", nil)
        progress = state.enabled and 1 or 0
        Render()
    end

    track:SetScript("OnClick", function()
        if state.disabled then return end
        state.enabled = not state.enabled
        local from = progress
        local target = state.enabled and 1 or 0
        local start = GetTime()
        container:SetScript("OnUpdate", function(self)
            local t = (GetTime() - start) / ANIM_DURATION
            if t >= 1 then
                progress = target
                self:SetScript("OnUpdate", nil)
            else
                local eased = 1 - (1 - t) * (1 - t)
                progress = from + (target - from) * eased
            end
            Render()
        end)
        if callback then callback(state.enabled) end
    end)

    Snap()
    function container:GetValue() return state.enabled end
    function container:SetValue(val) state.enabled = val; Snap() end
    function container:SetEnabled(val) state.disabled = not val; Snap() end
    return container
end

function Controls.TabLineBar(parent, tabs, selected, callback, width)
    width = width or 400
    local BAR_ROW_HEIGHT = 32
    local container = CreateFrame("Frame", nil, parent)
    local buttons = {}
    local state = { selected = selected or 1 }

    local function UpdateAll()
        for i, btn in ipairs(buttons) do
            if i == state.selected then
                btn.text:SetTextColor(unpack(T.text.primary))
                btn.indicator:Show()
            else
                btn.text:SetTextColor(unpack(T.text.muted))
                btn.indicator:Hide()
            end
        end
    end

    local x, rowNum = 0, 0
    for i, tabText in ipairs(tabs) do
        local btn = CreateFrame("Button", nil, container)
        btn:SetHeight(BAR_ROW_HEIGHT)
        btn.text = btn:CreateFontString(nil, "OVERLAY")
        btn.text:SetFont(UI.Font, 13, "")
        btn.text:SetPoint("CENTER", 0, 2)
        btn.text:SetText(tabText)
        btn.text:SetTextColor(unpack(T.text.muted))
        local tw = btn.text:GetStringWidth() + 24

        if x + tw > width and x > 0 then
            x = 0
            rowNum = rowNum + 1
        end
        btn:SetWidth(tw)
        btn:SetPoint("TOPLEFT", x, -rowNum * BAR_ROW_HEIGHT)
        x = x + tw

        btn.indicator = UI.CreateTex(btn, UI.GetAccent())
        btn.indicator:SetHeight(2)
        btn.indicator:SetPoint("BOTTOMLEFT")
        btn.indicator:SetPoint("BOTTOMRIGHT")
        btn.indicator:Hide()

        btn:SetScript("OnClick", function()
            state.selected = i
            UpdateAll()
            if callback then callback(i) end
        end)
        btn:SetScript("OnEnter", function()
            if i ~= state.selected then btn.text:SetTextColor(unpack(T.text.secondary)) end
        end)
        btn:SetScript("OnLeave", function()
            if i ~= state.selected then btn.text:SetTextColor(unpack(T.text.muted)) end
        end)
        buttons[i] = btn
    end

    container:SetSize(width, (rowNum + 1) * BAR_ROW_HEIGHT)

    local baseLine = UI.CreateTex(container, unpack(T.border.default))
    baseLine:SetHeight(1)
    baseLine:SetPoint("BOTTOMLEFT")
    baseLine:SetPoint("BOTTOMRIGHT")

    UpdateAll()

    function container:GetSelected() return state.selected end
    function container:SetSelected(val) state.selected = val; UpdateAll() end
    return container
end

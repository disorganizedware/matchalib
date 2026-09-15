-- ============================================================
--  Matcha UI  ·  single-file loadstring build
--  loadstring(game:HttpGet("URL"))()
--  UI is exposed via getgenv().MatchaUI — Matcha drops return values
-- ============================================================

-- ---------- Matcha-safe service fetch ----------
local function svc(name)
    local ok, s = pcall(function() return game:GetService(name) end)
    if ok and s then return s end
    local ok2, s2 = pcall(function() return game:FindService(name) end)
    if ok2 and s2 then return s2 end
    return game[name]
end

local RunService = svc("RunService")
local UserInput  = svc("UserInputService")
local Players    = svc("Players")

assert(RunService, "[matcha-ui] RunService unavailable")
assert(UserInput,  "[matcha-ui] UserInputService unavailable")
assert(Players,    "[matcha-ui] Players unavailable")

local LP = Players.LocalPlayer
while not LP do
    task.wait(0.1)
    LP = Players.LocalPlayer
end

local Camera = workspace.CurrentCamera
while not Camera do
    task.wait(0.1)
    Camera = workspace.CurrentCamera
end

-- ---------- theme ----------
local Theme = {
    Bg       = Color3.fromRGB(10, 10, 15),
    Panel    = Color3.fromRGB(16, 16, 24),
    PanelAlt = Color3.fromRGB(22, 22, 32),
    Hover    = Color3.fromRGB(30, 30, 44),
    Stroke   = Color3.fromRGB(46, 46, 66),
    Text     = Color3.fromRGB(235, 235, 248),
    TextDim  = Color3.fromRGB(140, 140, 170),
    Accent   = Color3.fromRGB(122, 92, 255),
    Accent2  = Color3.fromRGB(80, 220, 255),
    Good     = Color3.fromRGB(90, 240, 160),
    Danger   = Color3.fromRGB(255, 90, 120),
}

-- ---------- helpers ----------
local function lerp(a,b,t) return a + (b-a)*t end
local function clamp(v,a,b) if v<a then return a elseif v>b then return b else return v end end
local function lerpColor(a,b,t) return Color3.new(lerp(a.R,b.R,t), lerp(a.G,b.G,t), lerp(a.B,b.B,t)) end
local function v2(x,y) return Vector2.new(x,y) end
local function inRect(px,py,x,y,w,h) return px>=x and px<=x+w and py>=y and py<=y+h end

-- ---------- renderer: tween drawing props each frame ----------
local Renderer = { items = {}, conn = nil }
function Renderer:add(draw, targets, speed)
    table.insert(self.items, { draw=draw, tgt=targets or {}, sp=speed or 0.25 })
    return draw
end
function Renderer:start()
    if self.conn then return end
    self.conn = RunService.RenderStepped:Connect(function(dt)
        local k = clamp(dt * 60 * 0.3, 0, 1)
        for _, it in ipairs(self.items) do
            local d, tg = it.draw, it.tgt
            for prop, target in pairs(tg) do
                local cur = d[prop]
                if typeof(cur)=="number" and typeof(target)=="number" then
                    d[prop] = lerp(cur, target, k)
                elseif typeof(cur)=="Color3" and typeof(target)=="Color3" then
                    d[prop] = lerpColor(cur, target, k)
                elseif typeof(cur)=="Vector2" and typeof(target)=="Vector2" then
                    d[prop] = v2(lerp(cur.X,target.X,k), lerp(cur.Y,target.Y,k))
                else
                    d[prop] = target
                end
            end
        end
    end)
end
function Renderer:stop() if self.conn then self.conn:Disconnect() self.conn=nil end end
Renderer:start()

-- ---------- state ----------
local state = {
    open = true,
    activeTab = nil,
    accentPulse = 0,
    drag = nil,
    draggingSlider = nil,
    mouseDown = false,
    mousePos = v2(0,0),
    W = 520, H = 360,
    POS = v2(80, 80),
    z = 100,
    title = "matcha // ui",
}

-- ---------- mouse ----------
local Mouse = LP:GetMouse()

local function updateMouse()
    if Mouse then
        state.mousePos = v2(Mouse.X, Mouse.Y)
    end
end

-- ---------- drawing ----------
local persistent = {}
local elements   = {}

local function killList(list)
    for _,d in ipairs(list) do if d and d.Remove then pcall(function() d:Remove() end) end end
end

-- Text uses `Size` in Matcha's runtime — that's what the docs' ESP example uses.
local function draw(class, props)
    local d = Drawing.new(class)
    for k, v in pairs(props or {}) do d[k] = v end
    d.Visible = true
    return d
end

local function drawText(props)
    return draw("Text", {
        Text     = props.Text or "",
        Position = props.Position,
        Color    = props.Color,
        Size     = props.Size or 14,
        Center   = props.Center or false,
        Outline  = props.Outline ~= false,
        Font     = props.Font or Drawing.Fonts.UI,
        ZIndex   = props.ZIndex,
    })
end

-- ============================================================
--  PUBLIC API
-- ============================================================
local UI = setmetatable({}, {})
UI.__index = UI

local tabsOrder = {}

function UI:Window(opts)
    opts = opts or {}
    if opts.Title then state.title = opts.Title end
    if opts.Size then state.W, state.H = opts.Size.X, opts.Size.Y end
    if opts.Position then state.POS = opts.Position end
    return self
end

local function newTab(name)
    local t = { name=name, elements={}, active=false }
    table.insert(tabsOrder, t)
    if not state.activeTab then state.activeTab = t t.active = true end
    return t
end

function UI:Tab(name) return newTab(name) end

function UI:Toggle(tab, name, default, cb)
    local e = { kind="Toggle", name=name, on=default and true or false, cb=cb,
                anim=0, id="tg_"..#tabsOrder.."_"..(#tab.elements+1) }
    table.insert(tab.elements, e)
    return e
end

function UI:Slider(tab, name, min, max, default, cb)
    local e = { kind="Slider", name=name, min=min, max=max,
                value=default or min, cb=cb, dragging=false,
                id="sl_"..#tabsOrder.."_"..(#tab.elements+1) }
    table.insert(tab.elements, e)
    return e
end

function UI:Button(tab, name, cb)
    local e = { kind="Button", name=name, cb=cb, press=0,
                id="bt_"..#tabsOrder.."_"..(#tab.elements+1) }
    table.insert(tab.elements, e)
    return e
end

function UI:Label(tab, name)
    local e = { kind="Label", name=name, id="lb_"..#tabsOrder.."_"..(#tab.elements+1) }
    table.insert(tab.elements, e)
    return e
end

function UI:SetAccent(c) Theme.Accent = c end
function UI:SetOpen(v) state.open = v end
function UI:ToggleOpen() state.open = not state.open end
function UI:Destroy()
    killList(persistent)
    killList(elements)
    Renderer:stop()
end

-- ============================================================
--  INPUT
-- ============================================================
local function hitLayout()
    local layout = {}
    if not state.open then return layout end
    local px, py = state.POS.X, state.POS.Y
    local W, H = state.W, state.H
    local sidebar = 170

    table.insert(layout, { id="__titlebar", ref={kind="_titlebar"}, x=px, y=py, w=W, h=46 })

    local ty = py + 60
    for _, t in ipairs(tabsOrder) do
        table.insert(layout, { id="__tab_"..t.name, ref=t, x=px+10, y=ty, w=150, h=34, kind="tab" })
        ty = ty + 40
    end

    local tab = state.activeTab
    if tab then
        local ex = px + sidebar + 14
        local ew = W - sidebar - 28
        local ey = py + 104
        for _, el in ipairs(tab.elements) do
            local hh = (el.kind=="Slider") and 48 or (el.kind=="Toggle" and 38) or (el.kind=="Button" and 40) or 24
            if el.kind ~= "Label" then
                table.insert(layout, { id=el.id, ref=el, x=ex, y=ey, w=ew, h=hh, kind=el.kind })
            end
            ey = ey + hh
        end
    end
    return layout
end

local function layoutPositions()
    local m = {}
    local px, py = state.POS.X, state.POS.Y
    local W, H = state.W, state.H
    local sidebar = 170
    m.__titlebar = {x=px,y=py,w=W,h=46}
    local ty = py + 60
    for _, t in ipairs(tabsOrder) do
        m["__tab_"..t.name] = {x=px+10,y=ty,w=150,h=34,ref=t}
        ty = ty + 40
    end
    local tab = state.activeTab
    if tab then
        local ex = px + sidebar + 14
        local ew = W - sidebar - 28
        local ey = py + 104
        for _, el in ipairs(tab.elements) do
            local hh = (el.kind=="Slider") and 48 or (el.kind=="Toggle" and 38) or (el.kind=="Button" and 40) or 24
            if el.kind ~= "Label" then
                m[el.id] = {x=ex,y=ey,w=ew,h=hh,ref=el,kind=el.kind}
            end
            ey = ey + hh
        end
    end
    return m
end

UserInput.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    updateMouse()
    state.mouseDown = true
    local mx, my = state.mousePos.X, state.mousePos.Y

    for _, hit in ipairs(hitLayout()) do
        if inRect(mx,my,hit.x,hit.y,hit.w,hit.h) then
            local ref = hit.ref
            if hit.id == "__titlebar" then
                state.drag = { offX = mx - state.POS.X, offY = my - state.POS.Y }
                return
            elseif hit.kind == "tab" then
                for _, t in ipairs(tabsOrder) do t.active = (t==ref) end
                state.activeTab = ref
                return
            elseif hit.kind == "Toggle" then
                ref.on = not ref.on
                if ref.cb then pcall(ref.cb, ref.on) end
                return
            elseif hit.kind == "Button" then
                ref.press = 1
                if ref.cb then pcall(ref.cb) end
                return
            elseif hit.kind == "Slider" then
                ref.dragging = true
                state.draggingSlider = ref
                local pct = clamp((mx - (hit.x+10)) / (hit.w-20), 0, 1)
                ref.value = ref.min + (ref.max-ref.min) * pct
                if ref.cb then pcall(ref.cb, ref.value) end
                return
            end
        end
    end
end)

UserInput.InputEnded:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    state.mouseDown = false
    state.drag = nil
    if state.draggingSlider then
        state.draggingSlider.dragging = false
        state.draggingSlider = nil
    end
end)

-- ============================================================
--  RENDER
-- ============================================================
local function drawGlow(x,y,w,h,color,layers,z)
    local out = {}
    layers = layers or 4
    for i=1,layers do
        local spread = i*6
        local alpha = 0.14/i
        table.insert(out, draw("Square", {
            Position=v2(x-spread,y-spread), Size=v2(w+spread*2,h+spread*2),
            Color=color, Transparency=1-alpha, Filled=true, ZIndex=z-i
        }))
    end
    return out
end

local function buildChrome()
    killList(persistent)
    persistent = {}
    local px, py = state.POS.X, state.POS.Y
    local W, H = state.W, state.H
    local sidebar = 170

    local g = drawGlow(px,py,W,H,Theme.Accent,5,state.z)
    for _,d in ipairs(g) do table.insert(persistent,d) end

    table.insert(persistent, draw("Square", { Position=v2(px,py), Size=v2(W,H), Color=Theme.Bg, Transparency=0.05, Filled=true, ZIndex=state.z+1 }))
    table.insert(persistent, draw("Square", { Position=v2(px,py), Size=v2(W,H), Color=Theme.Stroke, Transparency=0.5, Filled=false, ZIndex=state.z+2 }))

    table.insert(persistent, draw("Square", { Position=v2(px,py), Size=v2(W,46), Color=Theme.Panel, Transparency=0.15, Filled=true, ZIndex=state.z+3 }))
    table.insert(persistent, draw("Line", { From=v2(px+1,py+46), To=v2(px+W-1,py+46), Color=Theme.Stroke, Transparency=0.5, Thickness=1, ZIndex=state.z+4 }))

    table.insert(persistent, draw("Square", { Position=v2(px+1,py+47), Size=v2(sidebar,H-48), Color=Theme.Panel, Transparency=0.25, Filled=true, ZIndex=state.z+3 }))
    table.insert(persistent, draw("Line", { From=v2(px+sidebar+1,py+47), To=v2(px+sidebar+1,py+H-1), Color=Theme.Stroke, Transparency=0.4, Thickness=1, ZIndex=state.z+4 }))

    table.insert(persistent, drawText({ Position=v2(px+18,py+14), Text=state.title, Color=Theme.Text, Font=Drawing.Fonts.SystemBold or Drawing.Fonts.UI, Size=16, Outline=true, ZIndex=state.z+10 }))
    table.insert(persistent, drawText({ Position=v2(px+W-18,py+18), Text="v1.0", Color=Theme.TextDim, Font=Drawing.Fonts.UI, Size=12, Outline=true, ZIndex=state.z+10 }))

    local strip = draw("Square", { Position=v2(px,py), Size=v2(W,3), Color=Theme.Accent, Transparency=0.1, Filled=true, ZIndex=state.z+5 })
    table.insert(persistent, strip)
    state._strip = strip

    local ty = py + 60
    for _, t in ipairs(tabsOrder) do
        local bg = draw("Square", { Position=v2(px+10,ty), Size=v2(150,34), Color=Theme.PanelAlt, Transparency=0.35, Filled=true, ZIndex=state.z+6 })
        local br = draw("Square", { Position=v2(px+10,ty), Size=v2(150,34), Color=Theme.Stroke, Transparency=0.5, Filled=false, ZIndex=state.z+7 })
        local tx = drawText({ Position=v2(px+24,ty+9), Text=t.name, Color=Theme.TextDim, Font=Drawing.Fonts.SystemBold or Drawing.Fonts.UI, Size=14, Outline=true, ZIndex=state.z+8 })
        table.insert(persistent, bg) table.insert(persistent, br) table.insert(persistent, tx)
        t._bg, t._br, t._tx = bg, br, tx
        ty = ty + 40
    end

    table.insert(persistent, drawText({ Position=v2(px+sidebar+14,py+66), Text="", Color=Theme.Text, Font=Drawing.Fonts.SystemBold or Drawing.Fonts.UI, Size=15, Outline=true, ZIndex=state.z+8 }))
    table.insert(persistent, draw("Line", { From=v2(px+sidebar+14,py+90), To=v2(px+W-18,py+90), Color=Theme.Stroke, Transparency=0.5, Thickness=1, ZIndex=state.z+6 }))

    state._heading = persistent[#persistent-1]
end

local function buildElements()
    killList(elements)
    elements = {}
    local tab = state.activeTab
    if not tab then return end
    local px, py = state.POS.X, state.POS.Y
    local sidebar = 170
    local ex = px + sidebar + 14
    local ew = state.W - sidebar - 28
    local ey = py + 104

    for _, el in ipairs(tab.elements) do
        if el.kind == "Toggle" then
            el._bg = draw("Square", { Position=v2(ex,ey), Size=v2(ew,30), Color=Theme.PanelAlt, Transparency=0.4, Filled=true, ZIndex=state.z+6 })
            el._tx = drawText({ Position=v2(ex+10,ey+8), Text=el.name, Color=Theme.Text, Font=Drawing.Fonts.UI, Size=13, Outline=true, ZIndex=state.z+8 })
            el._track = draw("Square", { Position=v2(ex+ew-42,ey+7), Size=v2(32,16), Color=Theme.Stroke, Transparency=0.5, Filled=true, ZIndex=state.z+7 })
            el._knob  = draw("Square", { Position=v2(ex+ew-42,ey+7), Size=v2(16,16), Color=Theme.TextDim, Transparency=0.15, Filled=true, ZIndex=state.z+8 })
            table.insert(elements, el._bg) table.insert(elements, el._tx) table.insert(elements, el._track) table.insert(elements, el._knob)
            ey = ey + 38
        elseif el.kind == "Slider" then
            el._bg = draw("Square", { Position=v2(ex,ey), Size=v2(ew,40), Color=Theme.PanelAlt, Transparency=0.4, Filled=true, ZIndex=state.z+6 })
            el._tx = drawText({ Position=v2(ex+10,ey+6), Text=el.name, Color=Theme.Text, Font=Drawing.Fonts.UI, Size=13, Outline=true, ZIndex=state.z+8 })
            el._val= drawText({ Position=v2(ex+ew-10,ey+6), Text=tostring(math.floor(el.value)), Color=Theme.Accent2, Font=Drawing.Fonts.SystemBold or Drawing.Fonts.UI, Size=13, Center=true, Outline=true, ZIndex=state.z+8 })
            el._bar= draw("Square", { Position=v2(ex+10,ey+24), Size=v2(ew-20,6), Color=Theme.Stroke, Transparency=0.4, Filled=true, ZIndex=state.z+7 })
            el._fill=draw("Square", { Position=v2(ex+10,ey+24), Size=v2(0,6), Color=Theme.Accent, Transparency=0.1, Filled=true, ZIndex=state.z+8 })
            el._knobS=draw("Square", { Position=v2(ex+10,ey+20), Size=v2(8,14), Color=Theme.Text, Transparency=0.1, Filled=true, ZIndex=state.z+9 })
            table.insert(elements, el._bg) table.insert(elements, el._tx) table.insert(elements, el._val)
            table.insert(elements, el._bar) table.insert(elements, el._fill) table.insert(elements, el._knobS)
            ey = ey + 48
        elseif el.kind == "Button" then
            el._bg = draw("Square", { Position=v2(ex,ey), Size=v2(ew,32), Color=Theme.Accent, Transparency=0.25, Filled=true, ZIndex=state.z+6 })
            el._br = draw("Square", { Position=v2(ex,ey), Size=v2(ew,32), Color=Theme.Accent, Transparency=0.05, Filled=false, ZIndex=state.z+7 })
            el._tx = drawText({ Position=v2(ex+ew/2,ey+9), Text=el.name, Color=Theme.Text, Font=Drawing.Fonts.SystemBold or Drawing.Fonts.UI, Size=14, Center=true, Outline=true, ZIndex=state.z+8 })
            table.insert(elements, el._bg) table.insert(elements, el._br) table.insert(elements, el._tx)
            ey = ey + 40
        elseif el.kind == "Label" then
            el._tx = drawText({ Position=v2(ex+4,ey+4), Text=el.name, Color=Theme.TextDim, Font=Drawing.Fonts.UI, Size=13, Outline=true, ZIndex=state.z+7 })
            table.insert(elements, el._tx)
            ey = ey + 24
        end
    end
end

local lastTab, lastOpen
RunService.RenderStepped:Connect(function()
    if lastTab ~= state.activeTab or lastOpen ~= state.open then
        buildChrome()
        buildElements()
        lastTab, lastOpen = state.activeTab, state.open
    end
end)

RunService.RenderStepped:Connect(function(dt)
    updateMouse()
    local mx, my = state.mousePos.X, state.mousePos.Y

    if not state.open then
        for _,d in ipairs(persistent) do d.Visible = false end
        for _,d in ipairs(elements) do d.Visible = false end
        return
    end
    for _,d in ipairs(persistent) do d.Visible = true end
    for _,d in ipairs(elements) do d.Visible = true end

    if state.drag and state.mouseDown then
        state.POS = v2(mx - state.drag.offX, my - state.drag.offY)
        buildChrome()
        buildElements()
    end

    if state.draggingSlider and state.mouseDown then
        local s = state.draggingSlider
        local m = layoutPositions()[s.id]
        if m then
            local pct = clamp((mx - (m.x+10)) / (m.w-20), 0, 1)
            s.value = s.min + (s.max-s.min) * pct
            if s.cb then pcall(s.cb, s.value) end
        end
    end

    state.accentPulse = (state.accentPulse + dt * 1.8) % (math.pi*2)
    local pulse = 0.5 + 0.5*math.sin(state.accentPulse)
    local acc = lerpColor(Theme.Accent, Theme.Accent2, pulse)
    if state._strip then state._strip.Color = acc end

    for _, t in ipairs(tabsOrder) do
        local active = (t == state.activeTab)
        local hov = inRect(mx,my,state.POS.X+10, (t._bg and t._bg.Position.Y) or 0, 150, 34)
        if t._bg then
            t._bg.Color = active and Theme.Accent or (hov and Theme.Hover or Theme.PanelAlt)
            t._bg.Transparency = active and 0.75 or 0.35
            t._br.Color = active and Theme.Accent or Theme.Stroke
            t._tx.Color = active and Theme.Text or (hov and Theme.Text or Theme.TextDim)
        end
    end

    if state._heading and state.activeTab then
        state._heading.Text = string.upper(state.activeTab.name)
    end

    if state.activeTab then
        local m = layoutPositions()
        for _, el in ipairs(state.activeTab.elements) do
            local pos = m[el.id]
            if pos then
                local hov = inRect(mx,my,pos.x,pos.y,pos.w,pos.h)
                if el.kind == "Toggle" then
                    el.anim = lerp(el.anim or 0, el.on and 1 or 0, clamp(dt*12,0,1))
                    el._knob.Position = v2(pos.x + pos.w - 42 + (el.anim*16), pos.y+7)
                    el._knob.Color = lerpColor(Theme.TextDim, Theme.Accent, el.anim)
                    el._track.Color = lerpColor(Theme.Stroke, Theme.Accent, el.anim)
                    el._track.Transparency = lerp(0.5, 0.1, el.anim)
                    el._bg.Color = hov and Theme.Hover or Theme.PanelAlt
                elseif el.kind == "Slider" then
                    local pct = (el.value - el.min) / (el.max - el.min)
                    local barW = pos.w - 20
                    el._fill.Size = v2(barW*pct, 6)
                    el._knobS.Position = v2(pos.x + 10 + barW*pct - 4, pos.y+20)
                    el._val.Text = tostring(math.floor(el.value))
                    el._bg.Color = hov and Theme.Hover or Theme.PanelAlt
                elseif el.kind == "Button" then
                    el.press = math.max(0, (el.press or 0) - dt*4)
                    el._bg.Transparency = hov and 0.1 or 0.25
                    el._tx.Position = v2(pos.x + pos.w/2, pos.y + 9 + el.press*2)
                end
            end
        end
    end
end)

-- ============================================================
--  BOOT
-- ============================================================
buildChrome()
buildElements()

-- Matcha drops loadstring return values — expose via getgenv()
getgenv().MatchaUI = UI

print("[matcha-ui] loaded · getgenv().MatchaUI ready")

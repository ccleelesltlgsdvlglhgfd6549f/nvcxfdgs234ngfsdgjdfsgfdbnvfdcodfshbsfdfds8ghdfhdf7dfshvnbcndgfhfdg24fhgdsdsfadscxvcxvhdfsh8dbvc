getgenv().MenuKey = Enum.KeyCode.RightControl

--//------------------------------------------------------------------------------------------\\--

if not game:IsLoaded() then game.Loaded:Wait() end

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local TextChatService = game:GetService("TextChatService")
local RS = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

if getgenv().StandCleanup then pcall(getgenv().StandCleanup) end
if getgenv().LinaUI then pcall(function() getgenv().LinaUI:Destroy() end) end

local TITLE_NAME = "lina's stand control cmd"
local startTime = os.time()

local conns = {}
local function connect(sig, fn)
    local c = sig:Connect(fn)
    table.insert(conns, c)
    return c
end

local function HRP()
    local c = LocalPlayer.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end
local function Hum()
    local c = LocalPlayer.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end

-- forward declarations
local visualCleanup
local showPage, paintVisuals
local page = "main"

-- GUI parent (with fallbacks)
local parent
pcall(function() if gethui then parent = gethui() end end)
if not parent then pcall(function() parent = game:GetService("CoreGui") end) end
if not parent then parent = Players.LocalPlayer:WaitForChild("PlayerGui") end

local gui = Instance.new("ScreenGui")
gui.Name = TITLE_NAME
gui.ResetOnSpawn = false
gui.DisplayOrder = 999
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function() if syn and syn.protect_gui then syn.protect_gui(gui) end end)
gui.Parent = parent
getgenv().LinaUI = gui
print("[Stand] GUI loaded, parent:", parent:GetFullName())

getgenv().StandCleanup = function()
    pcall(function() if visualCleanup then visualCleanup() end end)
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    conns = {}
    if gui then gui:Destroy() end
end

-- ===================== FLOATING .gg/standd (single, small, drifts around the screen) =====================
do
    local W, H = 104, 20
    local floatLbl = Instance.new("TextLabel")
    floatLbl.Name = "StandFloat"
    floatLbl.Size = UDim2.fromOffset(W, H)
    floatLbl.BackgroundTransparency = 1
    floatLbl.Text = ".gg/standd"
    floatLbl.Font = Enum.Font.Code
    floatLbl.TextSize = 16
    floatLbl.TextXAlignment = Enum.TextXAlignment.Left
    floatLbl.TextTransparency = 0.15
    floatLbl.TextColor3 = Color3.fromHSV(0, 0.55, 1)
    floatLbl.Active = false -- never blocks clicks
    floatLbl.ZIndex = 50
    floatLbl.Parent = gui

    local fpos, fvel, ft = Vector2.new(60, 80), Vector2.new(55, 38), 0
    connect(RunService.Heartbeat, function(dt)
        local view = gui.AbsoluteSize
        if view.X < 200 or view.Y < 200 then
            local cam = workspace.CurrentCamera
            if cam then view = cam.ViewportSize end
        end
        dt = math.min(dt, 0.1)
        ft = ft + dt
        fpos = fpos + fvel * dt
        local maxX, maxY = math.max(view.X - W, 1), math.max(view.Y - H, 1)
        if fpos.X < 0 then
            fpos = Vector2.new(0, fpos.Y)
            fvel = Vector2.new(math.abs(fvel.X), fvel.Y)
        elseif fpos.X > maxX then
            fpos = Vector2.new(maxX, fpos.Y)
            fvel = Vector2.new(-math.abs(fvel.X), fvel.Y)
        end
        if fpos.Y < 0 then
            fpos = Vector2.new(fpos.X, 0)
            fvel = Vector2.new(fvel.X, math.abs(fvel.Y))
        elseif fpos.Y > maxY then
            fpos = Vector2.new(fpos.X, maxY)
            fvel = Vector2.new(fvel.X, -math.abs(fvel.Y))
        end
        floatLbl.Position = UDim2.fromOffset(fpos.X, fpos.Y)
        floatLbl.TextColor3 = Color3.fromHSV((ft * 0.08) % 1, 0.55, 1)
    end)
end

-- Sends a message to chat
local function say(msg)
    local ok = pcall(function()
        if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
            TextChatService.TextChannels.RBXGeneral:SendAsync(msg)
        else
            RS.DefaultChatSystemChatEvents.SayMessageRequest:FireServer(msg, "All")
        end
    end)
    if not ok then warn("[Stand] Could not send chat message") end
end

-- ===================== EMOTES =====================
local EMOTES = {
    { name = "Take the L", id = "74430100028293" },
    { name = "Gamgam Style", id = "129764254213842" },
    { name = "Fly", id = "77529400769588" },
    { name = "Zombie Walk", id = "81931167118728" },
    { name = "Jamal Brasil", id = "83796130837213" },
    { name = "Insane Bug", id = "86036950557685" },
    { name = "Kick", id = "92249489340640" },
    { name = "Mini Box", id = "113994067684875" },
}

-- "!dance jamal" -> "!dance 83796130837213" (bots receive the id)
local function resolveDance(text)
    local at, rest = text:match("^(@%S+%s+)(.*)$")
    if not at then at, rest = "", text end
    local arg = rest:match("^!dance%s+(.+)$")
    if not arg then return text end
    local a = (arg:lower():gsub("%s+$", ""))
    for _, e in ipairs(EMOTES) do
        local n = e.name:lower()
        local nospace = (n:gsub("%s", ""))
        local first = n:match("^(%S+)")
        if a == n or a == nospace or a == first or a == e.id then
            if e.id == "83796130837213" then return at .. "!dance" end
            return at .. "!dance " .. e.id
        end
    end
    return text
end

-- ===================== STAND BRIDGE (command queue) =====================
local CHANNEL = "stand_cmd.json"
local MAX_QUEUE = 30
local queue, seq = {}, 0
local selectedBots = {} -- [name] = true  (target bots selected from the bot panel)

pcall(function()
    if type(isfile) == "function" and isfile(CHANNEL) then
        local d = HttpService:JSONDecode(readfile(CHANNEL))
        if type(d) == "table" and type(d.seq) == "number" then seq = d.seq end
    end
end)

-- Target priority: "@name ..." > bots selected in the bot panel > all
local function sendToStand(text)
    local to, msg = "all", text
    local t, rest = text:match("^@(%S+)%s+(.+)$")
    if t then
        to, msg = t, rest
    elseif next(selectedBots) then
        local names = {}
        for name in pairs(selectedBots) do table.insert(names, name) end
        table.sort(names)
        to = table.concat(names, ",")
    end
    seq = seq + 1
    table.insert(queue, { n = seq, to = to, msg = msg })
    while #queue > MAX_QUEUE do table.remove(queue, 1) end
    local ok = pcall(writefile, CHANNEL, HttpService:JSONEncode({ seq = seq, cmds = queue }))
    if not ok then warn("[Stand] Could not write command file") end
end

-- Chat mode: when on, commands go to chat; commands starting with "@name ..." still go through the bridge to that account
local chatMode = false
local function dispatch(text)
    if chatMode and not text:match("^@%S+%s+.+$") then
        say(text)
    else
        sendToStand(resolveDance(text))
    end
end

-- ===================== CONNECTED BOTS =====================
local BOT_DIR = "stand_bots"
local BOT_TTL = 6
local BOT_HIDE = 300
local bots = {}

pcall(function()
    if type(makefolder) == "function" and type(isfolder) == "function" and not isfolder(BOT_DIR) then
        makefolder(BOT_DIR)
    end
end)

local function refreshBots()
    if type(listfiles) ~= "function" or type(isfolder) ~= "function" or not isfolder(BOT_DIR) then return end
    local ok, files = pcall(listfiles, BOT_DIR)
    if not ok or type(files) ~= "table" then return end
    local now = os.time()
    local seen = {}
    for _, path in ipairs(files) do
        local ok2, data = pcall(function() return HttpService:JSONDecode(readfile(path)) end)
        if ok2 and type(data) == "table" and type(data.name) == "string" and type(data.ts) == "number" then
            local age = now - data.ts
            if age <= BOT_HIDE then
                seen[data.name] = true
                bots[data.name] = { on = age <= BOT_TTL, ts = data.ts, role = data.role }
            end
        end
    end
    for name in pairs(bots) do
        if not seen[name] then
            bots[name] = nil
            selectedBots[name] = nil
        end
    end
end

local function sortedBots(onlyOn)
    local t = {}
    for name, b in pairs(bots) do
        if not onlyOn or b.on then table.insert(t, name) end
    end
    table.sort(t, function(a, b) return a:lower() < b:lower() end)
    return t
end
-- =======================================================================

local function corner(o, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 8)
    c.Parent = o
end

local PINK = Color3.fromHex("F2BDCD") -- only used by the visuals page
local WHITE = Color3.fromRGB(235, 235, 240)
local GREEN = Color3.fromRGB(110, 230, 140)
local RED = Color3.fromRGB(235, 100, 110)
local BLUE = Color3.fromRGB(90, 160, 255)

-- ===================== ACTIVE BOTS + ROLE (bottom right, small) =====================
-- green = innocent, red = murderer, blue = sheriff
local BOT_ROLE_COLORS = { murderer = RED, sheriff = BLUE, innocent = GREEN }

local roleBox = Instance.new("Frame")
roleBox.Name = "BotRoles"
roleBox.AnchorPoint = Vector2.new(1, 1)
roleBox.Position = UDim2.new(1, -10, 1, -10)
roleBox.Size = UDim2.fromOffset(200, 0)
roleBox.AutomaticSize = Enum.AutomaticSize.Y
roleBox.BackgroundTransparency = 1
roleBox.Active = false
roleBox.ZIndex = 50
roleBox.Parent = gui
local roleList = Instance.new("UIListLayout")
roleList.SortOrder = Enum.SortOrder.LayoutOrder
roleList.HorizontalAlignment = Enum.HorizontalAlignment.Right
roleList.Padding = UDim.new(0, 1)
roleList.Parent = roleBox

local lastRoleSig = ""
local function renderRoleBox()
    local list = sortedBots(true)
    local parts = {}
    for _, name in ipairs(list) do
        table.insert(parts, name .. ":" .. tostring(bots[name].role))
    end
    local sig = table.concat(parts, "|")
    if sig == lastRoleSig then return end
    lastRoleSig = sig
    for _, c in ipairs(roleBox:GetChildren()) do
        if c:IsA("TextLabel") then c:Destroy() end
    end
    for i, name in ipairs(list) do
        local role = tostring(bots[name].role or "innocent"):lower()
        local lbl = Instance.new("TextLabel")
        lbl.LayoutOrder = i
        lbl.Size = UDim2.new(1, 0, 0, 14)
        lbl.BackgroundTransparency = 1
        lbl.Active = false
        lbl.Font = Enum.Font.Code
        lbl.TextSize = 12
        lbl.TextXAlignment = Enum.TextXAlignment.Right
        lbl.TextStrokeTransparency = 0.5
        lbl.TextColor3 = BOT_ROLE_COLORS[role] or GREEN
        lbl.Text = name
        lbl.ZIndex = 50
        lbl.Parent = roleBox
    end
end

-- ===================== VISUALS (this client only) =====================
local AURA_ASSETS = {
    starlight = "rbxassetid://134645216613107",
    heavenly = "rbxassetid://139300897520961",
    ribbon = "rbxassetid://132069507632161",
    sakura = "rbxassetid://81755778619404",
    angel = "rbxassetid://97658130917593",
    wind = "rbxassetid://80694081850877",
    flow = "rbxassetid://119913533725648",
    star = "rbxassetid://73754563740680",
}
local AURA_NAMES = { "angel", "starlight", "heavenly", "ribbon", "sakura", "wind", "flow", "star" }
local auraAssets, auraSel, auraParts = {}, {}, {}
local auraRev = 0

local function loadAura(name)
    if auraAssets[name] ~= nil then return auraAssets[name] or nil end
    local ok, obj = pcall(function() return game:GetObjects(AURA_ASSETS[name])[1] end)
    auraAssets[name] = (ok and obj) or false
    return auraAssets[name] or nil
end

local function clearAuras()
    for _, p in ipairs(auraParts) do pcall(function() p:Destroy() end) end
    auraParts = {}
end

local MAX_AURAS = 3 -- stacking more than this is what tanks the framerate
local function applyAuras()
    auraRev = auraRev + 1
    local myRev = auraRev
    clearAuras()
    local char = LocalPlayer.Character
    if not char then return end
    local used = 0
    for name in pairs(auraSel) do
        if used >= MAX_AURAS then break end
        local asset = loadAura(name)
        if myRev ~= auraRev then return end
        if asset then
            used = used + 1
            local clone = asset:Clone()
            -- drop anything that can run code, and throttle the particles
            for _, d in ipairs(clone:GetDescendants()) do
                if d:IsA("LuaSourceContainer") or d:IsA("Sound") then
                    d:Destroy()
                elseif d:IsA("ParticleEmitter") then
                    d.Rate = math.min(d.Rate, 12)
                    d.Lifetime = NumberRange.new(math.min(d.Lifetime.Min, 2), math.min(d.Lifetime.Max, 2))
                elseif d:IsA("Light") then
                    d.Shadows = false
                end
            end
            for _, part in ipairs(clone:GetChildren()) do
                local target = char:FindFirstChild(part.Name)
                if target then
                    for _, child in ipairs(part:GetChildren()) do
                        local c = child:Clone()
                        c.Parent = target
                        table.insert(auraParts, c)
                    end
                end
            end
            clone:Destroy()
        end
    end
end

local function toggleAura(name)
    auraSel[name] = (not auraSel[name]) or nil
    if paintVisuals then paintVisuals() end
    task.spawn(applyAuras)
end

local function clearAuraSel()
    auraSel = {}
    if paintVisuals then paintVisuals() end
    task.spawn(applyAuras)
end

-- RTX
local RTX_PROPS = { "Brightness", "ColorShift_Bottom", "ColorShift_Top", "OutdoorAmbient", "ClockTime",
    "FogColor", "FogEnd", "FogStart", "ExposureCompensation", "ShadowSoftness", "Ambient" }
local rtxOn, rtxOrig, rtxObjs = false, nil, {}

local function setRTX(on)
    rtxOn = on
    for _, o in ipairs(rtxObjs) do pcall(function() o:Destroy() end) end
    rtxObjs = {}
    if not on then
        if rtxOrig then
            for k, v in pairs(rtxOrig) do pcall(function() Lighting[k] = v end) end
            rtxOrig = nil
        end
        if paintVisuals then paintVisuals() end
        return
    end
    if not rtxOrig then
        rtxOrig = {}
        for _, k in ipairs(RTX_PROPS) do rtxOrig[k] = Lighting[k] end
    end
    local bloom = Instance.new("BloomEffect")
    bloom.Name = "Bloom (Lina RTX)"
    bloom.Intensity = 0.1
    bloom.Threshold = 0
    bloom.Size = 100
    bloom.Parent = Lighting
    table.insert(rtxObjs, bloom)
    local rays = Instance.new("SunRaysEffect")
    rays.Name = "SunRays (Lina RTX)"
    rays.Intensity = 0.15
    rays.Spread = 0.8
    rays.Parent = Lighting
    table.insert(rtxObjs, rays)
    local cc = Instance.new("ColorCorrectionEffect")
    cc.Name = "ColorCorrection (Lina RTX)"
    cc.Saturation = 0.15
    cc.Contrast = 0.1
    cc.Parent = Lighting
    table.insert(rtxObjs, cc)
    Lighting.Brightness = 2.14
    Lighting.ColorShift_Bottom = Color3.fromRGB(11, 0, 20)
    Lighting.ColorShift_Top = Color3.fromRGB(240, 127, 14)
    Lighting.OutdoorAmbient = Color3.fromRGB(34, 0, 49)
    Lighting.ClockTime = 6.7
    Lighting.FogColor = Color3.fromRGB(94, 76, 106)
    Lighting.FogEnd = 1000
    Lighting.FogStart = 0
    Lighting.ExposureCompensation = 0.24
    Lighting.ShadowSoftness = 0
    Lighting.Ambient = Color3.fromRGB(59, 33, 27)
    if paintVisuals then paintVisuals() end
end

-- Custom skybox
local SKY_ORDER = { "Sunset", "Night", "Minecraft", "Evening", "Purple", "Pink", "Chill" }
local SKYBOXES = {
    Sunset = { Bk = "http://www.roblox.com/asset/?id=458016711", Dn = "http://www.roblox.com/asset/?id=458016826", Ft = "http://www.roblox.com/asset/?id=458016532", Lf = "http://www.roblox.com/asset/?id=458016655", Rt = "http://www.roblox.com/asset/?id=458016782", Up = "http://www.roblox.com/asset/?id=458016792" },
    Night = { Bk = "rbxassetid://48020371", Dn = "rbxassetid://48020144", Ft = "rbxassetid://48020234", Lf = "rbxassetid://48020211", Rt = "rbxassetid://48020254", Up = "rbxassetid://48020383" },
    Minecraft = { Bk = "rbxassetid://1876545003", Dn = "rbxassetid://1876544331", Ft = "rbxassetid://1876542941", Lf = "rbxassetid://1876543392", Rt = "rbxassetid://1876543764", Up = "rbxassetid://1876544642" },
    Evening = { Bk = "http://www.roblox.com/asset/?id=7950569153", Dn = "http://www.roblox.com/asset/?id=7950570785", Ft = "http://www.roblox.com/asset/?id=7950572449", Lf = "http://www.roblox.com/asset/?id=7950573918", Rt = "http://www.roblox.com/asset/?id=7950575055", Up = "http://www.roblox.com/asset/?id=7950627627" },
    Purple = { Bk = "rbxassetid://159454299", Dn = "rbxassetid://159454296", Ft = "rbxassetid://159454293", Lf = "rbxassetid://159454286", Rt = "rbxassetid://159454300", Up = "rbxassetid://159454288" },
    Pink = { Bk = "rbxassetid://271042516", Dn = "rbxassetid://271077243", Ft = "rbxassetid://271042556", Lf = "rbxassetid://271042310", Rt = "rbxassetid://271042467", Up = "rbxassetid://271077958" },
    Chill = { Bk = "rbxassetid://5084575798", Dn = "rbxassetid://5084575916", Ft = "rbxassetid://5103949679", Lf = "rbxassetid://5103948542", Rt = "rbxassetid://5103948784", Up = "rbxassetid://5084576400" },
}
local skyOn, skyType, skyOrig, skyMade = false, "Sunset", nil, nil

local function baseSky()
    for _, o in ipairs(Lighting:GetChildren()) do
        if o:IsA("Sky") and o ~= skyMade then return o end
    end
    return nil
end

local function setSky(on, typ)
    if typ then skyType = typ end
    skyOn = on
    if on then
        local data = SKYBOXES[skyType]
        if not data then return end
        local sky = baseSky()
        if sky then
            if not skyOrig then
                skyOrig = { sky = sky, Bk = sky.SkyboxBk, Dn = sky.SkyboxDn, Ft = sky.SkyboxFt,
                    Lf = sky.SkyboxLf, Rt = sky.SkyboxRt, Up = sky.SkyboxUp }
            end
        else
            if not skyMade then
                skyMade = Instance.new("Sky")
                skyMade.Name = "LinaSky"
                skyMade.Parent = Lighting
            end
            sky = skyMade
        end
        sky.SkyboxBk = data.Bk
        sky.SkyboxDn = data.Dn
        sky.SkyboxFt = data.Ft
        sky.SkyboxLf = data.Lf
        sky.SkyboxRt = data.Rt
        sky.SkyboxUp = data.Up
    else
        if skyOrig and skyOrig.sky and skyOrig.sky.Parent then
            local s = skyOrig.sky
            s.SkyboxBk = skyOrig.Bk
            s.SkyboxDn = skyOrig.Dn
            s.SkyboxFt = skyOrig.Ft
            s.SkyboxLf = skyOrig.Lf
            s.SkyboxRt = skyOrig.Rt
            s.SkyboxUp = skyOrig.Up
        end
        skyOrig = nil
        if skyMade then skyMade:Destroy() skyMade = nil end
    end
    if paintVisuals then paintVisuals() end
end

-- ===================== REMOTE HOOKS (round events, MM2) =====================
local remoteFns, remoteHooked = {}, {}
local function getRemote(nm)
    local rem = RS:FindFirstChild("Remotes")
    local gp = rem and rem:FindFirstChild("Gameplay")
    return gp and gp:FindFirstChild(nm)
end
local function onRemote(nm, fn)
    remoteFns[nm] = remoteFns[nm] or {}
    table.insert(remoteFns[nm], fn)
end
local function hookRemotes()
    for nm, fns in pairs(remoteFns) do
        local r = getRemote(nm)
        if r and r:IsA("RemoteEvent") and not remoteHooked[r] then
            remoteHooked[r] = true
            connect(r.OnClientEvent, function(...)
                for _, f in ipairs(fns) do pcall(f, ...) end
            end)
        end
    end
end

-- ===================== ROLES + ESP (main account, this client only) =====================
local ROLE_COLORS = {
    Murderer = Color3.fromRGB(255, 0, 0),
    Sheriff = Color3.fromRGB(0, 132, 255),
    Hero = Color3.fromRGB(255, 200, 0),
    Innocent = Color3.fromRGB(56, 255, 112),
}
local ROLE_ORDER = { "Murderer", "Sheriff", "Innocent", "Hero" }
local roleCache, roundActive = {}, false
local espOn, espNames = false, false
local espHL, espTags = {}, {}

local function hasTool(parentObj, nm)
    if not parentObj then return false end
    for _, t in ipairs(parentObj:GetChildren()) do
        if t:IsA("Tool") and t.Name:lower():find(nm, 1, true) then return true end
    end
    return false
end
local function scanRole(p)
    local bp = p:FindFirstChildOfClass("Backpack")
    if hasTool(p.Character, "knife") or hasTool(bp, "knife") then return "Murderer" end
    if hasTool(p.Character, "gun") or hasTool(bp, "gun") then return "Sheriff" end
    return nil
end
local function normRole(r)
    r = tostring(r):lower()
    if r == "murderer" then return "Murderer" end
    if r == "sheriff" then return "Sheriff" end
    if r == "hero" then return "Hero" end
    return "Innocent"
end
-- Tools seen on the player always win over the cached role:
--   knife -> Murderer | gun -> Sheriff (original sheriff) or Hero (someone else holding the gun)
local function getRole(p)
    local bp = p:FindFirstChildOfClass("Backpack")
    local hasKnife = hasTool(p.Character, "knife") or hasTool(bp, "knife")
    local hasGun = hasTool(p.Character, "gun") or hasTool(bp, "gun")
    local c = roleCache[p.Name]
    local base = c and c.Role or nil
    if hasKnife then
        roleCache[p.Name] = { Role = "Murderer", Dead = false }
        return "Murderer"
    end
    if base == "Murderer" then return "Murderer" end
    if hasGun then
        if base == nil then
            roleCache[p.Name] = { Role = "Sheriff", Dead = false }
            return "Sheriff"
        end
        if base == "Sheriff" then return "Sheriff" end
        return "Hero"
    end
    return base or "Innocent"
end

onRemote("Fade", function(...)
    local fresh, found = {}, false
    for _, arg in ipairs({ ... }) do
        if type(arg) == "table" then
            for name, info in pairs(arg) do
                if type(name) == "string" and type(info) == "table" and info.Role then
                    fresh[name] = { Role = normRole(info.Role), Dead = info.Dead or false }
                    found = true
                end
            end
        end
    end
    roundActive = true
    if found then
        for name, info in pairs(fresh) do roleCache[name] = info end
    end
end)
onRemote("RoundEndFade", function()
    roundActive = false
    roleCache = {}
end)

local function clearESPFor(p)
    if espHL[p] then pcall(function() espHL[p]:Destroy() end) espHL[p] = nil end
    if espTags[p] then pcall(function() espTags[p]:Destroy() end) espTags[p] = nil end
end

local function applyESPFor(p)
    if p == LocalPlayer then return end
    local char = p.Character
    if not char then clearESPFor(p) return end
    local c = roleCache[p.Name]
    if c and c.Dead then clearESPFor(p) return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum and hum.Health <= 0 then clearESPFor(p) return end

    local role = getRole(p)
    local col = ROLE_COLORS[role] or ROLE_COLORS.Innocent

    local hl = espHL[p]
    if espOn then
        if not hl or not hl.Parent or hl.Parent ~= char then
            if hl then hl:Destroy() end
            hl = Instance.new("Highlight")
            hl.Name = "LinaESP"
            hl.FillTransparency = 0.78
            hl.OutlineTransparency = 0.45
            hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            hl.Parent = char
            espHL[p] = hl
        end
        hl.FillColor = col
        hl.OutlineColor = col
    elseif hl then
        hl:Destroy()
        espHL[p] = nil
    end

    local tag = espTags[p]
    local head = char:FindFirstChild("Head")
    if espNames and head then
        if not tag or not tag.Parent or tag.Parent ~= head then
            if tag then tag:Destroy() end
            tag = Instance.new("BillboardGui")
            tag.Name = "LinaTag"
            tag.AlwaysOnTop = true
            tag.Size = UDim2.fromOffset(140, 16)
            tag.StudsOffset = Vector3.new(0, 2.2, 0)
            tag.Parent = head
            local l = Instance.new("TextLabel")
            l.Name = "L"
            l.Size = UDim2.fromScale(1, 1)
            l.BackgroundTransparency = 1
            l.Font = Enum.Font.SourceSans
            l.TextSize = 13
            l.TextStrokeTransparency = 0.85
            l.Text = p.Name
            l.Parent = tag
            espTags[p] = tag
        end
        local l = tag:FindFirstChild("L")
        if l then l.TextColor3 = col end
    elseif tag then
        tag:Destroy()
        espTags[p] = nil
    end
end

local function clearAllESP()
    for _, p in ipairs(Players:GetPlayers()) do clearESPFor(p) end
    espHL, espTags = {}, {}
end

local function setESP(hl, names)
    espOn, espNames = hl and true or false, names and true or false
    if not espOn and not espNames then clearAllESP() end
    if paintVisuals then paintVisuals() end
end

connect(Players.PlayerRemoving, function(p) clearESPFor(p) end)

local function watchESP(p)
    if p == LocalPlayer then return end
    connect(p.CharacterAdded, function() clearESPFor(p) end)
    connect(p.CharacterRemoving, function() clearESPFor(p) end)
end
for _, p in ipairs(Players:GetPlayers()) do watchESP(p) end
connect(Players.PlayerAdded, watchESP)

task.spawn(function()
    while gui.Parent do
        task.wait(0.5)
        if espOn or espNames then
            if not roundActive then
                for _, p in ipairs(Players:GetPlayers()) do
                    if p ~= LocalPlayer and scanRole(p) then
                        roundActive = true
                        break
                    end
                end
            end
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LocalPlayer then
                    if roundActive then pcall(applyESPFor, p) else clearESPFor(p) end
                end
            end
        end
    end
end)

-- ===================== CHINA HAT (this client only) =====================
local hatOn, hatColor = false, Color3.fromRGB(255, 123, 123)
local hatPart, hatLight = nil, nil

local function clearHat()
    if hatPart then pcall(function() hatPart:Destroy() end) end
    hatPart, hatLight = nil, nil
end

local function applyHat()
    clearHat()
    if not hatOn then return end
    local char = LocalPlayer.Character
    local head = char and char:FindFirstChild("Head")
    if not head then return end
    local hat = Instance.new("Part")
    hat.Name = "ChinaHat"
    hat.Size = Vector3.new(1, 1, 1)
    hat.Color = hatColor
    hat.Material = Enum.Material.Neon
    hat.Transparency = 0.2
    hat.CanCollide = false
    hat.Massless = true
    hat.Anchored = false
    hat.Parent = char
    local mesh = Instance.new("SpecialMesh")
    mesh.MeshType = Enum.MeshType.FileMesh
    mesh.MeshId = "rbxassetid://1033714"
    mesh.Scale = Vector3.new(1.7, 1.1, 1.7)
    mesh.Parent = hat
    local weld = Instance.new("Weld")
    weld.Part0 = head
    weld.Part1 = hat
    weld.C0 = CFrame.new(0, 0.9, 0)
    weld.Parent = hat
    local light = Instance.new("PointLight")
    light.Color = hatColor
    light.Brightness = 1
    light.Range = 12
    light.Shadows = true
    light.Parent = hat
    hatPart, hatLight = hat, light
end

local function setHat(on)
    hatOn = on and true or false
    applyHat()
    if paintVisuals then paintVisuals() end
end

local function setHatColor(c)
    hatColor = c
    if hatPart and hatPart.Parent then hatPart.Color = c end
    if hatLight and hatLight.Parent then hatLight.Color = c end
end

connect(LocalPlayer.CharacterAdded, function()
    task.wait(0.6)
    if hatOn then applyHat() end
end)

-- ===================== WEATHER (this client only) =====================
local function kp(t, v) return NumberSequenceKeypoint.new(t, v) end
local WEATHER_ORDER = { "LightRain", "Rain", "Snow", "Snowball" }
local WEATHER_LABELS = { LightRain = "Light Rain", Rain = "Rain", Snow = "Snow", Snowball = "Snowball" }
local WEATHER_CONFIGS = {
    Rain = { BaseRate = 1500, Texture = "rbxassetid://1822883048", Speed = NumberRange.new(120, 180), Lifetime = NumberRange.new(2.5, 3.5), Size = NumberSequence.new({ kp(0, 0.8), kp(0.5, 0.9), kp(1, 0.7) }), SpreadAngle = Vector2.new(12, 12), Acceleration = Vector3.new(0, -30, 0), Transparency = NumberSequence.new({ kp(0, 0.1), kp(0.7, 0.3), kp(1, 1) }), EmissionDirection = Enum.NormalId.Bottom, LightEmission = 0.3, LightInfluence = 0.4 },
    Snow = { BaseRate = 150, Texture = "rbxassetid://605668174", SpreadAngle = Vector2.new(40, 40), Speed = NumberRange.new(8, 20), Lifetime = NumberRange.new(12, 18), Size = NumberSequence.new({ kp(0, 0.6), kp(0.5, 0.9), kp(1, 0.7) }), Rotation = NumberRange.new(-180, 180), RotSpeed = NumberRange.new(-60, 60), Acceleration = Vector3.new(0, -6, 0), Transparency = NumberSequence.new({ kp(0, 0.15), kp(0.8, 0.4), kp(1, 1) }), EmissionDirection = Enum.NormalId.Bottom, LightEmission = 0.4, LightInfluence = 0.3 },
    LightRain = { BaseRate = 600, Texture = "rbxasset://textures/particles/sparkles_main.dds", Speed = NumberRange.new(70, 110), Lifetime = NumberRange.new(3, 4), Size = NumberSequence.new({ kp(0, 0.35), kp(0.5, 0.4), kp(1, 0.3) }), SpreadAngle = Vector2.new(8, 8), Acceleration = Vector3.new(0, -18, 0), Transparency = NumberSequence.new({ kp(0, 0.2), kp(0.7, 0.5), kp(1, 1) }), EmissionDirection = Enum.NormalId.Bottom, LightEmission = 0.5, LightInfluence = 0.3 },
    Snowball = { BaseRate = 40, Texture = "rbxasset://textures/particles/smoke_main.dds", SpreadAngle = Vector2.new(30, 30), Speed = NumberRange.new(10, 22), Lifetime = NumberRange.new(10, 14), Size = NumberSequence.new({ kp(0, 2.0), kp(0.5, 2.6), kp(1, 2.0) }), Rotation = NumberRange.new(-180, 180), RotSpeed = NumberRange.new(-30, 30), Acceleration = Vector3.new(0, -8, 0), Transparency = NumberSequence.new({ kp(0, 0.05), kp(0.8, 0.2), kp(1, 1) }), EmissionDirection = Enum.NormalId.Bottom, LightEmission = 0.3, LightInfluence = 0.5 },
}
local weatherOn, weatherType, weatherColor, weatherInt = false, "Snow", Color3.fromRGB(200, 200, 255), 1
local weatherPart, weatherEmitter, weatherConn = nil, nil, nil

local function clearWeather()
    if weatherConn then weatherConn:Disconnect() weatherConn = nil end
    if weatherEmitter then pcall(function() weatherEmitter:Destroy() end) weatherEmitter = nil end
    if weatherPart then pcall(function() weatherPart:Destroy() end) weatherPart = nil end
end

local function applyWeather()
    clearWeather()
    if not weatherOn then return end
    local cfg = WEATHER_CONFIGS[weatherType]
    if not cfg then return end
    local part = Instance.new("Part")
    part.Name = "LinaWeather"
    part.Size = Vector3.new(200, 1, 200)
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
    part.Massless = true
    part.CastShadow = false
    part.Transparency = 1
    part.Anchored = true
    part.Parent = workspace
    weatherPart = part
    local emitter = Instance.new("ParticleEmitter")
    emitter.Parent = part
    emitter.Color = ColorSequence.new(weatherColor)
    emitter.Rate = cfg.BaseRate * weatherInt
    emitter.LightEmission = 0
    emitter.ZOffset = -1
    for k, v in pairs(cfg) do
        if k ~= "BaseRate" then
            pcall(function() emitter[k] = v end)
        end
    end
    weatherEmitter = emitter
    weatherConn = RunService.Heartbeat:Connect(function()
        if not weatherPart or not weatherPart.Parent then return end
        local hrp = HRP()
        local cam = workspace.CurrentCamera
        if hrp then
            weatherPart.CFrame = CFrame.new(hrp.Position.X, hrp.Position.Y + 50, hrp.Position.Z)
        elseif cam then
            weatherPart.CFrame = cam.CFrame * CFrame.new(0, 50, 0)
        end
    end)
end

local function setWeather(on, typ)
    if typ then weatherType = typ end
    weatherOn = on and true or false
    applyWeather()
    if paintVisuals then paintVisuals() end
end

local function setWeatherColor(c)
    weatherColor = c
    if weatherEmitter and weatherEmitter.Parent then
        weatherEmitter.Color = ColorSequence.new(c)
    end
end

local function setWeatherInt(v)
    weatherInt = v
    local cfg = WEATHER_CONFIGS[weatherType]
    if weatherEmitter and weatherEmitter.Parent and cfg then
        weatherEmitter.Rate = cfg.BaseRate * v
    end
    if paintVisuals then paintVisuals() end
end

-- ===================== AUTOFARM (main account, this client only) =====================
local FARM_SPEED = 23
local AF = {
    On = false, Type = nil, active = false, laid = false,
    tween = nil, holdConn = nil, noclipConn = nil, orig = {},
    collected = 0, total = 0, allDone = false,
    container = nil, containerCheck = 0, bagBusy = false,
    ResetOnFull = true,
    sessionTotal = 0, lastCollected = 0,
}
local farmStatus -- TextLabel on the visuals page, filled in below

local function afIsTarget(obj, itemType)
    if not obj or not itemType or not obj:IsA("BasePart") then return false end
    local id = obj:GetAttribute(itemType .. "ID") or obj:GetAttribute("ItemID") or obj:GetAttribute("CoinID")
    if id == itemType or id == "Coin" or id == "Candy" then return true end
    local n = obj.Name:lower()
    if itemType == "Candy" and n:find("candy", 1, true) then return true end
    if itemType == "Coin" and n:find("coin", 1, true) then return true end
    return false
end

local function afFindContainer(itemType)
    if AF.container and AF.container.Parent then return AF.container end
    AF.container = nil
    local now = tick()
    if now - AF.containerCheck < 1 then return nil end
    AF.containerCheck = now
    local names = { "CoinContainer", "CandyContainer", "ItemContainer", "CandyBagContainer" }
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj:IsA("Model") or obj:IsA("Folder") then
            for _, nm in ipairs(names) do
                local c = obj:FindFirstChild(nm)
                if c then AF.container = c return c end
            end
        end
    end
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj.Name == "CoinContainer" or obj.Name == "CandyContainer" or obj.Name == "ItemContainer" then
            AF.container = obj
            return obj
        end
    end
    local key = itemType == "Candy" and "candy" or "coin"
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Model") and obj.Name:lower():find(key, 1, true) then
            for _, child in ipairs(obj:GetChildren()) do
                if child:IsA("BasePart") then
                    AF.container = obj
                    return obj
                end
            end
        end
    end
    return nil
end

local function afCollectible(item, itemType)
    if not item or not afIsTarget(item, itemType) then return false end
    if not item.CanTouch then return false end
    if not (item:FindFirstChildWhichIsA("TouchTransmitter") or item:FindFirstChild("TouchInterest")) then return false end
    if item.Transparency ~= 1 then return false end
    return true
end

local function afFindNearest(container, itemType)
    if not container or not itemType then return nil, math.huge end
    local hrp = HRP()
    if not hrp then return nil, math.huge end
    local best, bd = nil, math.huge
    for _, item in ipairs(container:GetDescendants()) do
        if afCollectible(item, itemType) then
            local d = (hrp.Position - item.Position).Magnitude
            if d < bd then bd, best = d, item end
        end
    end
    return best, bd
end

local function afAddGravity()
    local hrp = HRP()
    if not hrp then return end
    local old = hrp:FindFirstChild("FarmGravity")
    if old then old:Destroy() end
    local bp = Instance.new("BodyPosition")
    bp.Name = "FarmGravity"
    bp.MaxForce = Vector3.new(0, math.huge, 0)
    bp.D = 1000
    bp.P = 10000
    bp.Position = hrp.Position
    bp.Parent = hrp
end
local function afRemoveGravity()
    local hrp = HRP()
    local g = hrp and hrp:FindFirstChild("FarmGravity")
    if g then g:Destroy() end
end
local function afStopNoclip()
    if AF.noclipConn then AF.noclipConn:Disconnect() AF.noclipConn = nil end
end
local function afStartNoclip()
    if AF.noclipConn then return end
    AF.noclipConn = RunService.Stepped:Connect(function()
        local c = LocalPlayer.Character
        if c then
            for _, p in ipairs(c:GetDescendants()) do
                if p:IsA("BasePart") then p.CanCollide = false end
            end
        end
    end)
end

function AF.stopFarm()
    if AF.holdConn then AF.holdConn:Disconnect() AF.holdConn = nil end
    if AF.tween then pcall(function() AF.tween:Cancel() end) AF.tween = nil end
    afStopNoclip()
    if not (AF.active or AF.laid) then return end
    AF.active = false
    for part, data in pairs(AF.orig) do
        if part and part.Parent then
            part.CanCollide = data.CanCollide
            part.Massless = data.Massless
        end
    end
    AF.orig = {}
    local hrp = HRP()
    if hrp and AF.laid then
        hrp.Velocity = Vector3.zero
        hrp.RotVelocity = Vector3.zero
        hrp.CFrame = hrp.CFrame * CFrame.Angles(math.rad(-90), 0, 0)
        hrp.CFrame = hrp.CFrame + Vector3.new(0, 2.5, 0)
    end
    AF.laid = false
    local hum = Hum()
    if hum then
        hum.PlatformStand = false
        hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
        hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, true)
    end
    afRemoveGravity()
end

function AF.startFarm()
    if AF.active then return end
    local hrp, hum = HRP(), Hum()
    if not hrp or not hum then return end
    if LocalPlayer:GetAttribute("Alive") == false then return end
    afAddGravity()
    AF.orig = {}
    for _, part in ipairs(LocalPlayer.Character:GetDescendants()) do
        if part:IsA("BasePart") then
            AF.orig[part] = { CanCollide = part.CanCollide, Massless = part.Massless }
        end
    end
    hrp.CFrame = hrp.CFrame - Vector3.new(0, 2.5, 0)
    hrp.CFrame = hrp.CFrame * CFrame.Angles(math.rad(90), 0, 0)
    hum.PlatformStand = true
    hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
    hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
    AF.laid = true
    AF.active = true
end

local function setFarm(typ)
    if typ then
        AF.Type = typ
        AF.container, AF.containerCheck = nil, 0
        AF.allDone, AF.bagBusy, AF.collected, AF.total = false, false, 0, 0
        AF.lastCollected = 0
        if not AF.On then AF.sessionTotal = 0 end
        AF.On = true
    else
        AF.On = false
        AF.Type = nil
        AF.stopFarm()
    end
    if paintVisuals then paintVisuals() end
end

-- Main loop
task.spawn(function()
    while gui.Parent do
        RunService.Heartbeat:Wait()
        pcall(function()
            local farmType = AF.Type
            if AF.On and farmType and not AF.allDone and LocalPlayer:GetAttribute("Alive") ~= false then
                local container = afFindContainer(farmType)
                local item, dist = afFindNearest(container, farmType)
                if item and AF.On and AF.Type == farmType then
                    if not AF.active then AF.startFarm() end
                    local hrp, hum = HRP(), Hum()
                    if hrp and hum then
                        hrp.Velocity = Vector3.zero
                        hrp.RotVelocity = Vector3.zero
                        local target = CFrame.new(item.Position - Vector3.new(0, 2.5, 0)) * CFrame.Angles(math.rad(90), 0, 0)
                        afStartNoclip()
                        if AF.tween then AF.tween:Cancel() end
                        local tweenTime = math.max(dist / FARM_SPEED, 0.15)
                        AF.tween = TweenService:Create(hrp, TweenInfo.new(tweenTime, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), { CFrame = target })
                        AF.tween:Play()
                        if AF.holdConn then AF.holdConn:Disconnect() end
                        AF.holdConn = RunService.Heartbeat:Connect(function()
                            if not AF.On or not hrp.Parent then return end
                            hrp.Velocity = Vector3.zero
                            hrp.RotVelocity = Vector3.zero
                            local g = hrp:FindFirstChild("FarmGravity")
                            if g and g:IsA("BodyPosition") then g.Position = hrp.Position end
                            local h = Hum()
                            if h then h.PlatformStand = true end
                        end)
                        task.wait(tweenTime + 0.08)
                        if AF.On and AF.Type == farmType and item and item.Parent and afCollectible(item, farmType) then
                            if (hrp.Position - item.Position).Magnitude <= 4 then
                                pcall(function() firetouchinterest(hrp, item, 0) end)
                                task.wait(0.03)
                                pcall(function() firetouchinterest(hrp, item, 1) end)
                            end
                        end
                        local checkStart = tick()
                        while AF.On and AF.Type == farmType and item and item.Parent and afCollectible(item, farmType)
                            and (tick() - checkStart) < 1.5 and LocalPlayer:GetAttribute("Alive") ~= false do
                            RunService.Heartbeat:Wait()
                        end
                        if AF.holdConn then AF.holdConn:Disconnect() AF.holdConn = nil end
                        if AF.tween then AF.tween:Cancel() AF.tween = nil end
                        if hrp.Parent then
                            hrp.Velocity = Vector3.zero
                            hrp.RotVelocity = Vector3.zero
                        end
                    end
                else
                    AF.stopFarm()
                end
            else
                AF.stopFarm()
            end
        end)
    end
end)

-- Bag full: if you are innocent, reset your character
task.spawn(function()
    while gui.Parent do
        task.wait(0.5)
        if AF.On and AF.allDone and not AF.bagBusy and LocalPlayer:GetAttribute("Alive") ~= false then
            AF.bagBusy = true
            AF.stopFarm()
            if AF.ResetOnFull and getRole(LocalPlayer) == "Innocent" then
                task.wait(0.5)
                local h = Hum()
                if h then h.Health = 0 end
                task.wait(6)
            end
            AF.bagBusy = false
        end
    end
end)

local function afResetCounters()
    AF.collected, AF.total, AF.allDone, AF.bagBusy = 0, 0, false, false
    AF.lastCollected = 0
    AF.container, AF.containerCheck = nil, 0
end
onRemote("RoundEndFade", function()
    afResetCounters()
    AF.stopFarm()
end)
onRemote("RoundStart", afResetCounters)
onRemote("CoinCollected", function(typ, collected, total)
    if typ == AF.Type or typ == nil then
        AF.collected = tonumber(collected) or AF.collected
        AF.total = tonumber(total) or AF.total
        if AF.On then
            local c = AF.collected
            if c < AF.lastCollected then AF.lastCollected = 0 end
            if c > AF.lastCollected then
                AF.sessionTotal = AF.sessionTotal + (c - AF.lastCollected)
                AF.lastCollected = c
            end
        end
        if AF.total > 0 and AF.collected >= AF.total then
            AF.allDone = true
            AF.stopFarm()
        end
    end
end)

connect(LocalPlayer.CharacterAdded, function()
    if AF.holdConn then AF.holdConn:Disconnect() AF.holdConn = nil end
    if AF.tween then pcall(function() AF.tween:Cancel() end) AF.tween = nil end
    afStopNoclip()
    AF.active, AF.laid, AF.orig = false, false, {}
end)

local function updateFarmStatus()
    if not (farmStatus and farmStatus.Parent) then return end
    if not AF.On then
        farmStatus.Text = "Autofarm is off."
        return
    end
    local c = AF.container
    local n = 0
    if c and c.Parent and AF.Type then
        for _, it in ipairs(c:GetDescendants()) do
            if afCollectible(it, AF.Type) then n = n + 1 end
        end
    end
    farmStatus.Text = "Farming " .. tostring(AF.Type)
        .. " | items left: " .. tostring(n)
        .. " | this round: " .. tostring(AF.collected) .. "/" .. tostring(AF.total)
        .. " | total collected: " .. tostring(AF.sessionTotal)
        .. ((c and c.Parent) and "" or " | waiting for round")
        .. (AF.allDone and " | bag full" or "")
end

task.spawn(function()
    while gui.Parent do
        task.wait(1)
        pcall(updateFarmStatus)
    end
end)

visualCleanup = function()
    pcall(setSky, false)
    pcall(setRTX, false)
    pcall(setHat, false)
    pcall(setWeather, false)
    pcall(setESP, false, false)
    pcall(setFarm, nil)
    auraSel = {}
    auraRev = auraRev + 1
    clearAuras()
end

connect(LocalPlayer.CharacterAdded, function()
    task.wait(0.6)
    if next(auraSel) then applyAuras() end
end)

-- /visuals, /return, /aura, /rtx, /sky, /esp, /hat, /weather, /farm
local function runVisualCmd(text)
    local cmd, arg = text:lower():match("^/(%S+)%s*(.-)%s*$")
    if not cmd then return false end
    if cmd == "visuals" then showPage("visuals") return true end
    if cmd == "return" then showPage("main") return true end
    if cmd == "aura" then
        if arg == "off" then
            clearAuraSel()
        else
            for w in arg:gmatch("%S+") do
                if AURA_ASSETS[w] then toggleAura(w) end
            end
        end
        return true
    end
    if cmd == "sky" then
        if arg == "off" then
            setSky(false)
        else
            for _, k in ipairs(SKY_ORDER) do
                if k:lower() == arg then setSky(true, k) end
            end
        end
        return true
    end
    if cmd == "rtx" then
        if arg == "on" then setRTX(true)
        elseif arg == "off" then setRTX(false)
        elseif arg == "" then setRTX(not rtxOn) end
        return true
    end
    if cmd == "esp" then
        local on
        if arg == "on" then on = true
        elseif arg == "off" then on = false
        else on = not (espOn or espNames) end
        setESP(on, on)
        return true
    end
    if cmd == "hat" then
        if arg == "on" then setHat(true)
        elseif arg == "off" then setHat(false)
        else setHat(not hatOn) end
        return true
    end
    if cmd == "weather" then
        if arg == "off" then
            setWeather(false)
        else
            for _, k in ipairs(WEATHER_ORDER) do
                if k:lower() == arg then setWeather(true, k) end
            end
        end
        return true
    end
    if cmd == "farm" then
        if arg == "candy" then setFarm("Candy")
        elseif arg == "coin" then setFarm("Coin")
        elseif arg == "off" then setFarm(nil) end
        return true
    end
    return false
end
-- =======================================================================

-- Window
local frame = Instance.new("CanvasGroup")
frame.GroupTransparency = 1
frame.Size = UDim2.fromOffset(460, 520)
frame.Position = UDim2.new(0.5, -230, 0.5, -260)
frame.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
frame.BorderSizePixel = 0
frame.Parent = gui
corner(frame)

-- Open / close animations (same style as the loader)
local uiScale = Instance.new("UIScale")
uiScale.Scale = 0.88
uiScale.Parent = frame

local shown = true
local animToken = 0
local function showFrame()
    animToken = animToken + 1
    shown = true
    frame.Visible = true
    TweenService:Create(frame, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { GroupTransparency = 0 }):Play()
    TweenService:Create(uiScale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end
local function hideFrame(after)
    animToken = animToken + 1
    shown = false
    local my = animToken
    local t = TweenService:Create(frame, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { GroupTransparency = 1 })
    TweenService:Create(uiScale, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.88 }):Play()
    t.Completed:Connect(function()
        if my ~= animToken then return end
        if after then after() else frame.Visible = false end
    end)
    t:Play()
end

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 32)
title.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
title.BorderSizePixel = 0
title.Text = TITLE_NAME
title.TextColor3 = WHITE
title.Font = Enum.Font.GothamBold
title.TextSize = 15
title.Parent = frame
corner(title)

-- Running time (far left, time only)
local timerLbl = Instance.new("TextLabel")
timerLbl.Size = UDim2.fromOffset(62, 32)
timerLbl.Position = UDim2.fromOffset(8, 0)
timerLbl.BackgroundTransparency = 1
timerLbl.Font = Enum.Font.Code
timerLbl.TextSize = 12
timerLbl.TextColor3 = Color3.fromRGB(150, 150, 160)
timerLbl.TextXAlignment = Enum.TextXAlignment.Left
timerLbl.Text = "00:00:00"
timerLbl.Parent = title

task.spawn(function()
    while gui.Parent do
        local e = os.time() - startTime
        timerLbl.Text = string.format("%02d:%02d:%02d", math.floor(e / 3600), math.floor((e % 3600) / 60), e % 60)
        task.wait(1)
    end
end)

-- Close button
local close = Instance.new("TextButton")
close.Size = UDim2.fromOffset(24, 24)
close.Position = UDim2.new(1, -30, 0, 4)
close.BackgroundTransparency = 1
close.BorderSizePixel = 0
close.Text = "X"
close.TextColor3 = Color3.new(1, 1, 1)
close.Font = Enum.Font.GothamBold
close.TextSize = 13
close.Parent = title
connect(close.MouseButton1Click, function()
    hideFrame(function() getgenv().StandCleanup() end)
end)

-- Command bar
local bar = Instance.new("TextBox")
bar.Position = UDim2.fromOffset(8, 38)
bar.Size = UDim2.new(1, -16, 0, 28)
bar.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
bar.BorderSizePixel = 0
bar.Text = ""
bar.PlaceholderColor3 = Color3.fromRGB(120, 120, 130)
bar.TextColor3 = Color3.fromRGB(220, 220, 225)
bar.Font = Enum.Font.Code
bar.TextSize = 13
bar.TextXAlignment = Enum.TextXAlignment.Left
bar.ClearTextOnFocus = false
bar.Parent = frame
corner(bar, 6)
local barPad = Instance.new("UIPadding")
barPad.PaddingLeft = UDim.new(0, 8)
barPad.Parent = bar

local BAR_HINT_STAND = "command + Enter  |  /c = chat mode  |  /visuals  |  @name = one account"
local BAR_HINT_CHAT = "CHAT MODE: commands go to chat  |  /c = back  |  @name = one account"
local function refreshTitle()
    title.Text = TITLE_NAME .. (chatMode and "  [CHAT]" or "") .. (page == "visuals" and "  [VISUALS]" or "")
end
local function setChatMode(on)
    chatMode = on
    refreshTitle()
    bar.PlaceholderText = on and BAR_HINT_CHAT or BAR_HINT_STAND
end
setChatMode(false)

-- Suggestions (names / on-off values / active bot names / dance / aura / sky)
local chips = Instance.new("ScrollingFrame")
chips.Position = UDim2.fromOffset(8, 70)
chips.Size = UDim2.new(1, -16, 0, 22)
chips.BackgroundTransparency = 1
chips.BorderSizePixel = 0
chips.ScrollBarThickness = 0
chips.CanvasSize = UDim2.new()
chips.AutomaticCanvasSize = Enum.AutomaticSize.X
chips.ScrollingDirection = Enum.ScrollingDirection.X
chips.Parent = frame
local cl = Instance.new("UIListLayout")
cl.FillDirection = Enum.FillDirection.Horizontal
cl.Padding = UDim.new(0, 4)
cl.Parent = chips

-- Connected bots panel
local botPanel = Instance.new("ScrollingFrame")
botPanel.Position = UDim2.fromOffset(8, 96)
botPanel.Size = UDim2.new(1, -16, 0, 26)
botPanel.BackgroundColor3 = Color3.fromRGB(26, 26, 32)
botPanel.BorderSizePixel = 0
botPanel.ScrollBarThickness = 0
botPanel.CanvasSize = UDim2.new()
botPanel.AutomaticCanvasSize = Enum.AutomaticSize.X
botPanel.ScrollingDirection = Enum.ScrollingDirection.X
botPanel.Parent = frame
corner(botPanel, 6)
local bl = Instance.new("UIListLayout")
bl.FillDirection = Enum.FillDirection.Horizontal
bl.Padding = UDim.new(0, 4)
bl.VerticalAlignment = Enum.VerticalAlignment.Center
bl.SortOrder = Enum.SortOrder.LayoutOrder
bl.Parent = botPanel
local bpad = Instance.new("UIPadding")
bpad.PaddingLeft = UDim.new(0, 6)
bpad.Parent = botPanel

-- Animated Discord text (types out, waits, erases backwards, repeats)
local botLabel = Instance.new("TextLabel")
botLabel.LayoutOrder = 0
botLabel.Size = UDim2.fromOffset(280, 20)
botLabel.BackgroundTransparency = 1
botLabel.Font = Enum.Font.GothamBold
botLabel.TextSize = 12
botLabel.TextColor3 = Color3.fromRGB(114, 137, 218)
botLabel.TextXAlignment = Enum.TextXAlignment.Left
botLabel.Text = "dont forget to join discord .gg/standd"
botLabel.MaxVisibleGraphemes = 0
botLabel.Parent = botPanel

task.spawn(function()
    local n = #botLabel.Text
    while gui.Parent do
        for i = 0, n do
            if not gui.Parent then return end
            botLabel.MaxVisibleGraphemes = i
            task.wait(0.05)
        end
        task.wait(1.5)
        for i = n, 0, -1 do
            if not gui.Parent then return end
            botLabel.MaxVisibleGraphemes = i
            task.wait(0.03)
        end
        task.wait(0.5)
    end
end)

-- Info line showing who the command goes to
local targetLabel = Instance.new("TextLabel")
targetLabel.Position = UDim2.fromOffset(8, 126)
targetLabel.Size = UDim2.new(1, -16, 0, 18)
targetLabel.BackgroundTransparency = 1
targetLabel.Font = Enum.Font.Gotham
targetLabel.TextSize = 11
targetLabel.TextXAlignment = Enum.TextXAlignment.Left
targetLabel.TextColor3 = Color3.fromRGB(150, 150, 160)
targetLabel.Text = "Sending to: ALL bots"
targetLabel.Parent = frame

local function updateTargetLabel()
    local atOverride = bar.Text:match("^@(%S+)")
    if atOverride and atOverride ~= "" then
        targetLabel.Text = "Sending to: @" .. atOverride .. "  (typed override)"
        return
    end
    local names = {}
    for name in pairs(selectedBots) do table.insert(names, name) end
    table.sort(names)
    if #names == 0 then
        targetLabel.Text = "Sending to: ALL bots"
    else
        targetLabel.Text = "Sending to: " .. table.concat(names, ", ")
    end
end

local OPTION_CMDS = {
    ["!followmode"] = { "on", "off" },
    ["!ainfo"] = { "on", "off", "on 8", "on 10", "on 12", "on 15" },
    ["!friends"] = { "on", "off" },
    ["!norender"] = { "on", "off" },
    ["!autofarm"] = { "on candy", "on coin", "off" },
    ["!time"] = { "0.5", "1", "3", "5", "7", "10" },
}

local SLASH_CMDS = { "/c", "/visuals", "/return", "/aura", "/rtx", "/sky", "/esp", "/hat", "/weather", "/farm" }
local SLASH_NEEDS_ARG = { ["/aura"] = true, ["/rtx"] = true, ["/sky"] = true, ["/esp"] = true, ["/hat"] = true, ["/weather"] = true, ["/farm"] = true }
local LOCAL_SLASH = {
    visuals = true, ["return"] = true, aura = true, rtx = true, sky = true,
    esp = true, hat = true, weather = true, farm = true,
}

local function focusBar()
    task.defer(function()
        bar:CaptureFocus()
        bar.CursorPosition = #bar.Text + 1
    end)
end

local function makeChip(label, width, color, onClick)
    local c = Instance.new("TextButton")
    c.Size = UDim2.fromOffset(width, 22)
    c.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
    c.BorderSizePixel = 0
    c.Text = label
    c.TextColor3 = color
    c.Font = Enum.Font.Gotham
    c.TextSize = 12
    c.TextTruncate = Enum.TextTruncate.AtEnd
    c.Parent = chips
    corner(c, 5)
    c.MouseButton1Click:Connect(function()
        onClick()
        focusBar()
    end)
end

local function nameMatches(p, word)
    return word == "" or p.Name:lower():sub(1, #word) == word:lower()
        or p.DisplayName:lower():sub(1, #word) == word:lower()
end

-- Runs the text in the bar (identical to pressing Enter)
local function submit(raw)
    local text = (raw:gsub("%s+$", ""))
    if (text:gsub("%s", "")) == "" then return end
    local lower = text:lower()
    local sc = lower:match("^/(%a+)")
    if lower == "/c" then
        setChatMode(not chatMode)
    elseif lower:sub(1, 3) == "/c " then
        say(text:sub(4))
    elseif sc and LOCAL_SLASH[sc] then
        runVisualCmd(text)
    else
        dispatch(text)
    end
    bar.Text = ""
    updateTargetLabel()
end

local GREY = Color3.fromRGB(130, 130, 140)

local function updateChips()
    for _, c in ipairs(chips:GetChildren()) do
        if c:IsA("TextButton") then c:Destroy() end
    end
    local text = bar.Text

    -- When typing "/": slash commands (ones without arguments run directly)
    local slashWord = text:match("^/(%S*)$")
    if slashWord then
        for _, sc in ipairs(SLASH_CMDS) do
            if sc:sub(2, 1 + #slashWord) == slashWord:lower() then
                makeChip(sc, math.clamp(#sc * 7 + 16, 50, 100), WHITE, function()
                    if SLASH_NEEDS_ARG[sc] then
                        bar.Text = sc .. " "
                    else
                        submit(sc)
                    end
                end)
            end
        end
        return
    end

    -- Options for "/aura ", "/sky ", "/rtx ", "/esp ", "/hat ", "/weather ", "/farm "
    local scmd, srest = text:match("^/(%S+)%s+(.*)$")
    if scmd then
        scmd = scmd:lower()
        local word = (srest:match("(%S*)$") or ""):lower()
        local items, isActive, pick
        if scmd == "aura" then
            items = {}
            for _, n in ipairs(AURA_NAMES) do table.insert(items, n) end
            table.insert(items, "off")
            isActive = function(n) return auraSel[n] end
            pick = function(n) if n == "off" then clearAuraSel() else toggleAura(n) end end
        elseif scmd == "sky" then
            items = {}
            for _, n in ipairs(SKY_ORDER) do table.insert(items, n) end
            table.insert(items, "off")
            isActive = function(n) return skyOn and skyType == n end
            pick = function(n) if n == "off" then setSky(false) else setSky(true, n) end end
        elseif scmd == "rtx" then
            items = { "on", "off" }
            isActive = function(n) return (n == "on") == rtxOn end
            pick = function(n) setRTX(n == "on") end
        elseif scmd == "hat" then
            items = { "on", "off" }
            isActive = function(n) return (n == "on") == hatOn end
            pick = function(n) setHat(n == "on") end
        elseif scmd == "esp" then
            items = { "on", "off" }
            isActive = function(n) return (n == "on") == (espOn or espNames) end
            pick = function(n) setESP(n == "on", n == "on") end
        elseif scmd == "weather" then
            items = {}
            for _, n in ipairs(WEATHER_ORDER) do table.insert(items, n) end
            table.insert(items, "off")
            isActive = function(n) return weatherOn and weatherType == n end
            pick = function(n) if n == "off" then setWeather(false) else setWeather(true, n) end end
        elseif scmd == "farm" then
            items = { "Candy", "Coin", "off" }
            isActive = function(n) return AF.On and AF.Type == n end
            pick = function(n) if n == "off" then setFarm(nil) else setFarm(n) end end
        end
        if items then
            for _, n in ipairs(items) do
                if word == "" or n:lower():sub(1, #word) == word then
                    makeChip(n, math.clamp(#n * 7 + 16, 44, 100), isActive(n) and GREEN or PINK, function()
                        pick(n)
                        updateChips()
                    end)
                end
            end
        end
        return
    end

    -- When typing "@": only ACTIVE bot names
    local atWord = text:match("^@(%S*)$")
    if atWord then
        local n = 0
        for _, name in ipairs(sortedBots(true)) do
            if n < 6 and (atWord == "" or name:lower():sub(1, #atWord) == atWord:lower()) then
                n = n + 1
                makeChip("@" .. name, 110, WHITE, function()
                    bar.Text = "@" .. name .. " "
                end)
            end
        end
        if n == 0 then
            makeChip("no active bots", 110, GREY, function() end)
        end
        return
    end

    -- Strip the "@name " prefix before parsing the command
    local atPrefix = text:match("^(@%S+%s+)") or ""
    text = text:sub(#atPrefix + 1)

    local cmdRaw = text:match("^(%S+)")
    if not cmdRaw or cmdRaw:sub(1, 1) ~= "!" then return end
    local cmd = cmdRaw:lower()
    local hasSpace = text:find("%s") ~= nil
    local word = hasSpace and (text:match("(%S*)$") or "") or ""

    -- Clicking a chip sends the command directly (no Enter needed)
    local function send(value)
        submit(atPrefix .. cmdRaw .. " " .. value)
    end

    -- !dance: dance list
    if cmd == "!dance" then
        local rest = (text:match("^%S+%s+(.*)$") or ""):lower()
        for _, e in ipairs(EMOTES) do
            if rest == "" or e.name:lower():find(rest, 1, true) then
                makeChip(e.name, math.clamp(#e.name * 7 + 16, 60, 130), WHITE, function() send(e.name) end)
            end
        end
        return
    end

    -- on / off and preset values
    if OPTION_CMDS[cmd] then
        for _, opt in ipairs(OPTION_CMDS[cmd]) do
            if word == "" or opt:sub(1, #word) == word:lower() then
                makeChip(opt, math.clamp(#opt * 7 + 16, 56, 110), WHITE, function() send(opt) end)
            end
        end
        return
    end

    -- !standmode: "off" plus matching player names, INCLUDING yourself (unlike fling you can stand-follow yourself)
    if cmd == "!standmode" then
        if word == "" or ("off"):sub(1, #word) == word:lower() then
            makeChip("off", 50, WHITE, function() send("off") end)
        end
        if nameMatches(Players.LocalPlayer, word) then
            makeChip(Players.LocalPlayer.Name .. " (you)", math.clamp(#Players.LocalPlayer.Name * 7 + 40, 90, 170), WHITE, function() send(Players.LocalPlayer.Name) end)
        end
    end

    -- player usernames
    local n = 0
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= Players.LocalPlayer and n < 8 and nameMatches(p, word) then
            n = n + 1
            makeChip(p.Name, math.clamp(#p.Name * 7 + 16, 70, 150), WHITE, function() send(p.Name) end)
        end
    end
    if n == 0 and cmd ~= "!standmode" then
        makeChip("no matching players", 130, GREY, function() end)
    end
end
connect(bar:GetPropertyChangedSignal("Text"), function()
    updateChips()
    updateTargetLabel()
end)
connect(Players.PlayerAdded, function() updateChips() end)
connect(Players.PlayerRemoving, function() task.defer(updateChips) end)

-- Paint the bot button according to its selection state
local botButtons = {}
local function paintBotButton(name)
    local b = botButtons[name]
    if not b then return end
    local sel = selectedBots[name]
    b.BackgroundColor3 = sel and WHITE or Color3.fromRGB(40, 40, 50)
    local botOn = bots[name] and bots[name].on
    b.TextColor3 = sel and Color3.fromRGB(30, 30, 34) or (botOn and Color3.fromRGB(220, 220, 225) or Color3.fromRGB(130, 130, 140))
end

-- Draw the bots panel (does not rebuild if the bot list/on-off state is unchanged)
local lastSig = ""
local function renderBots()
    local list = sortedBots(false)
    local sig = {}
    for _, name in ipairs(list) do
        local on = bots[name].on
        table.insert(sig, name .. (on and ":1" or ":0"))
    end
    sig = table.concat(sig, "|")
    if sig == lastSig then return end
    lastSig = sig

    for _, c in ipairs(botPanel:GetChildren()) do
        if c:IsA("TextButton") then c:Destroy() end
    end
    botButtons = {}

    -- ALL: clears the selection, target becomes "all"
    local allBtn = Instance.new("TextButton")
    allBtn.LayoutOrder = 1
    allBtn.Size = UDim2.fromOffset(40, 20)
    allBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
    allBtn.BorderSizePixel = 0
    allBtn.Text = "ALL"
    allBtn.TextColor3 = WHITE
    allBtn.Font = Enum.Font.GothamBold
    allBtn.TextSize = 11
    allBtn.Parent = botPanel
    corner(allBtn, 5)
    allBtn.MouseButton1Click:Connect(function()
        selectedBots = {}
        for name in pairs(botButtons) do paintBotButton(name) end
        bar.Text = bar.Text:gsub("^@%S*%s*", "")
        updateTargetLabel()
        focusBar()
    end)

    for i, name in ipairs(list) do
        local on = bots[name].on
        local b = Instance.new("TextButton")
        b.LayoutOrder = i + 1
        b.Size = UDim2.fromOffset(math.clamp(#name * 7 + 38, 70, 150), 20)
        b.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
        b.BorderSizePixel = 0
        b.RichText = true
        b.Text = ('<font color="%s">●</font> %s <font color="%s">%s</font>'):format(
            on and "#6ee68c" or "#eb646e", name, on and "#6ee68c" or "#eb646e", on and "on" or "off")
        b.TextColor3 = Color3.fromRGB(220, 220, 225)
        b.Font = Enum.Font.Gotham
        b.TextSize = 11
        b.TextTruncate = Enum.TextTruncate.AtEnd
        b.Parent = botPanel
        corner(b, 5)
        botButtons[name] = b
        paintBotButton(name)
        b.MouseButton1Click:Connect(function()
            if selectedBots[name] then
                selectedBots[name] = nil
            else
                selectedBots[name] = true
            end
            paintBotButton(name)
            updateTargetLabel()
        end)
    end
end

task.spawn(function()
    while gui.Parent do
        refreshBots()
        renderBots()
        renderRoleBox()
        if bar.Text:sub(1, 1) == "@" then updateChips() end
        task.wait(2)
    end
end)

connect(bar.FocusLost, function(enter)
    if enter then submit(bar.Text) end
end)

-- ===================== MAIN PAGE (bot control) =====================
local scroll = Instance.new("ScrollingFrame")
scroll.Position = UDim2.fromOffset(8, 150)
scroll.Size = UDim2.new(1, -16, 1, -166)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4
scroll.CanvasSize = UDim2.new()
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.Parent = frame

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 2)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = scroll

-- Colors the command name (!fling, /visuals ...) red and leaves the rest unchanged
local CMD_COLOR = "#ff5555"
local function colorCmd(text)
    local cmdPart, rest = text:match("^([!/]%S+)(.*)$")
    if cmdPart then
        return '<font color="' .. CMD_COLOR .. '">' .. cmdPart .. "</font>" .. rest
    end
    return text
end

local order = 0
local function header(text, color)
    order = order + 1
    local l = Instance.new("TextLabel")
    l.LayoutOrder = order
    l.Size = UDim2.new(1, -8, 0, 24)
    l.BackgroundTransparency = 1
    l.RichText = true
    l.Text = '<b><font color="' .. color .. '">' .. text .. "</font></b>"
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Font = Enum.Font.Code
    l.TextSize = 13
    l.TextColor3 = Color3.fromRGB(220, 220, 225)
    l.Parent = scroll
end

-- mode: "say" = sends directly | "arg" = writes to the bar, you type the value + Enter | "page" = opens a page | nil = text only
local function row(text, cmd, mode)
    order = order + 1
    local b = Instance.new(mode and "TextButton" or "TextLabel")
    b.LayoutOrder = order
    b.Size = UDim2.new(1, -8, 0, 0)
    b.AutomaticSize = Enum.AutomaticSize.Y
    b.BackgroundTransparency = 1
    b.BorderSizePixel = 0
    b.TextWrapped = true
    b.RichText = true
    b.Text = colorCmd(text)
    b.TextXAlignment = Enum.TextXAlignment.Left
    b.TextYAlignment = Enum.TextYAlignment.Top
    b.Font = Enum.Font.Code
    b.TextSize = 13
    b.TextColor3 = mode and Color3.fromRGB(220, 220, 225) or Color3.fromRGB(130, 130, 140)
    b.Parent = scroll
    if mode then
        b.AutoButtonColor = false
        connect(b.MouseEnter, function()
            b.BackgroundColor3 = WHITE
            b.BackgroundTransparency = 0.9
        end)
        connect(b.MouseLeave, function() b.BackgroundTransparency = 1 end)
        connect(b.MouseButton1Click, function()
            local at = bar.Text:match("^(@%S+%s+)") or ""
            if mode == "page" then
                showPage(cmd)
            elseif mode == "arg" then
                bar.Text = at .. cmd .. " "
                updateChips()
                updateTargetLabel()
                focusBar()
            else
                dispatch(at .. cmd)
            end
        end)
    end
end

header("Usable by you AND whitelisted players:", "#57F287")
row("!fling &lt;user&gt;  fling once", "!fling", "arg")
row("!flingall  fling everyone once (whitelist skipped)", "!flingall", "say")
row("!loop &lt;user&gt;  loop forever (saved list, survives rejoin)", "!loop", "arg")
row("!unloop &lt;user|all&gt;  remove from loop list", "!unloop", "arg")
row("!loopall  keep flinging everyone (whitelist skipped), the owner's !stop ends it", "!loopall", "say")
row("!bring  go to the gun, take it, tp to you, reset", "!bring", "say")
row("!abring  keep doing !bring every time the gun drops, !stop to end", "!abring", "say")
row("!list  show whitelist and loop list", "!list", "say")
row('!info  sheriff/murderer info (also written to chat, whitelisted shown as "whitelisted")', "!info", "say")
row("!standmode [user]|off  float beside that player's shoulder forever, dancing fly, follows them", "!standmode", "arg")
row("!stop  stop EVERYTHING (fling, loops, bring) except the dance, and go back to the void", "!stop", "say")
row("!resume  resume the loop list", "!resume", "say")
row("!reset  reset your character", "!reset", "say")
row("!shoot  (sheriff) shoot the murderer once", "!shoot", "say")
row("!killall  (murderer) knife aura for 5 seconds", "!killall", "say")
row("!tp  teleport to the main account", "!tp", "say")
row("!tp &lt;user&gt;  teleport to that user", "!tp", "arg")
row("!void  force the void hide on (on by default)", "!void", "say")
row("!unvoid  force the void hide off", "!unvoid", "say")
row("!followmode on|off  when the main account dies or !reset's, this bot auto-resets too", "!followmode", "arg")
row("!autofarm [on|off] [candy|coin]  bot autofarm, screen shows total collected, rainbow screen when off", "!autofarm", "arg")
row("!rejoin  teleport to a new server and re-inject (set LOADER_URL in the bot script first)", "!rejoin", "say")

header("Usable ONLY from your own account (or the main account, id bound):", "#FEE75C")
row("!whitelist &lt;user&gt;  add to whitelist (saved)", "!whitelist", "arg")
row("!unwhitelist &lt;user&gt;  remove from whitelist", "!unwhitelist", "arg")
row('!setmain &lt;user&gt;  set the "main account" bare !tp goes to (saved)', "!setmain", "arg")
row("!ainfo on|off [delay]  auto-post !info this many seconds after round start (default 12)", "!ainfo", "arg")
row("!leave  leave the game", "!leave", "say")
row("!time &lt;0.5-10&gt;  seconds spent per player (default 7)", "!time", "arg")
row("!friends on|off  never fling your friends", "!friends", "arg")
row("!norender on|off  3D rendering off + black screen", "!norender", "arg")
row("!dance [name]  dance forever, can't be stopped. Click, then pick: jamal, kick, fly...", "!dance", "arg")
row("!help  print this list to the F9 console", "!help", "say")

header("Local (this client only):", "#F2BDCD")
row("/visuals  open the visuals page (auras, RTX, sky, hat, weather, ESP, autofarm)", "visuals", "page")

-- ===================== COLOR PICKER (shared popup) =====================
local pickOnChange = nil
local ph, ps, pv = 0, 1, 1
local pickDrag = nil

local popup = Instance.new("Frame")
popup.Name = "ColorPicker"
popup.AnchorPoint = Vector2.new(0.5, 0.5)
popup.Position = UDim2.fromScale(0.5, 0.5)
popup.Size = UDim2.fromOffset(220, 210)
popup.BackgroundColor3 = Color3.fromRGB(34, 34, 42)
popup.BorderSizePixel = 0
popup.Visible = false
popup.Active = true -- swallows clicks so rows behind do not react
popup.ZIndex = 30
popup.Parent = frame
corner(popup, 8)
do
    local st = Instance.new("UIStroke")
    st.Color = Color3.fromRGB(70, 70, 84)
    st.Thickness = 1
    st.Parent = popup
end

local pTitle = Instance.new("TextLabel")
pTitle.Position = UDim2.fromOffset(10, 6)
pTitle.Size = UDim2.fromOffset(200, 18)
pTitle.BackgroundTransparency = 1
pTitle.Font = Enum.Font.GothamBold
pTitle.TextSize = 12
pTitle.TextColor3 = WHITE
pTitle.TextXAlignment = Enum.TextXAlignment.Left
pTitle.Text = "Color"
pTitle.Parent = popup

-- saturation / value square
local svBox = Instance.new("Frame")
svBox.Position = UDim2.fromOffset(10, 30)
svBox.Size = UDim2.fromOffset(200, 110)
svBox.BackgroundColor3 = Color3.fromHSV(0, 1, 1)
svBox.BorderSizePixel = 0
svBox.Parent = popup
corner(svBox, 4)

local svWhite = Instance.new("Frame")
svWhite.Size = UDim2.fromScale(1, 1)
svWhite.BackgroundColor3 = Color3.new(1, 1, 1)
svWhite.BorderSizePixel = 0
svWhite.Parent = svBox
corner(svWhite, 4)
do
    local g = Instance.new("UIGradient")
    g.Transparency = NumberSequence.new(0, 1) -- white on the left, clear on the right
    g.Parent = svWhite
end

local svBlack = Instance.new("Frame")
svBlack.Size = UDim2.fromScale(1, 1)
svBlack.BackgroundColor3 = Color3.new(0, 0, 0)
svBlack.BorderSizePixel = 0
svBlack.Parent = svBox
corner(svBlack, 4)
do
    local g = Instance.new("UIGradient")
    g.Rotation = 90
    g.Transparency = NumberSequence.new(1, 0) -- clear on top, black at the bottom
    g.Parent = svBlack
end

local svCursor = Instance.new("Frame")
svCursor.Size = UDim2.fromOffset(10, 10)
svCursor.BackgroundTransparency = 1
svCursor.BorderSizePixel = 0
svCursor.ZIndex = 3
svCursor.Parent = svBox
corner(svCursor, 5)
do
    local st = Instance.new("UIStroke")
    st.Color = Color3.new(1, 1, 1)
    st.Thickness = 2
    st.Parent = svCursor
end

local svHit = Instance.new("TextButton")
svHit.Size = UDim2.fromScale(1, 1)
svHit.BackgroundTransparency = 1
svHit.Text = ""
svHit.AutoButtonColor = false
svHit.ZIndex = 5
svHit.Parent = svBox

-- hue bar
local hueBar = Instance.new("Frame")
hueBar.Position = UDim2.fromOffset(10, 148)
hueBar.Size = UDim2.fromOffset(200, 14)
hueBar.BackgroundColor3 = Color3.new(1, 1, 1)
hueBar.BorderSizePixel = 0
hueBar.Parent = popup
corner(hueBar, 4)
do
    local g = Instance.new("UIGradient")
    local keys = {}
    for i = 0, 6 do
        table.insert(keys, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6 % 1, 1, 1)))
    end
    keys[#keys] = ColorSequenceKeypoint.new(1, Color3.fromHSV(0, 1, 1))
    g.Color = ColorSequence.new(keys)
    g.Parent = hueBar
end

local hueCursor = Instance.new("Frame")
hueCursor.Size = UDim2.fromOffset(4, 18)
hueCursor.Position = UDim2.new(0, -2, 0, -2)
hueCursor.BackgroundColor3 = Color3.new(1, 1, 1)
hueCursor.BorderSizePixel = 0
hueCursor.ZIndex = 3
hueCursor.Parent = hueBar
do
    local st = Instance.new("UIStroke")
    st.Color = Color3.new(0, 0, 0)
    st.Thickness = 1
    st.Parent = hueCursor
end

local hueHit = Instance.new("TextButton")
hueHit.Size = UDim2.fromScale(1, 1)
hueHit.BackgroundTransparency = 1
hueHit.Text = ""
hueHit.AutoButtonColor = false
hueHit.ZIndex = 5
hueHit.Parent = hueBar

local pPreview = Instance.new("Frame")
pPreview.Position = UDim2.fromOffset(10, 172)
pPreview.Size = UDim2.fromOffset(130, 26)
pPreview.BackgroundColor3 = Color3.new(1, 1, 1)
pPreview.BorderSizePixel = 0
pPreview.Parent = popup
corner(pPreview, 5)

local pDone = Instance.new("TextButton")
pDone.Position = UDim2.fromOffset(150, 172)
pDone.Size = UDim2.fromOffset(60, 26)
pDone.BackgroundColor3 = Color3.fromRGB(52, 52, 64)
pDone.BorderSizePixel = 0
pDone.Text = "Done"
pDone.TextColor3 = WHITE
pDone.Font = Enum.Font.GothamBold
pDone.TextSize = 12
pDone.AutoButtonColor = true
pDone.Parent = popup
corner(pDone, 5)

local function pickerPaint()
    svBox.BackgroundColor3 = Color3.fromHSV(ph, 1, 1)
    svCursor.Position = UDim2.new(ps, -5, 1 - pv, -5)
    hueCursor.Position = UDim2.new(ph, -2, 0, -2)
    pPreview.BackgroundColor3 = Color3.fromHSV(ph, ps, pv)
end

local function pickerFire()
    pickerPaint()
    if pickOnChange then pickOnChange(Color3.fromHSV(ph, ps, pv)) end
end

local function closePicker()
    popup.Visible = false
    pickOnChange = nil
    pickDrag = nil
end

local function openPicker(titleText, color, onChange)
    ph, ps, pv = color:ToHSV()
    pickOnChange = onChange
    pTitle.Text = titleText
    popup.Visible = true
    pickerPaint()
end

local function pickPos(i)
    if i.UserInputType == Enum.UserInputType.Touch then
        return Vector2.new(i.Position.X, i.Position.Y)
    end
    return UIS:GetMouseLocation()
end

local function pickUpdate(pos)
    if pickDrag == "sv" then
        local ap, as = svBox.AbsolutePosition, svBox.AbsoluteSize
        ps = math.clamp((pos.X - ap.X) / math.max(as.X, 1), 0, 1)
        pv = 1 - math.clamp((pos.Y - ap.Y) / math.max(as.Y, 1), 0, 1)
        pickerFire()
    elseif pickDrag == "hue" then
        local ap, as = hueBar.AbsolutePosition, hueBar.AbsoluteSize
        ph = math.clamp((pos.X - ap.X) / math.max(as.X, 1), 0, 1)
        pickerFire()
    end
end

local function isPress(i)
    return i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch
end

connect(svHit.InputBegan, function(i)
    if isPress(i) then
        pickDrag = "sv"
        pickUpdate(pickPos(i))
    end
end)
connect(hueHit.InputBegan, function(i)
    if isPress(i) then
        pickDrag = "hue"
        pickUpdate(pickPos(i))
    end
end)
connect(UIS.InputChanged, function(i)
    if pickDrag and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
        pickUpdate(pickPos(i))
    end
end)
connect(UIS.InputEnded, function(i)
    if isPress(i) then pickDrag = nil end
end)
connect(pDone.MouseButton1Click, closePicker)

-- ===================== VISUALS PAGE =====================
local visualsPage = Instance.new("ScrollingFrame")
visualsPage.Position = UDim2.fromOffset(8, 150)
visualsPage.Size = UDim2.new(1, -16, 1, -166)
visualsPage.BackgroundTransparency = 1
visualsPage.BorderSizePixel = 0
visualsPage.ScrollBarThickness = 4
visualsPage.CanvasSize = UDim2.new()
visualsPage.AutomaticCanvasSize = Enum.AutomaticSize.Y
visualsPage.Visible = false
visualsPage.Parent = frame

local vlayout = Instance.new("UIListLayout")
vlayout.Padding = UDim.new(0, 2)
vlayout.SortOrder = Enum.SortOrder.LayoutOrder
vlayout.Parent = visualsPage

local vorder = 0
local function vheader(text, color)
    vorder = vorder + 1
    local l = Instance.new("TextLabel")
    l.LayoutOrder = vorder
    l.Size = UDim2.new(1, -8, 0, 24)
    l.BackgroundTransparency = 1
    l.RichText = true
    l.Text = '<b><font color="' .. color .. '">' .. text .. "</font></b>"
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Font = Enum.Font.Code
    l.TextSize = 13
    l.TextColor3 = Color3.fromRGB(220, 220, 225)
    l.Parent = visualsPage
end

local function vrow(text, onClick)
    vorder = vorder + 1
    local b = Instance.new(onClick and "TextButton" or "TextLabel")
    b.LayoutOrder = vorder
    b.Size = UDim2.new(1, -8, 0, 0)
    b.AutomaticSize = Enum.AutomaticSize.Y
    b.BackgroundTransparency = 1
    b.BorderSizePixel = 0
    b.TextWrapped = true
    b.RichText = true
    b.Text = colorCmd(text)
    b.TextXAlignment = Enum.TextXAlignment.Left
    b.TextYAlignment = Enum.TextYAlignment.Top
    b.Font = Enum.Font.Code
    b.TextSize = 13
    b.TextColor3 = onClick and Color3.fromRGB(220, 220, 225) or Color3.fromRGB(130, 130, 140)
    b.Parent = visualsPage
    if onClick then
        b.AutoButtonColor = false
        connect(b.MouseEnter, function()
            b.BackgroundColor3 = PINK
            b.BackgroundTransparency = 0.8
        end)
        connect(b.MouseLeave, function() b.BackgroundTransparency = 1 end)
        connect(b.MouseButton1Click, onClick)
    end
    return b
end

-- Row with a color swatch that opens the color picker
local function vcolor(label, get, set)
    vorder = vorder + 1
    local b = Instance.new("TextButton")
    b.LayoutOrder = vorder
    b.Size = UDim2.new(1, -8, 0, 26)
    b.BackgroundTransparency = 1
    b.BorderSizePixel = 0
    b.Text = label
    b.TextXAlignment = Enum.TextXAlignment.Left
    b.Font = Enum.Font.Code
    b.TextSize = 13
    b.TextColor3 = Color3.fromRGB(220, 220, 225)
    b.AutoButtonColor = false
    b.Parent = visualsPage
    local sw = Instance.new("Frame")
    sw.Size = UDim2.fromOffset(40, 16)
    sw.Position = UDim2.new(1, -48, 0.5, -8)
    sw.BackgroundColor3 = get()
    sw.BorderSizePixel = 0
    sw.Parent = b
    corner(sw, 4)
    do
        local st = Instance.new("UIStroke")
        st.Color = Color3.fromRGB(90, 90, 104)
        st.Thickness = 1
        st.Parent = sw
    end
    connect(b.MouseEnter, function()
        b.BackgroundColor3 = PINK
        b.BackgroundTransparency = 0.8
    end)
    connect(b.MouseLeave, function() b.BackgroundTransparency = 1 end)
    connect(b.MouseButton1Click, function()
        openPicker(label, get(), function(c)
            set(c)
            sw.BackgroundColor3 = c
        end)
    end)
    return b
end

local function vgrid()
    vorder = vorder + 1
    local g = Instance.new("Frame")
    g.LayoutOrder = vorder
    g.Size = UDim2.new(1, -8, 0, 0)
    g.AutomaticSize = Enum.AutomaticSize.Y
    g.BackgroundTransparency = 1
    g.Parent = visualsPage
    local gl = Instance.new("UIGridLayout")
    gl.CellSize = UDim2.fromOffset(98, 26)
    gl.CellPadding = UDim2.fromOffset(4, 4)
    gl.SortOrder = Enum.SortOrder.LayoutOrder
    gl.Parent = g
    return g
end

local function gridButton(g, label, onClick)
    local b = Instance.new("TextButton")
    b.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
    b.BorderSizePixel = 0
    b.Text = label
    b.TextColor3 = Color3.fromRGB(220, 220, 225)
    b.Font = Enum.Font.Gotham
    b.TextSize = 12
    b.AutoButtonColor = false
    b.Parent = g
    corner(b, 5)
    connect(b.MouseButton1Click, onClick)
    return b
end

local auraBtns, skyBtns = {}, {}
local rtxBtn
local hatBtn, espBtn, namesBtn, resetBtn
local weatherBtns, wIntBtns, farmBtns = {}, {}, {}
local WEATHER_INTS = { 0.5, 1, 2, 4 }

vrow("/return  back to bot control", function() showPage("main") end)

vheader("Auras  (/aura &lt;name&gt; | /aura off)", "#7fd1ff")
do
    local g = vgrid()
    for _, name in ipairs(AURA_NAMES) do
        auraBtns[name] = gridButton(g, name, function() toggleAura(name) end)
    end
    gridButton(g, "off", function() clearAuraSel() end)
end
vrow("Click to stack/unstack. Aura models load on first use.")

vheader("RTX mode  (/rtx on | off)", "#ffb86b")
do
    local g = vgrid()
    rtxBtn = gridButton(g, "RTX: OFF", function() setRTX(not rtxOn) end)
end

vheader("Custom skybox  (/sky &lt;name&gt; | /sky off)", "#c792ea")
do
    local g = vgrid()
    for _, name in ipairs(SKY_ORDER) do
        skyBtns[name] = gridButton(g, name, function() setSky(true, name) end)
    end
    gridButton(g, "off", function() setSky(false) end)
end

vheader("China hat  (/hat on | off)", "#ff8f8f")
do
    local g = vgrid()
    hatBtn = gridButton(g, "Hat: OFF", function() setHat(not hatOn) end)
end
vcolor("Hat color", function() return hatColor end, function(c) setHatColor(c) end)

vheader("Weather  (/weather &lt;type&gt; | /weather off)", "#8be9fd")
do
    local g = vgrid()
    for _, t in ipairs(WEATHER_ORDER) do
        weatherBtns[t] = gridButton(g, WEATHER_LABELS[t], function()
            if weatherOn and weatherType == t then setWeather(false) else setWeather(true, t) end
        end)
    end
    gridButton(g, "off", function() setWeather(false) end)
end
vcolor("Weather color", function() return weatherColor end, function(c) setWeatherColor(c) end)
vrow("Intensity:")
do
    local g = vgrid()
    for _, v in ipairs(WEATHER_INTS) do
        wIntBtns[v] = gridButton(g, "x" .. tostring(v), function() setWeatherInt(v) end)
    end
end

vheader("ESP  (/esp on | off)  roles, this account only", "#50fa7b")
do
    local g = vgrid()
    espBtn = gridButton(g, "Chams: OFF", function() setESP(not espOn, espNames) end)
    namesBtn = gridButton(g, "Names: OFF", function() setESP(espOn, not espNames) end)
end
vcolor("Murderer color", function() return ROLE_COLORS.Murderer end, function(c) ROLE_COLORS.Murderer = c end)
vcolor("Sheriff color", function() return ROLE_COLORS.Sheriff end, function(c) ROLE_COLORS.Sheriff = c end)
vcolor("Innocent color", function() return ROLE_COLORS.Innocent end, function(c) ROLE_COLORS.Innocent = c end)
vcolor("Hero color", function() return ROLE_COLORS.Hero end, function(c) ROLE_COLORS.Hero = c end)

vheader("Autofarm  (/farm candy | coin | off)  this account", "#f1fa8c")
do
    local g = vgrid()
    for _, t in ipairs({ "Candy", "Coin" }) do
        farmBtns[t] = gridButton(g, t, function()
            if AF.On and AF.Type == t then setFarm(nil) else setFarm(t) end
        end)
    end
    gridButton(g, "off", function() setFarm(nil) end)
    resetBtn = gridButton(g, "Reset full: ON", function()
        AF.ResetOnFull = not AF.ResetOnFull
        if paintVisuals then paintVisuals() end
    end)
end
farmStatus = vrow("Autofarm is off.")

paintVisuals = function()
    local idle, idleText = Color3.fromRGB(40, 40, 50), Color3.fromRGB(220, 220, 225)
    local activeText = Color3.fromRGB(30, 30, 34)
    local function paint(b, active)
        if not b then return end
        b.BackgroundColor3 = active and PINK or idle
        b.TextColor3 = active and activeText or idleText
    end
    for name, b in pairs(auraBtns) do paint(b, auraSel[name]) end
    for name, b in pairs(skyBtns) do paint(b, skyOn and skyType == name) end
    if rtxBtn then
        rtxBtn.Text = rtxOn and "RTX: ON" or "RTX: OFF"
        paint(rtxBtn, rtxOn)
    end
    if hatBtn then
        hatBtn.Text = hatOn and "Hat: ON" or "Hat: OFF"
        paint(hatBtn, hatOn)
    end
    for t, b in pairs(weatherBtns) do paint(b, weatherOn and weatherType == t) end
    for v, b in pairs(wIntBtns) do paint(b, weatherInt == v) end
    if espBtn then
        espBtn.Text = espOn and "Chams: ON" or "Chams: OFF"
        paint(espBtn, espOn)
    end
    if namesBtn then
        namesBtn.Text = espNames and "Names: ON" or "Names: OFF"
        paint(namesBtn, espNames)
    end
    for t, b in pairs(farmBtns) do paint(b, AF.On and AF.Type == t) end
    if resetBtn then
        resetBtn.Text = AF.ResetOnFull and "Reset full: ON" or "Reset full: OFF"
        paint(resetBtn, AF.ResetOnFull)
    end
    pcall(updateFarmStatus)
end
paintVisuals()

showPage = function(p)
    page = p
    closePicker()
    scroll.Visible = (p == "main")
    visualsPage.Visible = (p == "visuals")
    refreshTitle()
end

-- Resize handle
local grip = Instance.new("TextButton")
grip.Size = UDim2.fromOffset(16, 16)
grip.Position = UDim2.new(1, -18, 1, -18)
grip.BackgroundTransparency = 1
grip.BorderSizePixel = 0
grip.Text = ""
grip.AutoButtonColor = false
grip.ZIndex = 5
grip.Parent = frame

local GRIP_COLOR = Color3.fromRGB(235, 235, 245)
local GRIP_IDLE, GRIP_HOVER = 0.75, 0.35

local vLine = Instance.new("Frame")
vLine.Size = UDim2.new(0, 2, 1, 0)
vLine.Position = UDim2.new(1, -2, 0, 0)
vLine.BackgroundColor3 = GRIP_COLOR
vLine.BackgroundTransparency = GRIP_IDLE
vLine.BorderSizePixel = 0
vLine.ZIndex = 5
vLine.Parent = grip

local hLine = Instance.new("Frame")
hLine.Size = UDim2.new(1, 0, 0, 2)
hLine.Position = UDim2.new(0, 0, 1, -2)
hLine.BackgroundColor3 = GRIP_COLOR
hLine.BackgroundTransparency = GRIP_IDLE
hLine.BorderSizePixel = 0
hLine.ZIndex = 5
hLine.Parent = grip

local function gripFade(t)
    vLine.BackgroundTransparency = t
    hLine.BackgroundTransparency = t
end
connect(grip.MouseEnter, function() gripFade(GRIP_HOVER) end)
connect(grip.MouseLeave, function()
    if not getgenv().__gripDrag then gripFade(GRIP_IDLE) end
end)

local MIN_W, MIN_H, MAX_W, MAX_H = 360, 300, 900, 820
local resizing, rStart, rSize
connect(grip.InputBegan, function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        resizing, rStart, rSize = true, i.Position, frame.AbsoluteSize
        getgenv().__gripDrag = true
        gripFade(GRIP_HOVER)
    end
end)

-- Dragging
local dragging, dragStart, startPos
connect(title.InputBegan, function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        dragging, dragStart, startPos = true, i.Position, frame.Position
    end
end)

connect(UIS.InputChanged, function(i)
    local moving = i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch
    if not moving then return end
    if resizing then
        local d = i.Position - rStart
        local w = math.clamp(rSize.X + d.X, MIN_W, MAX_W)
        local h = math.clamp(rSize.Y + d.Y, MIN_H, MAX_H)
        frame.Size = UDim2.fromOffset(w, h)
    elseif dragging then
        local d = i.Position - dragStart
        frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
    end
end)

connect(UIS.InputEnded, function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        dragging = false
        if resizing then
            resizing = false
            getgenv().__gripDrag = false
            gripFade(GRIP_IDLE)
        end
    end
end)

-- Toggle key (ignores gameProcessed: only doesn't work while you are typing in another TextBox)
connect(UIS.InputBegan, function(i)
    if i.KeyCode ~= (getgenv().MenuKey or Enum.KeyCode.RightControl) then return end
    local fb = UIS:GetFocusedTextBox()
    if fb ~= nil and fb ~= bar then return end
    if shown then
        pcall(function() bar:ReleaseFocus() end)
        closePicker()
        hideFrame()
    else
        showFrame()
    end
end)

-- Start hooking the round remotes (MM2). Retries every 3s in case they appear late.
task.spawn(function()
    while gui.Parent do
        pcall(hookRemotes)
        task.wait(3)
    end
end)

-- Start: open animation + title typewriter
showFrame()
task.spawn(function()
    local n = utf8.len(title.Text) or #title.Text
    for i = 0, n do
        if not title.Parent then return end
        title.MaxVisibleGraphemes = i
        task.wait(0.02)
    end
    title.MaxVisibleGraphemes = -1
end)

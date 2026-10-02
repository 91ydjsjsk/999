--[[
    Pistol Arena Hub  |  手枪竞技场
    Client Script with WindUI
    Remotes captured via Remote Spy (Cobalt)
]]

-- // WindUI Loader
local cloneref = (cloneref or clonereference or function(instance)
    return instance
end)
local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))
local WindUI
do
    local ok, result = pcall(function()
        return require(ReplicatedStorage:WaitForChild("WindUI"):WaitForChild("Init"))
    end)
    if ok then
        WindUI = result
    else
        WindUI = loadstring(game:HttpGet("https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"))()
    end
end

-- // Services
local Players = cloneref(game:GetService("Players"))
local RunService = cloneref(game:GetService("RunService"))
local UserInputService = cloneref(game:GetService("UserInputService"))
local Workspace = cloneref(game:GetService("Workspace"))
local Lighting = cloneref(game:GetService("Lighting"))
local TweenService = cloneref(game:GetService("TweenService"))
local Camera = Workspace.CurrentCamera

local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

-- // Remote Paths (captured from Remote Spy)
local RemoteEvents = ReplicatedStorage:WaitForChild("Events"):WaitForChild("RemoteEvents")
local BufferCache = ReplicatedStorage:WaitForChild("SystemResources"):WaitForChild("BufferCache")

local Remotes = {
    RequestActionSync      = BufferCache:WaitForChild("RequestActionSync"),
    ReplicateFakeBullet    = RemoteEvents:WaitForChild("ReplicateFakeBullet"),
    CharacterMuzzleFlash   = RemoteEvents:WaitForChild("CharacterMuzzleFlash"),
    ReplicateImpactEffect  = RemoteEvents:WaitForChild("ReplicateImpactEffect"),
    ValidateSprint         = RemoteEvents:WaitForChild("ValidateSprint"),
    ReplicateSlidingEffect = RemoteEvents:WaitForChild("ReplicateSlidingEffect"),
    DeathScreenButtonPressed = RemoteEvents:WaitForChild("DeathScreenButtonPressed"),
    SpectateTarget         = RemoteEvents:WaitForChild("SpectateTarget"),
    PlayerDied             = RemoteEvents:WaitForChild("PlayerDied"),
    KillfeedEntry          = RemoteEvents:WaitForChild("KillfeedEntry"),
}

-- // Settings
local Settings = {
    -- Combat
    SilentAim = false,
    SilentAimHitbox = true,
    Aimbot = false,
    AimbotSmoothness = 0.15,
    FOV = 180,
    FOVCircle = false,
    FOVColor = Color3.fromRGB(255, 255, 255),
    TargetPart = "Head",
    Triggerbot = false,
    NoSpread = true,
    NoRecoil = true,
    IgnoreTeammates = true,

    -- Visuals
    ESP = false,
    ESPBoxes = true,
    ESPNames = true,
    ESPHealth = true,
    ESPDistance = true,
    ESPTracers = false,
    ESPTeamColor = true,
    Fullbright = false,
    NoFog = false,

    -- Movement
    SpeedHack = false,
    SpeedValue = 32,
    JumpPower = false,
    JumpValue = 120,
    InfiniteSlide = false,
    Fly = false,
    FlySpeed = 60,
    NoClip = false,

    -- Misc
    AutoRespawn = true,
    AntiAFK = true,
    AutoSpectate = false,
}

-- // Utility
local function getCharacter(player)
    return player and player.Character
end

local function getHumanoid(player)
    local char = getCharacter(player)
    return char and char:FindFirstChildOfClass("Humanoid")
end

local function getRootPart(player)
    local char = getCharacter(player)
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function getPart(player, partName)
    local char = getCharacter(player)
    if not char then return nil end
    return char:FindFirstChild(partName) or char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
end

local function isAlive(player)
    local hum = getHumanoid(player)
    return hum and hum.Health > 0
end

local function isTeammate(player)
    if not Settings.IgnoreTeammates then return false end
    if player.Team and LocalPlayer.Team then
        return player.Team == LocalPlayer.Team
    end
    return false
end

local function worldToScreen(pos)
    local screenPos, onScreen = Camera:WorldToViewportPoint(pos)
    return Vector2.new(screenPos.X, screenPos.Y), onScreen, screenPos.Z
end

local function getNearestTarget(useFOV)
    local cameraPos = Camera.CFrame.Position
    local mouseCenter = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    local nearest = nil
    local nearestDist = math.huge

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and isAlive(player) and not isTeammate(player) then
            local part = getPart(player, Settings.TargetPart)
            if part then
                local screenPos, onScreen, depth = worldToScreen(part.Position)
                if onScreen and depth > 0 then
                    local dist = (screenPos - mouseCenter).Magnitude
                    if not useFOV or dist <= Settings.FOV then
                        if dist < nearestDist then
                            nearestDist = dist
                            nearest = player
                        end
                    end
                end
            end
        end
    end
    return nearest, nearestDist
end

-- // Silent Aim Hook
local oldNamecall
local hookSuccess = false

local function setupSilentAimHook()
    if hookSuccess then return end
    local mt = getrawmetatable(game)
    oldNamecall = mt.__namecall
    if setreadonly then
        pcall(setreadonly, mt, false)
    end

    mt.__namecall = newcclosure(function(self, ...)
        local method = getnamecallmethod and getnamecallmethod() or nil
        if method == "FireServer" and self == Remotes.RequestActionSync then
            local args = {...}
            local data = args[1]
            if type(data) == "table" and data.origin then
                if Settings.SilentAim then
                    local target = getNearestTarget(true)
                    if target then
                        local targetPart = getPart(target, Settings.TargetPart)
                        if targetPart then
                            local origin = data.origin
                            local targetPos = targetPart.Position
                            local newDirection = (targetPos - origin).Unit
                            data.direction = newDirection
                            data.hitPosition = targetPos
                            if Settings.SilentAimHitbox then
                                data.hitInstance = targetPart
                                data.hits = {targetPart}
                            end
                        end
                    end
                elseif Settings.NoSpread and data.direction then
                    -- keep direction perfectly straight (no random spread)
                    -- direction is already the intended aim; ensure it's normalized
                    data.direction = data.direction.Unit
                end
            end
            return oldNamecall(self, unpack(args))
        end
        return oldNamecall(self, ...)
    end)

    if setreadonly then
        pcall(setreadonly, mt, true)
    end
    hookSuccess = true
end

-- // Aimbot (visible camera rotation)
local aimbotTarget = nil
RunService:BindToRenderStep("AimbotUpdate", Enum.RenderPriority.Camera.Value + 1, function()
    if Settings.Aimbot then
        local target = getNearestTarget(true)
        if target then
            local part = getPart(target, Settings.TargetPart)
            if part then
                local cameraPos = Camera.CFrame.Position
                local targetPos = part.Position
                local desiredCFrame = CFrame.new(cameraPos, targetPos)
                Camera.CFrame = Camera.CFrame:Lerp(desiredCFrame, Settings.AimbotSmoothness)
            end
        end
    end
end)

-- // FOV Circle
local fovCircle = Drawing and Drawing.new("Circle") or nil
if fovCircle then
    fovCircle.Visible = false
    fovCircle.Color = Settings.FOVColor
    fovCircle.Thickness = 1
    fovCircle.NumSides = 64
    fovCircle.Radius = Settings.FOV
    fovCircle.Filled = false
end

RunService:BindToRenderStep("FOVCircleUpdate", Enum.RenderPriority.Camera.Value + 2, function()
    if fovCircle then
        fovCircle.Visible = Settings.FOVCircle
        fovCircle.Color = Settings.FOVColor
        fovCircle.Radius = Settings.FOV
        fovCircle.Position = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    end
end)

-- // ESP
local DrawingAvailable = (Drawing ~= nil)
local espDrawings = {}

local function clearESP()
    for _, drawing in pairs(espDrawings) do
        pcall(function() drawing:Remove() end)
    end
    espDrawings = {}
end

local function updateESP()
    if not DrawingAvailable then return end
    if not Settings.ESP then
        for _, drawing in pairs(espDrawings) do
            pcall(function() drawing.Visible = false end)
        end
        return
    end

    local cameraPos = Camera.CFrame.Position

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and isAlive(player) and not isTeammate(player) then
            local char = getCharacter(player)
            local root = getRootPart(player)
            if char and root then
                local rootScreen, onScreen, depth = worldToScreen(root.Position)
                if onScreen and depth > 0 then
                    local dist = (root.Position - cameraPos).Magnitude
                    local scale = 1 / (depth * math.tan(math.rad(Camera.FieldOfView / 2))) * 100
                    local boxHeight = scale * 4
                    local boxWidth = scale * 2
                    local teamColor = (Settings.ESPTeamColor and player.TeamColor and player.TeamColor.Color) or Color3.fromRGB(255, 0, 0)

                    -- Box
                    if Settings.ESPBoxes then
                        if not espDrawings[player.Name .. "_box"] then
                            espDrawings[player.Name .. "_box"] = Drawing.new("Square")
                        end
                        local box = espDrawings[player.Name .. "_box"]
                        box.Visible = true
                        box.Color = teamColor
                        box.Thickness = 1
                        box.Filled = false
                        box.Size = Vector2.new(boxWidth, boxHeight)
                        box.Position = rootScreen - Vector2.new(boxWidth / 2, boxHeight / 2)
                    elseif espDrawings[player.Name .. "_box"] then
                        espDrawings[player.Name .. "_box"].Visible = false
                    end

                    -- Name
                    if Settings.ESPNames then
                        if not espDrawings[player.Name .. "_name"] then
                            espDrawings[player.Name .. "_name"] = Drawing.new("Text")
                        end
                        local text = espDrawings[player.Name .. "_name"]
                        text.Visible = true
                        text.Color = Color3.fromRGB(255, 255, 255)
                        text.Text = player.Name
                        text.Size = 14
                        text.Center = true
                        text.Outline = true
                        text.Position = rootScreen - Vector2.new(0, boxHeight / 2 + 16)
                    elseif espDrawings[player.Name .. "_name"] then
                        espDrawings[player.Name .. "_name"].Visible = false
                    end

                    -- Health
                    if Settings.ESPHealth then
                        local hum = getHumanoid(player)
                        if hum then
                            if not espDrawings[player.Name .. "_health"] then
                                espDrawings[player.Name .. "_health"] = Drawing.new("Text")
                            end
                            local htext = espDrawings[player.Name .. "_health"]
                            htext.Visible = true
                            htext.Color = Color3.fromRGB(0, 255, 0)
                            htext.Text = tostring(math.floor(hum.Health)) .. " HP"
                            htext.Size = 12
                            htext.Center = true
                            htext.Outline = true
                            htext.Position = rootScreen + Vector2.new(0, boxHeight / 2 + 2)
                        end
                    elseif espDrawings[player.Name .. "_health"] then
                        espDrawings[player.Name .. "_health"].Visible = false
                    end

                    -- Distance
                    if Settings.ESPDistance then
                        if not espDrawings[player.Name .. "_dist"] then
                            espDrawings[player.Name .. "_dist"] = Drawing.new("Text")
                        end
                        local dtext = espDrawings[player.Name .. "_dist"]
                        dtext.Visible = true
                        dtext.Color = Color3.fromRGB(255, 255, 0)
                        dtext.Text = tostring(math.floor(dist)) .. " studs"
                        dtext.Size = 12
                        dtext.Center = true
                        dtext.Outline = true
                        dtext.Position = rootScreen + Vector2.new(boxWidth / 2 + 28, 0)
                    elseif espDrawings[player.Name .. "_dist"] then
                        espDrawings[player.Name .. "_dist"].Visible = false
                    end

                    -- Tracers
                    if Settings.ESPTracers then
                        if not espDrawings[player.Name .. "_tracer"] then
                            espDrawings[player.Name .. "_tracer"] = Drawing.new("Line")
                        end
                        local line = espDrawings[player.Name .. "_tracer"]
                        line.Visible = true
                        line.Color = teamColor
                        line.Thickness = 1
                        line.From = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y)
                        line.To = rootScreen
                    elseif espDrawings[player.Name .. "_tracer"] then
                        espDrawings[player.Name .. "_tracer"].Visible = false
                    end
                end
            end
        else
            for _, suffix in ipairs({"box", "name", "health", "dist", "tracer"}) do
                if espDrawings[player.Name .. "_" .. suffix] then
                    espDrawings[player.Name .. "_" .. suffix].Visible = false
                end
            end
        end
    end
end

RunService:BindToRenderStep("ESPUpdate", Enum.RenderPriority.Camera.Value + 3, updateESP)

-- // Movement Hacks
local originalWalkSpeed = 16
local originalJumpPower = 50

RunService.Heartbeat:Connect(function()
    local hum = getHumanoid(LocalPlayer)
    if hum then
        if Settings.SpeedHack then
            hum.WalkSpeed = Settings.SpeedValue
        end
        if Settings.JumpPower then
            hum.UseJumpPower = true
            hum.JumpPower = Settings.JumpValue
        end
    end

    -- NoClip
    if Settings.NoClip then
        local char = getCharacter(LocalPlayer)
        if char then
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.CanCollide = false
                end
            end
        end
    end
end)

-- // Fly
local flyConnection
local function startFly()
    if flyConnection then return end
    local flying = false
    local bodyGyro, bodyVel

    flyConnection = UserInputService.InputBegan:Connect(function(input)
        if input.KeyCode == Enum.KeyCode.F then
            flying = not flying
            local char = getCharacter(LocalPlayer)
            local root = getRootPart(LocalPlayer)
            if not char or not root then return end

            if flying then
                bodyGyro = Instance.new("BodyGyro")
                bodyGyro.P = 9e4
                bodyGyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
                bodyGyro.CFrame = root.CFrame
                bodyGyro.Parent = root

                bodyVel = Instance.new("BodyVelocity")
                bodyVel.MaxForce = Vector3.new(9e9, 9e9, 9e9)
                bodyVel.Velocity = Vector3.new(0, 0, 0)
                bodyVel.Parent = root
            else
                if bodyGyro then bodyGyro:Destroy() end
                if bodyVel then bodyVel:Destroy() end
            end
        end
    end)

    RunService.RenderStepped:Connect(function()
        if flying and bodyGyro and bodyVel then
            local root = getRootPart(LocalPlayer)
            if root then
                bodyGyro.CFrame = Camera.CFrame
                local speed = Settings.FlySpeed
                local moveDir = Vector3.new(0, 0, 0)

                if UserInputService:IsKeyDown(Enum.KeyCode.W) then
                    moveDir = moveDir + Camera.CFrame.LookVector
                end
                if UserInputService:IsKeyDown(Enum.KeyCode.S) then
                    moveDir = moveDir - Camera.CFrame.LookVector
                end
                if UserInputService:IsKeyDown(Enum.KeyCode.A) then
                    moveDir = moveDir - Camera.CFrame.RightVector
                end
                if UserInputService:IsKeyDown(Enum.KeyCode.D) then
                    moveDir = moveDir + Camera.CFrame.RightVector
                end
                if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
                    moveDir = moveDir + Vector3.new(0, 1, 0)
                end
                if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
                    moveDir = moveDir - Vector3.new(0, 1, 0)
                end

                bodyVel.Velocity = moveDir * speed
            end
        end
    end)
end

-- // Infinite Slide
local slideConnection
local function setupInfiniteSlide()
    if slideConnection then return end
    slideConnection = RunService.Heartbeat:Connect(function()
        if Settings.InfiniteSlide then
            pcall(function()
                Remotes.ReplicateSlidingEffect:FireServer(true)
            end)
        end
    end)
end

-- // Auto Respawn
Remotes.PlayerDied.OnClientEvent:Connect(function(character, pos, killer)
    if Settings.AutoRespawn then
        task.wait(0.5)
        pcall(function()
            Remotes.DeathScreenButtonPressed:FireServer("Respawn")
        end)
    end
end)

-- // Anti AFK
if Settings.AntiAFK then
    local virtualUser = game:GetService("VirtualUser")
    LocalPlayer.Idled:Connect(function()
        virtualUser:CaptureController()
        virtualUser:ClickButton2(Vector2.new())
    end)
end

-- // Fullbright / No Fog
local originalBrightness = Lighting.Brightness
local originalAmbient = Lighting.Ambient
local originalFogEnd = Lighting.FogEnd

task.spawn(function()
    while task.wait(0.5) do
        if Settings.Fullbright then
            Lighting.Brightness = 2
            Lighting.Ambient = Color3.fromRGB(178, 178, 178)
            Lighting.GlobalShadows = false
        end
        if Settings.NoFog then
            Lighting.FogEnd = 1e9
        end
    end
end)

-- // Setup hooks
setupSilentAimHook()
setupInfiniteSlide()
startFly()

-- // UI Creation
local Window = WindUI:CreateWindow({
    Title = "Pistol Arena Hub | 手枪竞技场",
    Folder = "pistolarena",
    Icon = "solar:crosshair-bold",
    NewElements = true,
    OpenButton = {
        Title = "Open Hub",
        CornerRadius = UDim.new(1, 0),
        StrokeThickness = 3,
        Enabled = true,
        Draggable = true,
        OnlyMobile = true,
        Scale = 0.5,
        Color = ColorSequence.new(
            Color3.fromHex("#ff4830"),
            Color3.fromHex("#ff8c30")
        ),
    },
    Topbar = {
        Height = 44,
        ButtonsType = "Mac",
    },
})

-- // Colors
local Red = Color3.fromHex("#EF4F1D")
local Green = Color3.fromHex("#10C550")
local Blue = Color3.fromHex("#257AF7")
local Yellow = Color3.fromHex("#ECA201")
local Purple = Color3.fromHex("#7775F2")
local Grey = Color3.fromHex("#83889E")

-- // Combat Tab
do
    local CombatTab = Window:Tab({
        Title = "Combat",
        Icon = "solar:crosshair-bold",
        IconColor = Red,
        IconShape = "Square",
        Border = true,
    })

    local SilentAimSection = CombatTab:Section({
        Title = "Silent Aim",
        Box = true,
        BoxBorder = true,
        Opened = true,
    })

    SilentAimSection:Toggle({
        Title = "Silent Aim",
        Desc = "Redirect bullets to nearest enemy",
        Default = Settings.SilentAim,
        Callback = function(v)
            Settings.SilentAim = v
        end,
    })
    SilentAimSection:Toggle({
        Title = "Hitbox Expander",
        Desc = "Set hitInstance to target part",
        Default = Settings.SilentAimHitbox,
        Callback = function(v)
            Settings.SilentAimHitbox = v
        end,
    })
    SilentAimSection:Dropdown({
        Title = "Target Part",
        Values = {
            { Title = "Head", Callback = function() Settings.TargetPart = "Head" end },
            { Title = "HumanoidRootPart", Callback = function() Settings.TargetPart = "HumanoidRootPart" end },
            { Title = "UpperTorso", Callback = function() Settings.TargetPart = "UpperTorso" end },
            { Title = "LowerTorso", Callback = function() Settings.TargetPart = "LowerTorso" end },
        },
    })

    local AimbotSection = CombatTab:Section({
        Title = "Aimbot (Visible)",
        Box = true,
        BoxBorder = true,
        Opened = false,
    })

    AimbotSection:Toggle({
        Title = "Aimbot",
        Desc = "Rotate camera to target",
        Default = Settings.Aimbot,
        Callback = function(v)
            Settings.Aimbot = v
        end,
    })
    AimbotSection:Slider({
        Title = "Smoothness",
        Step = 0.01,
        Value = { Min = 0.01, Max = 1, Default = Settings.AimbotSmoothness },
        Callback = function(v)
            Settings.AimbotSmoothness = v
        end,
    })

    local FOVSection = CombatTab:Section({
        Title = "FOV",
        Box = true,
        BoxBorder = true,
        Opened = false,
    })

    FOVSection:Toggle({
        Title = "FOV Circle",
        Default = Settings.FOVCircle,
        Callback = function(v)
            Settings.FOVCircle = v
        end,
    })
    FOVSection:Slider({
        Title = "FOV Radius",
        Step = 5,
        Value = { Min = 10, Max = 500, Default = Settings.FOV },
        Callback = function(v)
            Settings.FOV = v
        end,
    })
    FOVSection:Colorpicker({
        Title = "FOV Color",
        Default = Settings.FOVColor,
        Callback = function(c)
            Settings.FOVColor = c
        end,
    })

    local GunSection = CombatTab:Section({
        Title = "Gun Mods",
        Box = true,
        BoxBorder = true,
        Opened = false,
    })

    GunSection:Toggle({
        Title = "No Spread",
        Desc = "Remove bullet spread",
        Default = Settings.NoSpread,
        Callback = function(v)
            Settings.NoSpread = v
        end,
    })
    GunSection:Toggle({
        Title = "No Recoil",
        Desc = "Recoil already client-side",
        Default = Settings.NoRecoil,
        Callback = function(v)
            Settings.NoRecoil = v
        end,
    })
    GunSection:Toggle({
        Title = "Ignore Teammates",
        Default = Settings.IgnoreTeammates,
        Callback = function(v)
            Settings.IgnoreTeammates = v
        end,
    })
end

-- // Visuals Tab
do
    local VisualsTab = Window:Tab({
        Title = "Visuals",
        Icon = "solar:eye-bold",
        IconColor = Blue,
        IconShape = "Square",
        Border = true,
    })

    local ESPSection = VisualsTab:Section({
        Title = "ESP",
        Box = true,
        BoxBorder = true,
        Opened = true,
    })

    ESPSection:Toggle({
        Title = "Enable ESP",
        Default = Settings.ESP,
        Callback = function(v)
            Settings.ESP = v
        end,
    })
    ESPSection:Toggle({
        Title = "Boxes",
        Default = Settings.ESPBoxes,
        Callback = function(v)
            Settings.ESPBoxes = v
        end,
    })
    ESPSection:Toggle({
        Title = "Names",
        Default = Settings.ESPNames,
        Callback = function(v)
            Settings.ESPNames = v
        end,
    })
    ESPSection:Toggle({
        Title = "Health",
        Default = Settings.ESPHealth,
        Callback = function(v)
            Settings.ESPHealth = v
        end,
    })
    ESPSection:Toggle({
        Title = "Distance",
        Default = Settings.ESPDistance,
        Callback = function(v)
            Settings.ESPDistance = v
        end,
    })
    ESPSection:Toggle({
        Title = "Tracers",
        Default = Settings.ESPTracers,
        Callback = function(v)
            Settings.ESPTracers = v
        end,
    })
    ESPSection:Toggle({
        Title = "Team Color",
        Default = Settings.ESPTeamColor,
        Callback = function(v)
            Settings.ESPTeamColor = v
        end,
    })

    local WorldSection = VisualsTab:Section({
        Title = "World",
        Box = true,
        BoxBorder = true,
        Opened = false,
    })

    WorldSection:Toggle({
        Title = "Fullbright",
        Default = Settings.Fullbright,
        Callback = function(v)
            Settings.Fullbright = v
            if not v then
                Lighting.Brightness = originalBrightness
                Lighting.Ambient = originalAmbient
                Lighting.GlobalShadows = true
            end
        end,
    })
    WorldSection:Toggle({
        Title = "No Fog",
        Default = Settings.NoFog,
        Callback = function(v)
            Settings.NoFog = v
            if not v then
                Lighting.FogEnd = originalFogEnd
            end
        end,
    })
end

-- // Movement Tab
do
    local MovementTab = Window:Tab({
        Title = "Movement",
        Icon = "solar:running-bold",
        IconColor = Green,
        IconShape = "Square",
        Border = true,
    })

    MovementTab:Toggle({
        Title = "Speed Hack",
        Default = Settings.SpeedHack,
        Callback = function(v)
            Settings.SpeedHack = v
        end,
    })
    MovementTab:Slider({
        Title = "Speed Value",
        Step = 1,
        Value = { Min = 16, Max = 200, Default = Settings.SpeedValue },
        Callback = function(v)
            Settings.SpeedValue = v
        end,
    })
    MovementTab:Space()

    MovementTab:Toggle({
        Title = "Jump Power",
        Default = Settings.JumpPower,
        Callback = function(v)
            Settings.JumpPower = v
        end,
    })
    MovementTab:Slider({
        Title = "Jump Value",
        Step = 5,
        Value = { Min = 50, Max = 500, Default = Settings.JumpValue },
        Callback = function(v)
            Settings.JumpValue = v
        end,
    })
    MovementTab:Space()

    MovementTab:Toggle({
        Title = "Infinite Slide",
        Default = Settings.InfiniteSlide,
        Callback = function(v)
            Settings.InfiniteSlide = v
        end,
    })
    MovementTab:Space()

    MovementTab:Toggle({
        Title = "Fly (Press F)",
        Default = Settings.Fly,
        Callback = function(v)
            Settings.Fly = v
        end,
    })
    MovementTab:Slider({
        Title = "Fly Speed",
        Step = 5,
        Value = { Min = 10, Max = 300, Default = Settings.FlySpeed },
        Callback = function(v)
            Settings.FlySpeed = v
        end,
    })
    MovementTab:Space()

    MovementTab:Toggle({
        Title = "No Clip",
        Default = Settings.NoClip,
        Callback = function(v)
            Settings.NoClip = v
        end,
    })
end

-- // Misc Tab
do
    local MiscTab = Window:Tab({
        Title = "Misc",
        Icon = "solar:settings-bold",
        IconColor = Yellow,
        IconShape = "Square",
        Border = true,
    })

    MiscTab:Toggle({
        Title = "Auto Respawn",
        Default = Settings.AutoRespawn,
        Callback = function(v)
            Settings.AutoRespawn = v
        end,
    })
    MiscTab:Toggle({
        Title = "Anti AFK",
        Default = Settings.AntiAFK,
        Callback = function(v)
            Settings.AntiAFK = v
        end,
    })
    MiscTab:Toggle({
        Title = "Auto Spectate",
        Default = Settings.AutoSpectate,
        Callback = function(v)
            Settings.AutoSpectate = v
            if v then
                task.spawn(function()
                    while Settings.AutoSpectate do
                        local nearest = getNearestTarget(false)
                        if nearest then
                            pcall(function()
                                Remotes.SpectateTarget:FireServer(nearest)
                            end)
                        end
                        task.wait(1)
                    end
                end)
            end
        end,
    })
    MiscTab:Space()

    MiscTab:Button({
        Title = "Respawn Now",
        Color = Color3.fromHex("#305dff"),
        Justify = "Center",
        Icon = "",
        Callback = function()
            pcall(function()
                Remotes.DeathScreenButtonPressed:FireServer("Respawn")
            end)
        end,
    })
    MiscTab:Space()

    MiscTab:Button({
        Title = "Rejoin",
        Color = Color3.fromHex("#ff4830"),
        Justify = "Center",
        Icon = "",
        Callback = function()
            game:GetService("TeleportService"):TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
        end,
    })
    MiscTab:Space()

    MiscTab:Button({
        Title = "Copy Server Job ID",
        Color = Color3.fromHex("#a2ff30"),
        Justify = "Center",
        Icon = "",
        Callback = function()
            if setclipboard then
                setclipboard(game.JobId)
                WindUI:Notify({
                    Title = "Copied",
                    Content = "Server Job ID copied to clipboard",
                })
            end
        end,
    })
end

-- // Notify
WindUI:Notify({
    Title = "Pistol Arena Hub",
    Content = "Loaded successfully! Remotes hooked.",
    Duration = 5,
})

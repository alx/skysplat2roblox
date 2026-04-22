--[[
  Navigation.client.lua
  Player-side navigation helpers for the SkyPlat world.

  Features:
    • Fly mode toggle  (F key)
    • Sprint           (Shift)
    • Drone-eye view   (V key — top-down orthographic camera)
    • Click-to-teleport on minimap (handled by Minimap.client.lua)
    • Speed HUD
--]]

local Players         = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService      = game:GetService("RunService")
local TweenService    = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player    = Players.LocalPlayer
local camera    = workspace.CurrentCamera
local character = player.Character or player.CharacterAdded:Wait()
local humanoid  = character:WaitForChild("Humanoid")
local root      = character:WaitForChild("HumanoidRootPart")

-- ── Config ───────────────────────────────────────────────────────────────────
local WALK_SPEED     = 24
local SPRINT_SPEED   = 60
local FLY_SPEED      = 120
local FLY_ASCEND     = 60

local flyEnabled     = false
local droneView      = false
local flyBodyVel     : BodyVelocity? = nil
local flyBodyGyro    : BodyGyro?     = nil

-- ── Fly mode ─────────────────────────────────────────────────────────────────
local function enableFly()
    flyEnabled = true
    humanoid.PlatformStand = true

    flyBodyVel = Instance.new("BodyVelocity")
    flyBodyVel.Velocity    = Vector3.zero
    flyBodyVel.MaxForce    = Vector3.new(1e5, 1e5, 1e5)
    flyBodyVel.P           = 1e4
    flyBodyVel.Parent      = root

    flyBodyGyro = Instance.new("BodyGyro")
    flyBodyGyro.MaxTorque  = Vector3.new(1e5, 1e5, 1e5)
    flyBodyGyro.P          = 1e4
    flyBodyGyro.CFrame     = root.CFrame
    flyBodyGyro.Parent     = root
end

local function disableFly()
    flyEnabled = false
    humanoid.PlatformStand = false
    if flyBodyVel  then flyBodyVel:Destroy();  flyBodyVel  = nil end
    if flyBodyGyro then flyBodyGyro:Destroy(); flyBodyGyro = nil end
end

-- ── Drone (top-down) view ────────────────────────────────────────────────────
local savedCameraType : Enum.CameraType
local droneHeight = 300

local function enableDroneView()
    droneView = true
    savedCameraType = camera.CameraType
    camera.CameraType = Enum.CameraType.Scriptable
end

local function disableDroneView()
    droneView = false
    camera.CameraType = savedCameraType or Enum.CameraType.Custom
end

-- ── HUD: speed display ───────────────────────────────────────────────────────
local screenGui = Instance.new("ScreenGui")
screenGui.Name        = "NavHUD"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = player.PlayerGui

local speedLabel = Instance.new("TextLabel")
speedLabel.Size              = UDim2.new(0, 160, 0, 28)
speedLabel.Position          = UDim2.new(0, 12, 1, -42)
speedLabel.AnchorPoint       = Vector2.new(0, 1)
speedLabel.BackgroundColor3  = Color3.fromRGB(15, 15, 15)
speedLabel.BackgroundTransparency = 0.4
speedLabel.TextColor3        = Color3.new(1, 1, 1)
speedLabel.Font               = Enum.Font.Code
speedLabel.TextSize           = 13
speedLabel.Text               = "WALK  24 studs/s"
speedLabel.Parent             = screenGui

local modeLabel = Instance.new("TextLabel")
modeLabel.Size              = UDim2.new(0, 160, 0, 22)
modeLabel.Position          = UDim2.new(0, 12, 1, -70)
modeLabel.AnchorPoint       = Vector2.new(0, 1)
modeLabel.BackgroundTransparency = 1
modeLabel.TextColor3        = Color3.fromRGB(160, 220, 255)
modeLabel.Font               = Enum.Font.GothamBold
modeLabel.TextSize           = 11
modeLabel.Text               = "[F] Fly  [V] Drone view  [Shift] Sprint"
modeLabel.Parent             = screenGui

-- ── Input handling ───────────────────────────────────────────────────────────
UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end

    if input.KeyCode == Enum.KeyCode.F then
        if flyEnabled then
            disableFly()
            humanoid.WalkSpeed = WALK_SPEED
            speedLabel.Text = "WALK  " .. WALK_SPEED .. " studs/s"
        else
            enableFly()
            speedLabel.Text = "FLY   " .. FLY_SPEED .. " studs/s"
        end
    end

    if input.KeyCode == Enum.KeyCode.V then
        if droneView then
            disableDroneView()
        else
            enableDroneView()
        end
    end
end)

-- Sprint
RunService.RenderStepped:Connect(function()
    if not flyEnabled then
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
            humanoid.WalkSpeed = SPRINT_SPEED
            speedLabel.Text = "SPRINT " .. SPRINT_SPEED .. " studs/s"
        else
            humanoid.WalkSpeed = WALK_SPEED
            speedLabel.Text = "WALK   " .. WALK_SPEED .. " studs/s"
        end
    end
end)

-- ── Fly physics loop ─────────────────────────────────────────────────────────
RunService.RenderStepped:Connect(function(_dt)
    if not flyEnabled then return end

    local camCF   = camera.CFrame
    local moveDir = Vector3.zero

    if UserInputService:IsKeyDown(Enum.KeyCode.W) then
        moveDir = moveDir + camCF.LookVector
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.S) then
        moveDir = moveDir - camCF.LookVector
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.A) then
        moveDir = moveDir - camCF.RightVector
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.D) then
        moveDir = moveDir + camCF.RightVector
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
        moveDir = moveDir + Vector3.yAxis
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
        moveDir = moveDir - Vector3.yAxis
    end

    if moveDir.Magnitude > 0 then
        moveDir = moveDir.Unit
    end

    if flyBodyVel then
        flyBodyVel.Velocity = moveDir * FLY_SPEED
    end
    if flyBodyGyro then
        flyBodyGyro.CFrame = camCF
    end
end)

-- ── Drone camera loop ─────────────────────────────────────────────────────────
RunService.RenderStepped:Connect(function(_dt)
    if not droneView then return end

    -- Scroll to adjust height
    local pos = root.Position
    camera.CFrame = CFrame.new(pos + Vector3.new(0, droneHeight, 0))
                  * CFrame.Angles(-math.pi / 2, 0, 0)
end)

UserInputService.InputChanged:Connect(function(input)
    if droneView and input.UserInputType == Enum.UserInputType.MouseWheel then
        droneHeight = math.clamp(droneHeight - input.Position.Z * 30, 80, 1200)
    end
end)

print("[Navigation] Loaded ✓  F=fly, V=drone, Shift=sprint")

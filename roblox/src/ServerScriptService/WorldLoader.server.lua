--[[
  WorldLoader.server.lua
  Runs on the server when the place starts.

  Responsibilities:
    1. Read WorldConfig metadata and broadcast to clients
    2. Anchor terrain + set sky/atmosphere
    3. Create interactive waypoint markers (if waypoints.json was embedded)
    4. Handle player spawn above terrain
--]]

local Players         = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting        = game:GetService("Lighting")
local Workspace       = game:GetService("Workspace")
local RunService      = game:GetService("RunService")

local WorldConfig = require(ReplicatedStorage:WaitForChild("WorldConfig"))

-- ── Sky & atmosphere ─────────────────────────────────────────────────────────
local function setupEnvironment()
    -- Daylight cycle off — freeze at golden hour (14:00)
    Lighting.TimeOfDay = "14:00:00"
    Lighting.Brightness = 2.2
    Lighting.GlobalShadows = true
    Lighting.Technology = Enum.Technology.Future

    -- Soft blue sky
    local sky = Instance.new("Sky")
    sky.SkyboxBk = "rbxassetid://6444884337"
    sky.SkyboxDn = "rbxassetid://6444884337"
    sky.SkyboxFt = "rbxassetid://6444884337"
    sky.SkyboxLf = "rbxassetid://6444884337"
    sky.SkyboxRt = "rbxassetid://6444884337"
    sky.SkyboxUp = "rbxassetid://6444884337"
    sky.Parent = Lighting

    -- Subtle atmosphere (mimics aerial haze from drone footage)
    local atm = Instance.new("Atmosphere")
    atm.Density = 0.25
    atm.Offset  = 0.20
    atm.Haze    = 0.1
    atm.Glare   = 0.0
    atm.Color   = Color3.fromRGB(200, 214, 231)
    atm.Parent  = Lighting
end

-- ── Spawn players above terrain ──────────────────────────────────────────────
local function getTerrainHeightAt(cx, cz)
    local rayOrigin = Vector3.new(cx, 2000, cz)
    local rayDir    = Vector3.new(0, -4000, 0)
    local params    = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances = {Workspace.Terrain}
    local result = Workspace:Raycast(rayOrigin, rayDir, params)
    return result and result.Position.Y or 20
end

local function spawnPlayerAboveTerrain(player)
    local character = player.Character or player.CharacterAdded:Wait()
    local root = character:WaitForChild("HumanoidRootPart", 5)
    if not root then return end

    local y = getTerrainHeightAt(0, 0) + 10
    root.CFrame = CFrame.new(0, y, 0)
end

-- ── RemoteEvent: request world info from client ──────────────────────────────
local WorldInfoEvent = Instance.new("RemoteFunction")
WorldInfoEvent.Name = "GetWorldInfo"
WorldInfoEvent.Parent = ReplicatedStorage

WorldInfoEvent.OnServerInvoke = function(_player)
    return WorldConfig
end

-- ── Waypoint parts (optional — placed at (0,h,0) origin marker) ──────────────
local function createOriginMarker()
    local h = getTerrainHeightAt(0, 0)
    local marker = Instance.new("Part")
    marker.Name       = "OriginMarker"
    marker.Size       = Vector3.new(4, 4, 4)
    marker.CFrame     = CFrame.new(0, h + 2, 0)
    marker.Anchored   = true
    marker.Material   = Enum.Material.Neon
    marker.BrickColor = BrickColor.new("Bright red")
    marker.Shape      = Enum.PartType.Ball
    marker.CanCollide = false

    local bill = Instance.new("BillboardGui")
    bill.Size          = UDim2.new(0, 120, 0, 40)
    bill.StudsOffset   = Vector3.new(0, 4, 0)
    bill.AlwaysOnTop   = false
    bill.Parent        = marker

    local label = Instance.new("TextLabel")
    label.Size            = UDim2.new(1, 0, 1, 0)
    label.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    label.BackgroundTransparency = 0.3
    label.TextColor3      = Color3.new(1, 1, 1)
    label.Text            = "📡 Origin"
    label.Font            = Enum.Font.GothamBold
    label.TextScaled      = true
    label.Parent          = bill

    marker.Parent = Workspace
end

-- ── Init ─────────────────────────────────────────────────────────────────────
setupEnvironment()
task.defer(createOriginMarker)

Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function(_char)
        task.wait(0.5)
        spawnPlayerAboveTerrain(player)
    end)
end)

print("[WorldLoader] SkyPlat world ready ✓")
print(string.format("[WorldLoader] World: %dx%d studs",
    WorldConfig.roblox and WorldConfig.roblox.world_width_studs or 2048,
    WorldConfig.roblox and WorldConfig.roblox.world_depth_studs or 2048))

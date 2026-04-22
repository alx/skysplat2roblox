--[[
  Minimap.client.lua
  Top-right HUD minimap showing player position in the world.

  • Draws a square top-down map (uses colormap.png uploaded as a Decal asset)
  • Player dot + compass heading
  • Click anywhere on minimap → fly/teleport to that world position
  • Toggle minimap: M key
--]]

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService     = game:GetService("TweenService")

local player    = Players.LocalPlayer
local camera    = workspace.CurrentCamera

-- WorldConfig gives us the world dimensions in studs
local WorldConfig = require(ReplicatedStorage:WaitForChild("WorldConfig"))
local roblox      = WorldConfig.roblox or {}
local WORLD_W     = roblox.world_width_studs  or 2048
local WORLD_D     = roblox.world_depth_studs  or 2048
local ORIG_X      = roblox.terrain_x_origin   or -1024   -- world min X in studs
local ORIG_Z      = roblox.terrain_z_origin   or -1024   -- world min Z in studs

-- ── UI construction ───────────────────────────────────────────────────────────
local MAP_SIZE   = 220   -- pixels
local DOT_SIZE   = 10

local screenGui = Instance.new("ScreenGui")
screenGui.Name          = "MinimapGui"
screenGui.ResetOnSpawn  = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent        = player.PlayerGui

local mapFrame = Instance.new("Frame")
mapFrame.Name            = "MapFrame"
mapFrame.Size            = UDim2.new(0, MAP_SIZE, 0, MAP_SIZE)
mapFrame.Position        = UDim2.new(1, -(MAP_SIZE + 16), 0, 16)
mapFrame.AnchorPoint     = Vector2.new(0, 0)
mapFrame.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
mapFrame.BackgroundTransparency = 0.25
mapFrame.BorderSizePixel  = 0
mapFrame.ClipsDescendants = true
mapFrame.Parent          = screenGui

-- Rounded corners
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = mapFrame

-- Border stroke
local stroke = Instance.new("UIStroke")
stroke.Color     = Color3.fromRGB(80, 160, 220)
stroke.Thickness = 1.5
stroke.Parent    = mapFrame

-- Map image (replace rbxassetid with your uploaded colormap asset ID)
-- After uploading colormap.png via Roblox → Creator Hub → Images,
-- replace the number below with your asset ID.
local mapImage = Instance.new("ImageLabel")
mapImage.Size              = UDim2.new(1, 0, 1, 0)
mapImage.Position          = UDim2.new(0, 0, 0, 0)
mapImage.BackgroundTransparency = 1
mapImage.Image             = "rbxassetid://0"  -- TODO: set after uploading colormap.png
mapImage.ImageTransparency = 0
mapImage.ScaleType         = Enum.ScaleType.Stretch
mapImage.Parent            = mapFrame

-- Player dot
local playerDot = Instance.new("Frame")
playerDot.Name            = "PlayerDot"
playerDot.Size            = UDim2.new(0, DOT_SIZE, 0, DOT_SIZE)
playerDot.AnchorPoint     = Vector2.new(0.5, 0.5)
playerDot.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
playerDot.BorderSizePixel  = 0
playerDot.ZIndex           = 5
playerDot.Parent           = mapFrame

local dotCorner = Instance.new("UICorner")
dotCorner.CornerRadius = UDim.new(1, 0)
dotCorner.Parent = playerDot

-- Heading arrow inside dot
local arrow = Instance.new("TextLabel")
arrow.Size             = UDim2.new(1, 0, 1, 0)
arrow.BackgroundTransparency = 1
arrow.Text             = "▲"
arrow.TextColor3       = Color3.new(1, 1, 1)
arrow.Font             = Enum.Font.GothamBold
arrow.TextScaled       = true
arrow.ZIndex           = 6
arrow.Parent           = playerDot

-- Coordinates display
local coordLabel = Instance.new("TextLabel")
coordLabel.Size              = UDim2.new(1, 0, 0, 18)
coordLabel.Position          = UDim2.new(0, 0, 1, 2)
coordLabel.BackgroundTransparency = 1
coordLabel.TextColor3        = Color3.fromRGB(180, 220, 255)
coordLabel.Font               = Enum.Font.Code
coordLabel.TextSize           = 11
coordLabel.Text               = "(0, 0)"
coordLabel.Parent             = mapFrame

-- Toggle label
local toggleLabel = Instance.new("TextLabel")
toggleLabel.Size              = UDim2.new(0, MAP_SIZE, 0, 14)
toggleLabel.Position          = UDim2.new(1, -(MAP_SIZE + 16), 0, MAP_SIZE + 34)
toggleLabel.BackgroundTransparency = 1
toggleLabel.TextColor3        = Color3.fromRGB(120, 120, 120)
toggleLabel.Font               = Enum.Font.Code
toggleLabel.TextSize           = 11
toggleLabel.Text               = "[M] toggle minimap"
toggleLabel.Parent             = screenGui

-- ── Toggle minimap ────────────────────────────────────────────────────────────
local minimapVisible = true

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.M then
        minimapVisible = not minimapVisible
        mapFrame.Visible = minimapVisible
        coordLabel.Visible = minimapVisible
    end
end)

-- ── Update loop ───────────────────────────────────────────────────────────────
local function worldToMinimap(worldX, worldZ)
    -- Map world studs → 0..1
    local nx = (worldX - ORIG_X) / WORLD_W
    local nz = (worldZ - ORIG_Z) / WORLD_D
    -- Clamp
    nx = math.clamp(nx, 0, 1)
    nz = math.clamp(nz, 0, 1)
    -- UDim2 position (px inside MAP_SIZE frame)
    return UDim2.new(0, nx * MAP_SIZE, 0, nz * MAP_SIZE)
end

RunService.RenderStepped:Connect(function()
    if not minimapVisible then return end
    local character = player.Character
    if not character then return end
    local root = character:FindFirstChild("HumanoidRootPart")
    if not root then return end

    local pos = root.Position
    playerDot.Position = worldToMinimap(pos.X, pos.Z)

    -- Rotate arrow to match camera heading
    local camCF     = camera.CFrame
    local lookFlat  = Vector3.new(camCF.LookVector.X, 0, camCF.LookVector.Z)
    local angle     = math.deg(math.atan2(lookFlat.X, -lookFlat.Z))
    arrow.Rotation  = angle

    coordLabel.Text = string.format("(%.0f, %.0f)", pos.X, pos.Z)
end)

-- ── Click on minimap → teleport ───────────────────────────────────────────────
mapFrame.InputBegan:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end

    local relX = input.Position.X - mapFrame.AbsolutePosition.X
    local relY = input.Position.Y - mapFrame.AbsolutePosition.Y

    local nx = math.clamp(relX / MAP_SIZE, 0, 1)
    local nz = math.clamp(relY / MAP_SIZE, 0, 1)

    local worldX = ORIG_X + nx * WORLD_W
    local worldZ = ORIG_Z + nz * WORLD_D

    -- Raycast to find terrain height at target
    local rayOrigin = Vector3.new(worldX, 2000, worldZ)
    local rayDir    = Vector3.new(0, -4000, 0)
    local params    = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances = {workspace.Terrain}
    local result = workspace:Raycast(rayOrigin, rayDir, params)
    local worldY = result and result.Position.Y + 8 or 30

    local character = player.Character
    if not character then return end
    local root = character:FindFirstChild("HumanoidRootPart")
    if not root then return end

    local targetCF = CFrame.new(worldX, worldY, worldZ)
    local tween = TweenService:Create(root, TweenInfo.new(0.5), {CFrame = targetCF})
    tween:Play()
end)

print("[Minimap] Loaded ✓  M=toggle, click map=teleport")

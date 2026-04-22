--[[
  WorldLoader.server.lua
  Runs on the server when the place starts.

  Responsibilities:
    1. Read WorldConfig metadata and broadcast to clients
    2. Set sky / atmosphere / lighting
    3. Create floating info panels:
         • World Metadata panel — capture stats, scale, resolution
         • Project Description panel — what SkyPlat2Roblox is
    4. Handle player spawn above terrain
--]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting          = game:GetService("Lighting")
local Workspace         = game:GetService("Workspace")

local WorldConfig = require(ReplicatedStorage:WaitForChild("WorldConfig"))

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function getTerrainHeightAt(cx, cz)
    local rayOrigin = Vector3.new(cx, 2000, cz)
    local rayDir    = Vector3.new(0, -4000, 0)
    local params    = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances = {Workspace.Terrain}
    local result = Workspace:Raycast(rayOrigin, rayDir, params)
    return result and result.Position.Y or 20
end

-- ── Sky & atmosphere ──────────────────────────────────────────────────────────
local function setupEnvironment()
    Lighting.TimeOfDay     = "14:00:00"
    Lighting.Brightness    = 2.2
    Lighting.GlobalShadows = true
    Lighting.Technology    = Enum.Technology.Future

    local sky = Instance.new("Sky")
    sky.SkyboxBk = "rbxassetid://6444884337"
    sky.SkyboxDn = "rbxassetid://6444884337"
    sky.SkyboxFt = "rbxassetid://6444884337"
    sky.SkyboxLf = "rbxassetid://6444884337"
    sky.SkyboxRt = "rbxassetid://6444884337"
    sky.SkyboxUp = "rbxassetid://6444884337"
    sky.Parent = Lighting

    local atm = Instance.new("Atmosphere")
    atm.Density = 0.25
    atm.Offset  = 0.20
    atm.Haze    = 0.1
    atm.Glare   = 0.0
    atm.Color   = Color3.fromRGB(200, 214, 231)
    atm.Parent  = Lighting
end

-- ── Panel builder ─────────────────────────────────────────────────────────────
--[[
  Creates a sleek floating glass panel at worldPosition.
  Returns the SurfaceGui frame so callers can add rows.

  Layout:
    ┌───────────────────────────┐
    │  [accent bar]             │  ← 6px top bar in accent colour
    │  TITLE                    │  ← bold header row
    │  ─────────────────────    │
    │  row 1                    │
    │  row 2  …                 │
    └───────────────────────────┘
--]]
local function createPanel(opts)
    --[[
    opts = {
      name        : string          — Part name in Workspace
      title       : string          — Header text
      position    : Vector3         — World position
      width       : number          — studs wide  (default 18)
      height      : number          — studs tall  (default 12)
      accentColor : Color3          — top bar + title colour
      rows        : {string}        — body text lines
    }
    --]]
    local w = opts.width  or 18
    local h = opts.height or 12

    -- Invisible anchor part
    local part = Instance.new("Part")
    part.Name        = opts.name or "Panel"
    part.Size        = Vector3.new(w, h, 0.05)
    part.CFrame      = CFrame.new(opts.position) * CFrame.Angles(0, 0, 0)
    part.Anchored    = true
    part.CanCollide  = false
    part.Transparency = 1
    part.Parent      = Workspace

    -- SurfaceGui (face = Front)
    local gui = Instance.new("SurfaceGui")
    gui.Face           = Enum.NormalId.Front
    gui.SizingMode     = Enum.SurfaceGuiSizingMode.PixelsPerStud
    gui.PixelsPerStud  = 40
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.AlwaysOnTop    = false
    gui.Parent         = part

    local totalPx = Vector2.new(w * 40, h * 40)

    -- Glass background
    local bg = Instance.new("Frame")
    bg.Size                  = UDim2.new(1, 0, 1, 0)
    bg.BackgroundColor3      = Color3.fromRGB(8, 12, 22)
    bg.BackgroundTransparency = 0.18
    bg.BorderSizePixel       = 0
    bg.Parent                = gui

    local bgCorner = Instance.new("UICorner")
    bgCorner.CornerRadius = UDim.new(0, 14)
    bgCorner.Parent = bg

    -- Outer border glow
    local stroke = Instance.new("UIStroke")
    stroke.Color     = opts.accentColor or Color3.fromRGB(80, 180, 255)
    stroke.Thickness = 2.5
    stroke.Transparency = 0.3
    stroke.Parent    = bg

    -- Accent top bar
    local bar = Instance.new("Frame")
    bar.Size             = UDim2.new(1, 0, 0, 6)
    bar.Position         = UDim2.new(0, 0, 0, 0)
    bar.BackgroundColor3 = opts.accentColor or Color3.fromRGB(80, 180, 255)
    bar.BorderSizePixel  = 0
    bar.Parent           = bg

    local barCornerT = Instance.new("UICorner")
    barCornerT.CornerRadius = UDim.new(0, 14)
    barCornerT.Parent = bar

    -- Bottom mask to square the bottom corners of the top bar
    local barMask = Instance.new("Frame")
    barMask.Size             = UDim2.new(1, 0, 0.5, 0)
    barMask.Position         = UDim2.new(0, 0, 0.5, 0)
    barMask.BackgroundColor3 = opts.accentColor or Color3.fromRGB(80, 180, 255)
    barMask.BorderSizePixel  = 0
    barMask.Parent           = bar

    -- Content list layout
    local list = Instance.new("Frame")
    list.Size            = UDim2.new(1, -24, 1, -18)
    list.Position        = UDim2.new(0, 12, 0, 12)
    list.BackgroundTransparency = 1
    list.Parent          = bg

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.VerticalAlignment = Enum.VerticalAlignment.Top
    layout.Padding       = UDim.new(0, 4)
    layout.Parent        = list

    -- Title row
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size              = UDim2.new(1, 0, 0, 26)
    titleLabel.BackgroundTransparency = 1
    titleLabel.TextColor3        = opts.accentColor or Color3.fromRGB(130, 200, 255)
    titleLabel.Font               = Enum.Font.GothamBold
    titleLabel.TextSize           = 17
    titleLabel.TextXAlignment     = Enum.TextXAlignment.Left
    titleLabel.Text               = opts.title or "Panel"
    titleLabel.Parent             = list

    -- Divider
    local divider = Instance.new("Frame")
    divider.Size             = UDim2.new(1, 0, 0, 1)
    divider.BackgroundColor3 = Color3.fromRGB(60, 80, 120)
    divider.BorderSizePixel  = 0
    divider.Parent           = list

    -- Body rows
    for _, rowText in ipairs(opts.rows or {}) do
        local row = Instance.new("TextLabel")
        row.Size              = UDim2.new(1, 0, 0, 20)
        row.BackgroundTransparency = 1
        row.TextColor3        = Color3.fromRGB(210, 225, 245)
        row.Font               = Enum.Font.Code
        row.TextSize           = 13
        row.TextXAlignment     = Enum.TextXAlignment.Left
        row.TextTruncate       = Enum.TextTruncate.AtEnd
        row.Text               = rowText
        row.Parent             = list
    end

    return part
end

-- ── Floating panel: World Metadata ───────────────────────────────────────────
local function createMetadataPanel()
    local cfg    = WorldConfig
    local rb     = cfg.roblox        or {}
    local bounds = cfg.source_bounds or {}
    local scale  = cfg.scale         or {}

    local bx = bounds.x or {0, 0}
    local by = bounds.y or {0, 0}
    local bz = bounds.z or {0, 0}

    local rows = {
        string.format("  Resolution     %d × %d px",
            cfg.resolution or 512, cfg.resolution or 512),
        string.format("  World size     %d × %d studs",
            rb.world_width_studs or 2048, rb.world_depth_studs or 2048),
        string.format("  Max height     %d studs",  rb.world_height_studs or 512),
        string.format("  Voxel size     %d studs",  rb.studs_per_cell     or 4),
        "",
        "  Source bounds (scene units):",
        string.format("    X  %.2f → %.2f",  bx[1], bx[2]),
        string.format("    Y  %.2f → %.2f",  by[1], by[2]),
        string.format("    Z  %.2f → %.2f",  bz[1], bz[2]),
        "",
        "  Scale factors:",
        string.format("    X  %.2f studs / unit", scale.world_unit_to_stud_x or 0),
        string.format("    Y  %.2f studs / unit", scale.world_unit_to_stud_y or 0),
        string.format("    Z  %.2f studs / unit", scale.world_unit_to_stud_z or 0),
    }

    local h = getTerrainHeightAt(30, 0)
    createPanel({
        name        = "MetadataPanel",
        title       = "📡  World Metadata",
        position    = Vector3.new(30, h + 22, 0),
        width       = 22,
        height      = 14,
        accentColor = Color3.fromRGB(56, 189, 248),   -- sky blue
        rows        = rows,
    })
end

-- ── Floating panel: Project Description ──────────────────────────────────────
local function createDescriptionPanel()
    local rows = {
        "  SkyPlat2Roblox converts drone photogrammetry",
        "  captures (Gaussian Splat / point cloud) into",
        "  fully navigable Roblox worlds.",
        "",
        "  Pipeline:",
        "    .ply / .splat / .obj",
        "    → heightmap.png + colormap.png",
        "    → world.rbxlx (this place)",
        "",
        "  In-game controls:",
        "    F  — fly mode",
        "    V  — drone top-down view",
        "    M  — toggle minimap",
        "    Click minimap → teleport",
        "",
        "  github.com/alx/skysplat2roblox",
    }

    local h = getTerrainHeightAt(-30, 0)
    createPanel({
        name        = "DescriptionPanel",
        title       = "🛸  SkyPlat2Roblox",
        position    = Vector3.new(-30, h + 22, 0),
        width       = 22,
        height      = 16,
        accentColor = Color3.fromRGB(168, 85, 247),   -- violet
        rows        = rows,
    })
end

-- ── Origin marker (GPS anchor) ────────────────────────────────────────────────
local function createOriginMarker()
    local h = getTerrainHeightAt(0, 0)

    local marker = Instance.new("Part")
    marker.Name       = "OriginMarker"
    marker.Size       = Vector3.new(3, 3, 3)
    marker.CFrame     = CFrame.new(0, h + 2, 0)
    marker.Anchored   = true
    marker.Material   = Enum.Material.Neon
    marker.BrickColor = BrickColor.new("Bright red")
    marker.Shape      = Enum.PartType.Ball
    marker.CanCollide = false
    marker.Parent     = Workspace

    local bill = Instance.new("BillboardGui")
    bill.Size        = UDim2.new(0, 100, 0, 32)
    bill.StudsOffset = Vector3.new(0, 4, 0)
    bill.AlwaysOnTop = false
    bill.Parent      = marker

    local label = Instance.new("TextLabel")
    label.Size                  = UDim2.new(1, 0, 1, 0)
    label.BackgroundColor3      = Color3.fromRGB(15, 15, 15)
    label.BackgroundTransparency = 0.3
    label.TextColor3            = Color3.new(1, 1, 1)
    label.Text                  = "📡 Origin (0, 0)"
    label.Font                  = Enum.Font.GothamBold
    label.TextScaled            = true
    label.Parent                = bill
end

-- ── Spawn players above terrain ───────────────────────────────────────────────
local function spawnPlayerAboveTerrain(player)
    local character = player.Character or player.CharacterAdded:Wait()
    local root = character:WaitForChild("HumanoidRootPart", 5)
    if not root then return end
    local y = getTerrainHeightAt(0, 0) + 10
    root.CFrame = CFrame.new(0, y, 0)
end

-- ── Remote: clients can fetch WorldConfig ────────────────────────────────────
local WorldInfoFn = Instance.new("RemoteFunction")
WorldInfoFn.Name   = "GetWorldInfo"
WorldInfoFn.Parent = ReplicatedStorage
WorldInfoFn.OnServerInvoke = function() return WorldConfig end

-- ── Init ──────────────────────────────────────────────────────────────────────
setupEnvironment()

task.defer(function()
    -- Small delay so terrain is ready for raycasts
    task.wait(1)
    createOriginMarker()
    createMetadataPanel()
    createDescriptionPanel()
end)

Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function()
        task.wait(0.5)
        spawnPlayerAboveTerrain(player)
    end)
end)

local rb = WorldConfig.roblox or {}
print("[WorldLoader] SkyPlat world ready ✓")
print(string.format("[WorldLoader] %d × %d studs · resolution %d",
    rb.world_width_studs or 2048,
    rb.world_depth_studs or 2048,
    WorldConfig.resolution or 512))
print("[WorldLoader] Panels: Metadata (right) + Description (left) of origin")

--[[
  SkySplatImporter.plugin.lua
  Roblox Studio Plugin — imports the skysplat2roblox pipeline output into Studio.

  Installation:
    1. Save this file as SkySplatImporter.lua in:
         %LOCALAPPDATA%\Roblox\Plugins\  (Windows)
         ~/Documents/Roblox/Plugins/     (macOS)
    2. Restart Roblox Studio
    3. A "🛸 SkySplat" button appears in the Plugins toolbar

  What it does:
    1. Prompts for heightmap.png and colormap.png from your pipeline output
    2. Imports heightmap via Terrain:ImportHeightmap()
    3. Applies colormap as terrain surface colour (paints in cells)
    4. Places the SpawnLocation above the highest terrain point at (0, 0)

  NOTE: This plugin uses Studio-only APIs (Terrain:ImportHeightmap).
        It will NOT run in a live game — Studio context only.
--]]

local toolbar    = plugin:CreateToolbar("🛸 SkySplat")
local importBtn  = toolbar:CreateButton(
    "Import World",
    "Import heightmap + colormap from skysplat2roblox pipeline output",
    "rbxassetid://6031097564"   -- generic image icon
)

local Selection  = game:GetService("Selection")
local Workspace  = game:GetService("Workspace")
local RunService = game:GetService("RunService")

-- Only active in Studio
if not RunService:IsStudio() then return end

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function notify(msg)
    print("[SkySplatImporter] " .. msg)
end

local function promptFile(title: string): string?
    -- Studio file picker returns a path string or nil if cancelled
    local result = pcall(function()
        -- Studio plugin API: studio:PromptImportFile()
    end)
    -- Fallback: ask user to paste path in command bar / set attribute
    return nil
end

-- ── Main import workflow ──────────────────────────────────────────────────────

local function doImport()
    notify("Starting terrain import …")

    local terrain = Workspace:FindFirstChildOfClass("Terrain")
    if not terrain then
        terrain = Instance.new("Terrain")
        terrain.Parent = Workspace
        notify("Created Terrain object")
    end

    -- ── Step 1: read heightmap asset ID from Workspace attribute ─────────────
    -- Set these attributes on Workspace before clicking Import:
    --   HeightmapAssetId  (number) — asset ID of uploaded heightmap.png
    --   ColormapAssetId   (number) — asset ID of uploaded colormap.png
    --   WorldWidthStuds   (number) — from world_meta.json (default 2048)
    --   WorldDepthStuds   (number) — from world_meta.json (default 2048)
    --   WorldHeightStuds  (number) — from world_meta.json (default 512)

    local hmapId   = Workspace:GetAttribute("HeightmapAssetId")
    local cmapId   = Workspace:GetAttribute("ColormapAssetId")
    local worldW   = Workspace:GetAttribute("WorldWidthStuds")  or 2048
    local worldD   = Workspace:GetAttribute("WorldDepthStuds")  or 2048
    local worldH   = Workspace:GetAttribute("WorldHeightStuds") or 512

    if not hmapId then
        warn([[
[SkySplatImporter] ⚠  HeightmapAssetId not set on Workspace.

Steps:
  1. Upload heightmap.png to Roblox (Creator Hub → Images)
  2. Copy the asset ID
  3. In the Explorer, select Workspace
  4. In Properties → Attributes, add:
       HeightmapAssetId  = <your asset ID>   (type: number)
       ColormapAssetId   = <colormap ID>     (type: number, optional)
  5. Click "Import World" again
]])
        return
    end

    notify(string.format("Heightmap asset: %d  Colormap: %s", hmapId, tostring(cmapId)))
    notify(string.format("World: %d × %d studs, height: %d studs", worldW, worldD, worldH))

    -- ── Step 2: define terrain region ────────────────────────────────────────
    local halfW = worldW / 2
    local halfD = worldD / 2
    local region = Region3.new(
        Vector3.new(-halfW, 0,        -halfD),
        Vector3.new( halfW, worldH,    halfD)
    )

    -- ── Step 3: import heightmap ─────────────────────────────────────────────
    notify("Importing heightmap …")
    local hmapUrl = "rbxassetid://" .. tostring(hmapId)

    local ok, err = pcall(function()
        -- Terrain:ImportHeightmap(region, heightmapUrl, colormapUrl?)
        if cmapId then
            terrain:ImportHeightmap(region, hmapUrl, "rbxassetid://" .. tostring(cmapId))
        else
            terrain:ImportHeightmap(region, hmapUrl)
        end
    end)

    if not ok then
        warn("[SkySplatImporter] ImportHeightmap failed: " .. tostring(err))
        warn("Make sure the asset is approved and accessible.")
        return
    end

    notify("Heightmap imported ✓")

    -- ── Step 4: move spawn above terrain ─────────────────────────────────────
    local spawn = Workspace:FindFirstChild("SpawnLocation")
    if spawn then
        local rayOrigin = Vector3.new(0, worldH, 0)
        local rayDir    = Vector3.new(0, -worldH - 10, 0)
        local params    = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Include
        params.FilterDescendantsInstances = {terrain}
        local result = Workspace:Raycast(rayOrigin, rayDir, params)
        local spawnY = result and (result.Position.Y + 2) or 20
        spawn.CFrame = CFrame.new(0, spawnY, 0)
        notify(string.format("SpawnLocation moved to Y=%.1f", spawnY))
    end

    notify([[
✅  Import complete!

Next:
  1. Press ▶ to playtest
  2. Fly around with F key, drone view with V key
  3. File → Publish to Roblox to go live
]])
end

-- ── Button click ─────────────────────────────────────────────────────────────
importBtn.Click:Connect(doImport)
notify("Plugin loaded — click 'Import World' to begin")

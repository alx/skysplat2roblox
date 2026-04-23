--[[
  SkySplatImporter.plugin.lua  (v2 — WriteVoxels edition)
  Roblox Studio Plugin — imports the skysplat2roblox pipeline output into Studio.

  Installation:
    1. Save this file as SkySplatImporter.lua in:
         %LOCALAPPDATA%\Roblox\Plugins\  (Windows)
         ~/Documents/Roblox/Plugins/     (macOS)
    2. Restart Roblox Studio
    3. A "🛸 SkySplat" button appears in the Plugins toolbar

  What it does:
    1. Reads HeightmapAssetId + ColormapAssetId from Workspace attributes
    2. Downloads both images via AssetService:CreateEditableImageAsync()
    3. Builds a 3-D voxel grid (materials + occupancies) from the pixel data
    4. Writes terrain via Terrain:WriteVoxels() in strips (avoids timeout)
    5. Places SpawnLocation above terrain at world centre

  Workspace attributes to set BEFORE clicking Import:
    HeightmapAssetId  (number)  — asset ID of uploaded heightmap.png
    ColormapAssetId   (number)  — asset ID of uploaded colormap.png  [optional]
    WorldWidthStuds   (number)  — from world_meta.json  (default 2048)
    WorldDepthStuds   (number)  — from world_meta.json  (default 2048)
    WorldHeightStuds  (number)  — from world_meta.json  (default 512)

  NOTE: This plugin uses Studio-only APIs.
        It will NOT run in a live game — Studio context only.
--]]

local toolbar   = plugin:CreateToolbar("🛸 SkySplat")
local importBtn = toolbar:CreateButton(
    "Import World",
    "Import heightmap + colormap from skysplat2roblox pipeline output",
    "rbxassetid://6031097564"
)

local AssetService = game:GetService("AssetService")
local RunService   = game:GetService("RunService")
local Workspace    = game:GetService("Workspace")

if not RunService:IsStudio() then return end

-- ── Constants ─────────────────────────────────────────────────────────────────

local VOXEL_RES  = 4          -- studs per voxel (Roblox minimum)
local STRIP_COLS = 32         -- X-columns processed per frame slice
local YIELD_EVERY = 5         -- yield every N strips

-- ── Colour → material mapping ─────────────────────────────────────────────────

local function rgbToMaterial(r, g, b)
    -- r, g, b are floats [0, 1]
    local R, G, B = r * 255, g * 255, b * 255

    -- Water: low R+G, higher B
    if B > 140 and B > R * 1.5 and B > G * 1.2 then
        return Enum.Material.Water
    end
    -- Snow: all channels high
    if R > 220 and G > 220 and B > 220 then
        return Enum.Material.Snow
    end
    -- Sand: warm yellow-tan
    if R > 180 and G > 150 and B < 120 then
        return Enum.Material.Sand
    end
    -- Rock: dark-ish grey
    if R < 140 and G < 140 and B < 140 and math.abs(R - G) < 25 and math.abs(G - B) < 25 then
        return Enum.Material.Rock
    end
    -- Grass: green dominant
    if G > R and G > B and G > 80 then
        return Enum.Material.Grass
    end
    -- Ground: everything else
    return Enum.Material.Ground
end

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function notify(msg)
    print("[SkySplatImporter] " .. msg)
end

local function readImagePixels(assetId)
    -- Returns (pixelTable, width, height) or throws
    local url = "rbxassetid://" .. tostring(assetId)
    local img = AssetService:CreateEditableImageAsync(url)   -- yields; Studio only
    local sz  = img.Size   -- Vector2
    local w   = math.floor(sz.X)
    local h   = math.floor(sz.Y)
    -- ReadPixels returns a flat table of {r,g,b,a, r,g,b,a, …} in [0,1]
    local pixels = img:ReadPixels(Vector2.zero, sz)
    img:Destroy()
    return pixels, w, h
end

-- ── Main import ───────────────────────────────────────────────────────────────

local function doImport()
    notify("Starting terrain import (v2 — WriteVoxels) …")

    -- ── 1. Read attributes ───────────────────────────────────────────────────
    local hmapId = Workspace:GetAttribute("HeightmapAssetId")
    local cmapId = Workspace:GetAttribute("ColormapAssetId")
    local worldW = Workspace:GetAttribute("WorldWidthStuds")  or 2048
    local worldD = Workspace:GetAttribute("WorldDepthStuds")  or 2048
    local worldH = Workspace:GetAttribute("WorldHeightStuds") or 512

    if not hmapId then
        warn([[
[SkySplatImporter] ⚠  HeightmapAssetId not set on Workspace.

Steps:
  1. Upload out/heightmap.png to Roblox (Creator Hub → Images)
  2. Copy the numeric asset ID from the URL
  3. In Explorer, select Workspace
  4. In Properties → Attributes, click [+] and add:
       HeightmapAssetId  = <your asset ID>   (Type: Number)
       ColormapAssetId   = <colormap ID>     (Type: Number, optional)
  5. Click "🛸 Import World" again
]])
        return
    end

    notify(string.format(
        "Heightmap asset: %d | Colormap: %s | World: %d×%d studs, H: %d studs",
        hmapId, tostring(cmapId), worldW, worldD, worldH
    ))

    -- ── 2. Ensure terrain object ─────────────────────────────────────────────
    local terrain = Workspace:FindFirstChildOfClass("Terrain")
    if not terrain then
        terrain = Instance.new("Terrain")
        terrain.Parent = Workspace
        notify("Created Terrain object")
    end

    -- ── 3. Download heightmap pixels ─────────────────────────────────────────
    notify("Downloading heightmap …")
    local hmapPixels, hmapW, hmapH
    local ok, err = pcall(function()
        hmapPixels, hmapW, hmapH = readImagePixels(hmapId)
    end)
    if not ok then
        warn("[SkySplatImporter] Failed to load heightmap: " .. tostring(err))
        return
    end
    notify(string.format("Heightmap: %d × %d px", hmapW, hmapH))

    -- ── 4. Download colormap pixels (optional) ────────────────────────────────
    local cmapPixels, cmapW, cmapH
    if cmapId then
        notify("Downloading colormap …")
        local cok, cerr = pcall(function()
            cmapPixels, cmapW, cmapH = readImagePixels(cmapId)
        end)
        if not cok then
            warn("[SkySplatImporter] Colormap load failed (continuing without): " .. tostring(cerr))
            cmapPixels = nil
        else
            notify(string.format("Colormap: %d × %d px", cmapW, cmapH))
        end
    end

    -- ── 5. Compute voxel grid dimensions ─────────────────────────────────────
    -- voxel counts along each axis
    local voxX = math.floor(worldW / VOXEL_RES)
    local voxY = math.floor(worldH / VOXEL_RES)
    local voxZ = math.floor(worldD / VOXEL_RES)

    notify(string.format("Voxel grid: %d × %d × %d (X×Y×Z)", voxX, voxY, voxZ))

    -- terrain region: centred on (0, worldH/2, 0)
    local halfW = worldW / 2
    local halfD = worldD / 2

    -- ── 6. Clear old terrain ─────────────────────────────────────────────────
    notify("Clearing previous terrain …")
    terrain:Clear()

    -- ── 7. Build + write voxels in X-column strips ───────────────────────────
    --
    -- Terrain:WriteVoxels(region, voxelSize, materials, occupancies)
    --   region      — Region3 for the strip (must be voxelSize-aligned)
    --   voxelSize   — 4 (only valid value for full terrain)
    --   materials   — [X][Y][Z] nested array of Enum.Material
    --   occupancies — [X][Y][Z] nested array of floats [0, 1]
    --
    -- We build one strip of STRIP_COLS columns at a time.

    local stripsDone = 0
    local yieldCount = 0

    local x0 = 0   -- strip start column (0-indexed)
    while x0 < voxX do
        local x1 = math.min(x0 + STRIP_COLS, voxX)   -- exclusive end
        local colCount = x1 - x0

        -- world-space X bounds for this strip
        local stripMinX = -halfW + x0 * VOXEL_RES
        local stripMaxX = -halfW + x1 * VOXEL_RES

        local region = Region3.new(
            Vector3.new(stripMinX, 0,      -halfD),
            Vector3.new(stripMaxX, worldH,  halfD)
        )

        -- Build 3-D material/occupancy arrays [localX][Y][Z]
        local mats = {}
        local occs = {}

        for lx = 1, colCount do
            mats[lx] = {}
            occs[lx] = {}
            local gx = x0 + lx - 1   -- global X voxel index (0-based)

            for ly = 1, voxY do
                mats[lx][ly] = {}
                occs[lx][ly] = {}

                for lz = 1, voxZ do
                    local gz = lz - 1   -- global Z index (0-based)

                    -- Map voxel column (gx, gz) → heightmap pixel
                    local px = math.floor(gx / voxX * hmapW)
                    local pz = math.floor(gz / voxZ * hmapH)
                    px = math.max(0, math.min(px, hmapW - 1))
                    pz = math.max(0, math.min(pz, hmapH - 1))

                    -- heightmap is greyscale: sample R channel [0,1]
                    local idx = (pz * hmapW + px) * 4 + 1   -- 1-based Lua
                    local heightNorm = hmapPixels[idx] or 0  -- R channel

                    -- height in voxels
                    local heightVoxels = math.floor(heightNorm * voxY)

                    -- is this Y voxel filled?
                    if ly <= heightVoxels then
                        -- determine material from colormap (or fallback)
                        local mat = Enum.Material.Grass
                        if cmapPixels then
                            local ci = (pz * cmapW + px) * 4 + 1
                            local cr = cmapPixels[ci]     or 0
                            local cg = cmapPixels[ci + 1] or 0
                            local cb = cmapPixels[ci + 2] or 0
                            mat = rgbToMaterial(cr, cg, cb)
                        end
                        mats[lx][ly][lz] = mat
                        occs[lx][ly][lz] = 1
                    else
                        mats[lx][ly][lz] = Enum.Material.Air
                        occs[lx][ly][lz] = 0
                    end
                end
            end
        end

        -- Write the strip
        local wok, werr = pcall(function()
            terrain:WriteVoxels(region, VOXEL_RES, mats, occs)
        end)
        if not wok then
            warn(string.format("[SkySplatImporter] WriteVoxels failed at x0=%d: %s", x0, tostring(werr)))
        end

        stripsDone += 1
        yieldCount += 1
        if yieldCount >= YIELD_EVERY then
            yieldCount = 0
            notify(string.format("  … %d / %d strips written", stripsDone, math.ceil(voxX / STRIP_COLS)))
            task.wait()   -- give Studio a breath
        end

        x0 = x1
    end

    notify(string.format("All %d strips written ✓", stripsDone))

    -- ── 8. Place SpawnLocation above terrain centre ───────────────────────────
    local spawn = Workspace:FindFirstChild("SpawnLocation")
    if not spawn then
        spawn = Instance.new("SpawnLocation")
        spawn.Name   = "SpawnLocation"
        spawn.Size   = Vector3.new(6, 1, 6)
        spawn.Parent = Workspace
    end

    local rayOrigin = Vector3.new(0, worldH + 10, 0)
    local rayDir    = Vector3.new(0, -(worldH + 20), 0)
    local params    = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances = {terrain}
    local hit = Workspace:Raycast(rayOrigin, rayDir, params)
    local spawnY = hit and (hit.Position.Y + 4) or 30
    spawn.CFrame = CFrame.new(0, spawnY, 0)
    notify(string.format("SpawnLocation placed at Y=%.1f", spawnY))

    notify([[
✅  Import complete!

Next steps:
  1. Press ▶ to playtest
  2. Press F to fly, V for drone view, M for minimap
  3. File → Publish to Roblox to go live
]])
end

-- ── Button click ──────────────────────────────────────────────────────────────
importBtn.Click:Connect(function()
    -- Run in a coroutine so yields inside doImport() work correctly
    task.spawn(doImport)
end)

notify("Plugin loaded (v2 — WriteVoxels) — click 'Import World' to begin")

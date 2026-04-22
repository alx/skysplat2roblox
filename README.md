# skysplat2roblox

Convert a **Gaussian Splat / drone photogrammetry capture** into a fully navigable **Roblox world** that players can explore on foot, sprint, fly, and navigate via minimap.

```
.ply / .splat / .obj
       ↓  pipeline/
heightmap.png + colormap.png + world.rbxlx
       ↓  Roblox Studio + SkySplat plugin
Roblox terrain (voxels) + nav scripts
       ↓  Publish
roblox.com/games/YOUR_PLACE_ID
```

---

## What you get in-game

| Feature | Key |
|---------|-----|
| Walk | WASD |
| Sprint | Shift |
| **Fly mode** | **F** |
| Fly up/down | Space / Ctrl |
| **Drone top-down view** | **V** |
| Scroll drone height | Mouse wheel |
| **Minimap** | top-right corner |
| Toggle minimap | **M** |
| **Click minimap** → teleport | mouse click |

---

## Quick start

### 1 · Install Python dependencies

```bash
pip install -r requirements.txt
```

### 2 · Run the pipeline

```bash
# With your drone capture:
python -m pipeline scene.ply --out ./out --resolution 512

# Or try the built-in demo (synthetic landscape, no file needed):
python -m pipeline --demo
```

**Output in `./out/`:**

| File | Purpose |
|------|---------|
| `heightmap.png` | 16-bit grayscale height data (import into Roblox Studio) |
| `colormap.png` | RGB surface colours |
| `world_meta.json` | Scale + origin (read by in-game scripts) |
| `world.rbxlx` | Roblox place file with nav scripts embedded |

### 3 · Import into Roblox Studio

**Option A — Studio Plugin (recommended):**

1. Copy `studio_plugin/SkySplatImporter.plugin.lua` to your Roblox Plugins folder:
   - Windows: `%LOCALAPPDATA%\Roblox\Plugins\`
   - macOS: `~/Documents/Roblox/Plugins/`
2. Restart Studio → File → Open → `out/world.rbxlx`
3. Upload `out/heightmap.png` and `out/colormap.png` to Roblox (Creator Hub → Images)
4. In Explorer, select **Workspace** → Properties → Attributes → Add:
   - `HeightmapAssetId` = *your heightmap asset ID* (number)
   - `ColormapAssetId`  = *your colormap asset ID* (number)
5. Click **Plugins → 🛸 SkySplat → Import World**

**Option B — Studio built-in terrain importer:**

1. File → Open → `out/world.rbxlx`
2. Home → Editor → Terrain Editor → Import
3. Import `heightmap.png` as heightmap, `colormap.png` as colormap
4. Set region to match `world_meta.json` dimensions

### 4 · Playtest

Press ▶ in Studio. Try:
- **F** to fly above the terrain
- **V** for bird's-eye view
- Click the minimap to teleport to any point

### 5 · Publish to Roblox

**Via Studio:**
File → Publish to Roblox As… → choose your game

**Via CLI:**
```bash
cp .env.example .env
# Fill in ROBLOX_API_KEY, ROBLOX_UNIVERSE_ID, ROBLOX_PLACE_ID in .env

python publish/publish.py --place out/world.rbxlx
```

---

## Supported input formats

| Format | Description |
|--------|-------------|
| `.ply`   | Gaussian Splat training output (ascii + binary; SH DC coefficients + simple XYZRGB) |
| `.splat` | Compact viewer format (32 bytes/gaussian: position + scale + rgba + rotation) |
| `.obj`   | Wavefront mesh (vertices with optional per-vertex colour) |

---

## Pipeline internals

```
pipeline/
├── splat_reader.py     Parse .ply / .splat / .obj → N×7 numpy array (x y z r g b a)
├── heightmap.py        Point cloud → heightmap.png (16-bit) + colormap.png + world_meta.json
│                         • Grid the XZ plane at `resolution × resolution`
│                         • Per cell: max-Y point → height; its colour → colormap
│                         • Empty cells: filled by nearest-neighbour
│                         • Height normalised → 16-bit PNG [0, 65535]
├── rbxlx_builder.py    Assemble world.rbxlx XML (terrain placeholder + all Lua scripts)
└── cli.py              Entry point: python -m pipeline <input> [options]
```

### Resolution vs performance

| Resolution | Voxels | World size | File size | Notes |
|-----------|--------|------------|-----------|-------|
| 256 | 256×256 | 1024×1024 studs | ~0.2 MB | Fast; good for small scenes |
| 512 | 512×512 | 2048×2048 studs | ~0.8 MB | **Default; good for most drone maps** |
| 1024 | 1024×1024 | 4096×4096 studs | ~3 MB | Large captures; Studio may be slow |

---

## Roblox files

```
roblox/
├── default.project.json                              Rojo project file
└── src/
    ├── ServerScriptService/
    │   └── WorldLoader.server.lua      Sky, atmosphere, spawn above terrain, origin marker
    ├── StarterPlayer/StarterPlayerScripts/
    │   ├── Navigation.client.lua       Fly (F), sprint, drone view (V), speed HUD
    │   └── Minimap.client.lua          Top-right minimap, M toggle, click to teleport
    └── ReplicatedStorage/
        └── WorldConfig.lua             World dimensions + scale (ModuleScript)
```

---

## Publishing workflow

```
# One-shot: convert + place file + publish
python -m pipeline scene.ply --out ./out
python publish/publish.py --place ./out/world.rbxlx
```

Get your API key at **create.roblox.com/credentials** → API Keys
Required permission: `Universe → universe-places:write`

---

## Tests

```bash
python tests/test_pipeline.py
# or
pip install pytest && pytest tests/ -v
```

---

## Requirements

- Python ≥ 3.10
- `numpy`, `Pillow`, `scipy`, `requests`
- Roblox Studio (free) for terrain import + playtest
- Roblox account for publishing

---

## Roadmap

- [ ] Waypoint extraction from drone GPS telemetry (`.srt` / `.gpx` → in-game markers)
- [ ] LOD: auto-reduce resolution for large captures
- [ ] Roblox `.rbxl` binary format (smaller files)
- [ ] Auto-upload colormap via Open Cloud Assets API
- [ ] Web viewer (Three.js) as fallback for non-Roblox users

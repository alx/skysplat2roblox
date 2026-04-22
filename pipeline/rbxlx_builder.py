"""
rbxlx_builder.py — Generate a Roblox place file (.rbxlx)

The generated place includes:
  - Workspace with terrain placeholder + spawn + atmosphere
  - ServerScriptService with WorldLoader (reads world_meta.json)
  - StarterPlayerScripts with Navigation + Minimap
  - ReplicatedStorage with WorldConfig ModuleScript

The terrain itself is NOT embedded here (too large).
Use the Studio plugin (studio_plugin/SkySplatImporter.plugin.lua) to
import heightmap.png + colormap.png after loading this place.

Usage:
  meta = heightmap.save(points, "./out")
  rbxlx_builder.build("./out/world.rbxlx", meta)
"""

from __future__ import annotations
import json
from pathlib import Path

# ── Lua script bodies are in roblox/src/ — we embed them here as strings ─────
# (so the .rbxlx is self-contained; Studio plugin handles terrain import)


def _lua(path: Path) -> str:
    """Read a Lua file and escape for XML embedding."""
    try:
        return path.read_text(encoding="utf-8")
    except FileNotFoundError:
        return f"-- (script not found: {path})\n"


def build(out_path: str | Path, meta: dict, scripts_dir: str | Path | None = None) -> None:
    """Generate a self-contained .rbxlx Roblox place file."""
    out_path  = Path(out_path)
    scripts_dir = Path(scripts_dir) if scripts_dir else Path(__file__).parent.parent / "roblox" / "src"

    roblox = meta.get("roblox", {})
    world_w = roblox.get("world_width_studs",  2048)
    world_d = roblox.get("world_depth_studs",  2048)
    world_h = roblox.get("world_height_studs",  512)
    tx_orig = roblox.get("terrain_x_origin", -1024)
    tz_orig = roblox.get("terrain_z_origin", -1024)

    world_config_src = json.dumps(meta, indent=2)

    server_script  = _lua(scripts_dir / "ServerScriptService" / "WorldLoader.server.lua")
    nav_script     = _lua(scripts_dir / "StarterPlayer" / "StarterPlayerScripts" / "Navigation.client.lua")
    minimap_script = _lua(scripts_dir / "StarterPlayer" / "StarterPlayerScripts" / "Minimap.client.lua")
    worldcfg_src   = _lua(scripts_dir / "ReplicatedStorage" / "WorldConfig.lua")

    def esc(s: str) -> str:
        return (s.replace("&", "&amp;")
                  .replace("<", "&lt;")
                  .replace(">", "&gt;")
                  .replace('"', "&quot;"))

    xml = f"""<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">
  <External>null</External>
  <External>nil</External>
  <Item class="DataModel" referent="RBX0">
    <Properties>
      <string name="Name">SkyPlat World</string>
    </Properties>

    <!-- Workspace -->
    <Item class="Workspace" referent="RBX1">
      <Properties>
        <string name="Name">Workspace</string>
        <bool name="FilteringEnabled">true</bool>
        <float name="Gravity">196.2</float>
      </Properties>

      <!-- Terrain placeholder (import via Studio plugin) -->
      <Item class="Terrain" referent="RBX2">
        <Properties>
          <string name="Name">Terrain</string>
        </Properties>
      </Item>

      <!-- Spawn location (centred in world) -->
      <Item class="SpawnLocation" referent="RBX3">
        <Properties>
          <string name="Name">SpawnLocation</string>
          <CoordinateFrame name="CFrame">
            <X>0</X><Y>20</Y><Z>0</Z>
            <R00>1</R00><R01>0</R01><R02>0</R02>
            <R10>0</R10><R11>1</R11><R12>0</R12>
            <R20>0</R20><R21>0</R21><R22>1</R22>
          </CoordinateFrame>
          <Vector3 name="Size"><X>6</X><Y>1</Y><Z>6</Z></Vector3>
          <BrickColor name="BrickColor">37</BrickColor>
          <bool name="Anchored">true</bool>
        </Properties>
      </Item>

      <!-- Atmosphere -->
      <Item class="Atmosphere" referent="RBX4">
        <Properties>
          <string name="Name">Atmosphere</string>
          <float name="Density">0.3</float>
          <float name="Offset">0.25</float>
          <float name="Haze">0</float>
          <float name="Glare">0</float>
          <Color3 name="Color">
            <R>0.784</R><G>0.839</G><B>0.906</B>
          </Color3>
        </Properties>
      </Item>
    </Item>

    <!-- Lighting -->
    <Item class="Lighting" referent="RBX5">
      <Properties>
        <string name="Name">Lighting</string>
        <float name="Brightness">2</float>
        <Color3 name="Ambient"><R>0.5</R><G>0.5</G><B>0.5</B></Color3>
        <string name="TimeOfDay">14:00:00</string>
        <bool name="GlobalShadows">true</bool>
        <string name="Technology">Future</string>
      </Properties>
    </Item>

    <!-- ServerScriptService -->
    <Item class="ServerScriptService" referent="RBX6">
      <Properties><string name="Name">ServerScriptService</string></Properties>
      <Item class="Script" referent="RBX7">
        <Properties>
          <string name="Name">WorldLoader</string>
          <bool name="Disabled">false</bool>
          <ProtectedString name="Source">{esc(server_script)}</ProtectedString>
        </Properties>
      </Item>
    </Item>

    <!-- StarterPlayer -->
    <Item class="StarterPlayer" referent="RBX8">
      <Properties><string name="Name">StarterPlayer</string></Properties>
      <Item class="StarterPlayerScripts" referent="RBX9">
        <Properties><string name="Name">StarterPlayerScripts</string></Properties>
        <Item class="LocalScript" referent="RBX10">
          <Properties>
            <string name="Name">Navigation</string>
            <bool name="Disabled">false</bool>
            <ProtectedString name="Source">{esc(nav_script)}</ProtectedString>
          </Properties>
        </Item>
        <Item class="LocalScript" referent="RBX11">
          <Properties>
            <string name="Name">Minimap</string>
            <bool name="Disabled">false</bool>
            <ProtectedString name="Source">{esc(minimap_script)}</ProtectedString>
          </Properties>
        </Item>
      </Item>
    </Item>

    <!-- ReplicatedStorage -->
    <Item class="ReplicatedStorage" referent="RBX12">
      <Properties><string name="Name">ReplicatedStorage</string></Properties>
      <Item class="ModuleScript" referent="RBX13">
        <Properties>
          <string name="Name">WorldConfig</string>
          <ProtectedString name="Source">{esc(worldcfg_src)}</ProtectedString>
        </Properties>
      </Item>
    </Item>

  </Item>
</roblox>
"""
    out_path.write_text(xml, encoding="utf-8")
    print(f"  ✓ {out_path}  (Roblox place file)")

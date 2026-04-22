"""
heightmap.py — Convert a point cloud (N×7 xyz+rgba) into:

  heightmap.png   — 16-bit grayscale (or 8-bit) PNG; each pixel = terrain height
  colormap.png    — RGB PNG; each pixel = dominant surface colour
  world_meta.json — scale/origin/bounds so Roblox knows how to place terrain

Roblox terrain facts:
  - Each voxel = 4 studs (≈ 0.28 m / stud → 4 studs ≈ 1.1 m / cell)
  - Max terrain: 2048 × 2048 × 256 voxels (8192 × 8192 × 1024 studs)
  - Heightmap PNG: white = max elevation, black = min
  - Resolution: power-of-2 recommended (256, 512, 1024)
"""

from __future__ import annotations
import json
import numpy as np
from pathlib import Path
from PIL import Image


DEFAULT_RESOLUTION = 512     # output PNG side length (square)
DEFAULT_VOXEL_STUDS = 4      # Roblox: studs per terrain voxel (fixed)
DEFAULT_HEIGHT_STUDS = 512   # maximum terrain height in studs


def build_heightmap(
    points: np.ndarray,
    resolution: int = DEFAULT_RESOLUTION,
    min_alpha: float = 0.1,
) -> tuple[np.ndarray, np.ndarray, dict]:
    """
    Parameters
    ----------
    points     : N×7 float32 (x y z r g b a)
    resolution : output image side length (pixels = voxels)
    min_alpha  : discard gaussians below this opacity

    Returns
    -------
    height_u16 : H×W uint16  — height values 0-65535
    color_u8   : H×W×3 uint8 — RGB colour map
    meta       : dict with world-space bounds + scale factors
    """
    pts = points[points[:, 6] >= min_alpha]  # filter low-opacity
    if len(pts) == 0:
        raise ValueError("No points remain after opacity filter — check your input file.")

    x, y, z = pts[:, 0], pts[:, 1], pts[:, 2]
    r, g, b = pts[:, 3], pts[:, 4], pts[:, 5]

    xmin, xmax = float(x.min()), float(x.max())
    ymin, ymax = float(y.min()), float(y.max())
    zmin, zmax = float(z.min()), float(z.max())

    # Map world coords → pixel indices (0..resolution-1)
    x_range = max(xmax - xmin, 1e-6)
    z_range = max(zmax - zmin, 1e-6)
    y_range = max(ymax - ymin, 1e-6)

    ix = np.clip(((x - xmin) / x_range * (resolution - 1)).astype(int), 0, resolution - 1)
    iz = np.clip(((z - zmin) / z_range * (resolution - 1)).astype(int), 0, resolution - 1)

    # Accumulation buffers
    height_max = np.full((resolution, resolution), -np.inf, dtype="f4")
    color_r    = np.zeros((resolution, resolution), dtype="f4")
    color_g    = np.zeros((resolution, resolution), dtype="f4")
    color_b    = np.zeros((resolution, resolution), dtype="f4")
    color_cnt  = np.zeros((resolution, resolution), dtype="f4")

    # Vectorised scatter: for each point, keep colour of highest point per cell
    # Pass 1: find max Y per cell
    for i in range(len(pts)):
        px, pz = ix[i], iz[i]
        if y[i] > height_max[pz, px]:
            height_max[pz, px] = y[i]
            color_r[pz, px] = r[i]
            color_g[pz, px] = g[i]
            color_b[pz, px] = b[i]

    # Fill empty cells with nearest neighbour (simple flood from neighbours)
    empty = height_max == -np.inf
    if empty.any():
        from scipy.ndimage import distance_transform_edt
        _, (row_idx, col_idx) = distance_transform_edt(empty, return_indices=True)
        height_max[empty] = height_max[row_idx[empty], col_idx[empty]]
        color_r[empty]    = color_r   [row_idx[empty], col_idx[empty]]
        color_g[empty]    = color_g   [row_idx[empty], col_idx[empty]]
        color_b[empty]    = color_b   [row_idx[empty], col_idx[empty]]

    # Normalise height → uint16
    h_norm = (height_max - height_max.min()) / max(height_max.max() - height_max.min(), 1e-6)
    height_u16 = (h_norm * 65535).astype(np.uint16)

    # Colour → uint8
    color_u8 = np.stack([
        (np.clip(color_r, 0, 1) * 255).astype(np.uint8),
        (np.clip(color_g, 0, 1) * 255).astype(np.uint8),
        (np.clip(color_b, 0, 1) * 255).astype(np.uint8),
    ], axis=-1)

    # World metadata for Roblox
    studs_per_cell = DEFAULT_VOXEL_STUDS
    world_width_studs  = resolution * studs_per_cell
    world_depth_studs  = resolution * studs_per_cell
    world_height_studs = DEFAULT_HEIGHT_STUDS

    meta = {
        "source_bounds": {
            "x": [xmin, xmax], "y": [ymin, ymax], "z": [zmin, zmax],
        },
        "resolution": resolution,
        "roblox": {
            "studs_per_cell":    studs_per_cell,
            "world_width_studs": world_width_studs,
            "world_depth_studs": world_depth_studs,
            "world_height_studs": world_height_studs,
            # Terrain origin in Roblox coordinates (centred at 0,0)
            "terrain_x_origin": -(world_width_studs  / 2),
            "terrain_y_origin": 0,
            "terrain_z_origin": -(world_depth_studs  / 2),
        },
        "scale": {
            "world_unit_to_stud_x": world_width_studs  / x_range,
            "world_unit_to_stud_y": world_height_studs / y_range,
            "world_unit_to_stud_z": world_depth_studs  / z_range,
        },
    }

    return height_u16, color_u8, meta


def save(
    points: np.ndarray,
    out_dir: str | Path,
    resolution: int = DEFAULT_RESOLUTION,
    min_alpha: float = 0.1,
) -> dict:
    """Build and save heightmap.png, colormap.png, world_meta.json.

    Returns the meta dict.
    """
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    print(f"  Building heightmap ({resolution}×{resolution}) from {len(points):,} points …")
    height_u16, color_u8, meta = build_heightmap(points, resolution, min_alpha)

    # Save heightmap (16-bit grayscale)
    hmap_path = out_dir / "heightmap.png"
    Image.fromarray(height_u16, mode="I;16").save(hmap_path)
    print(f"  ✓ {hmap_path}  [{resolution}×{resolution} 16-bit]")

    # Save colormap (RGB)
    cmap_path = out_dir / "colormap.png"
    Image.fromarray(color_u8, mode="RGB").save(cmap_path)
    print(f"  ✓ {cmap_path}  [{resolution}×{resolution} RGB]")

    # Save metadata
    meta_path = out_dir / "world_meta.json"
    meta_path.write_text(json.dumps(meta, indent=2))
    print(f"  ✓ {meta_path}")

    return meta

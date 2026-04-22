"""
test_pipeline.py — Smoke tests for the skysplat2roblox pipeline.

Run: python -m pytest tests/ -v
Or:  python tests/test_pipeline.py
"""

import sys
import numpy as np
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from pipeline.splat_reader import make_test_points
from pipeline.heightmap import build_heightmap, save as save_heightmap
from pipeline.rbxlx_builder import build as build_rbxlx


def test_make_test_points():
    pts = make_test_points(n=1000)
    assert pts.shape == (1000, 7), f"Expected (1000, 7), got {pts.shape}"
    assert pts[:, 3:6].max() <= 1.0, "RGB should be <= 1"
    assert pts[:, 3:6].min() >= 0.0, "RGB should be >= 0"
    print("  ✓ make_test_points")


def test_build_heightmap():
    pts = make_test_points(n=5000)
    h, c, meta = build_heightmap(pts, resolution=64)
    assert h.shape == (64, 64), f"Expected (64,64), got {h.shape}"
    assert c.shape == (64, 64, 3), f"Expected (64,64,3), got {c.shape}"
    assert h.dtype == np.uint16, "Height should be uint16"
    assert c.dtype == np.uint8, "Color should be uint8"
    assert "roblox" in meta, "Meta should have 'roblox' key"
    print("  ✓ build_heightmap")


def test_save_pipeline():
    pts = make_test_points(n=5000)
    with tempfile.TemporaryDirectory() as tmpdir:
        out = Path(tmpdir)
        meta = save_heightmap(pts, out, resolution=64)

        assert (out / "heightmap.png").exists(), "heightmap.png missing"
        assert (out / "colormap.png").exists(),  "colormap.png missing"
        assert (out / "world_meta.json").exists(), "world_meta.json missing"

        rbxlx_path = out / "world.rbxlx"
        build_rbxlx(rbxlx_path, meta)
        assert rbxlx_path.exists(), "world.rbxlx missing"

        content = rbxlx_path.read_text()
        assert "DataModel" in content, ".rbxlx should contain DataModel"
        assert "WorldLoader" in content, ".rbxlx should contain WorldLoader script"
        assert "Navigation" in content,  ".rbxlx should contain Navigation script"
        assert "Minimap" in content,     ".rbxlx should contain Minimap script"

    print("  ✓ full pipeline save")


def test_ply_ascii_write_and_read():
    """Write a minimal ASCII PLY and parse it back."""
    import struct

    ply_content = b"""ply
format ascii 1.0
element vertex 3
property float x
property float y
property float z
property uchar red
property uchar green
property uchar blue
end_header
1.0 2.0 3.0 255 0 0
4.0 5.0 6.0 0 255 0
7.0 8.0 9.0 0 0 255
"""
    with tempfile.NamedTemporaryFile(suffix=".ply", delete=False) as f:
        f.write(ply_content)
        ply_path = Path(f.name)

    try:
        from pipeline.splat_reader import read_ply
        pts = read_ply(ply_path)
        assert pts.shape == (3, 7), f"Expected (3,7), got {pts.shape}"
        assert abs(pts[0, 0] - 1.0) < 1e-4, "x[0] should be 1.0"
        assert abs(pts[0, 3] - 1.0) < 1e-4, "r[0] should be 1.0 (255/255)"
    finally:
        ply_path.unlink()

    print("  ✓ ascii PLY read")


if __name__ == "__main__":
    print("\n🧪  Running pipeline tests …\n")
    test_make_test_points()
    test_build_heightmap()
    test_save_pipeline()
    test_ply_ascii_write_and_read()
    print("\n✅  All tests passed!\n")

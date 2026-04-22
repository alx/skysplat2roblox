"""
cli.py — Main entry point for the skysplat2roblox pipeline

Usage:
  python -m pipeline <input_file> [options]

Examples:
  python -m pipeline scene.ply
  python -m pipeline scene.splat --out ./roblox_out --resolution 512
  python -m pipeline scene.ply   --out ./roblox_out --resolution 1024 --min-alpha 0.2
  python -m pipeline --demo                          # generate from synthetic test data

Outputs (in --out directory):
  heightmap.png     16-bit grayscale — import via Roblox Studio terrain importer
                    OR via studio_plugin/SkySplatImporter.plugin.lua
  colormap.png      RGB surface colours
  world_meta.json   Scale + origin metadata (read by in-game WorldConfig)
  world.rbxlx       Roblox place file with nav scripts pre-loaded
"""

from __future__ import annotations
import argparse
import sys
from pathlib import Path

from .splat_reader import load, make_test_points
from .heightmap import save as save_heightmap
from .rbxlx_builder import build as build_rbxlx


def main(argv=None):
    parser = argparse.ArgumentParser(
        prog="python -m pipeline",
        description="Convert Gaussian Splat / drone point cloud → Roblox world",
    )
    parser.add_argument("input", nargs="?", help="Input file (.ply / .splat / .obj)")
    parser.add_argument("--out",        "-o", default="./out", help="Output directory (default: ./out)")
    parser.add_argument("--resolution", "-r", type=int, default=512,  help="Heightmap resolution in pixels (default: 512)")
    parser.add_argument("--min-alpha",  "-a", type=float, default=0.1, help="Minimum opacity threshold (default: 0.1)")
    parser.add_argument("--demo",       action="store_true", help="Run with synthetic test data (no input file needed)")
    args = parser.parse_args(argv)

    if args.demo:
        print("\n🧪  Demo mode — generating synthetic hilly landscape …\n")
        points = make_test_points(n=50_000)
    elif args.input:
        print(f"\n📡  Loading: {args.input}\n")
        points = load(args.input)
    else:
        parser.print_help()
        sys.exit(0)

    out_dir = Path(args.out)
    print(f"\n🗺️   Building world → {out_dir}/\n")

    meta = save_heightmap(points, out_dir, resolution=args.resolution, min_alpha=args.min_alpha)

    rbxlx_path = out_dir / "world.rbxlx"
    build_rbxlx(rbxlx_path, meta)

    print(f"""
✅  Done!

Next steps:
  1. Open Roblox Studio
  2. File → Open → {out_dir / "world.rbxlx"}
  3. Run the Studio plugin to import the terrain:
       Plugins → SkySplat Importer → Import Heightmap
       (select {out_dir / "heightmap.png"} and {out_dir / "colormap.png"})
  4. Playtest the world (press ▶)
  5. Publish → File → Publish to Roblox
     OR use: python publish/publish.py --place {rbxlx_path}
""")


if __name__ == "__main__":
    main()

"""
publish.py — Publish a Roblox place via Open Cloud API

Uploads a .rbxlx file to an existing Roblox Universe/Place.
Requires a Roblox Open Cloud API key with permission:
  universe-places:write

Usage:
  python publish/publish.py --place ./out/world.rbxlx
  python publish/publish.py --place ./out/world.rbxlx \
      --universe-id 1234567890 --place-id 9876543210

Environment variables (see .env.example):
  ROBLOX_API_KEY      — Open Cloud API key
  ROBLOX_UNIVERSE_ID  — Universe (game) ID
  ROBLOX_PLACE_ID     — Place ID within the universe

How to get these:
  1. Create a game at create.roblox.com
  2. Note the Universe ID and Place ID from the URL
  3. Creator Hub → Credentials → API Keys → Create key
     Scope: Universe → universe-places:write
"""

from __future__ import annotations
import argparse
import os
import sys
from pathlib import Path

try:
    import requests
except ImportError:
    print("Install requests: pip install requests")
    sys.exit(1)


API_BASE = "https://apis.roblox.com"


def publish(
    place_path: Path,
    universe_id: int,
    place_id: int,
    api_key: str,
    version_type: str = "Published",
) -> dict:
    """Upload place file to Roblox Open Cloud. Returns version info dict."""
    url = f"{API_BASE}/universes/v1/{universe_id}/places/{place_id}/versions"
    headers = {
        "x-api-key":     api_key,
        "Content-Type":  "application/xml",
    }
    params = {"versionType": version_type}

    print(f"  Uploading {place_path.name} ({place_path.stat().st_size:,} bytes) …")

    with open(place_path, "rb") as f:
        resp = requests.post(url, headers=headers, params=params, data=f, timeout=120)

    if resp.status_code == 200:
        data = resp.json()
        print(f"  ✓ Published!  Version: {data.get('versionNumber', '?')}")
        print(f"    Universe: {universe_id}  Place: {place_id}")
        print(f"    Play URL: https://www.roblox.com/games/{place_id}")
        return data
    else:
        print(f"  ✗ HTTP {resp.status_code}: {resp.text}")
        resp.raise_for_status()


def main():
    parser = argparse.ArgumentParser(
        description="Publish .rbxlx to Roblox via Open Cloud API"
    )
    parser.add_argument("--place",        required=True,  help=".rbxlx file path")
    parser.add_argument("--universe-id",  type=int,       help="Roblox Universe ID")
    parser.add_argument("--place-id",     type=int,       help="Roblox Place ID")
    parser.add_argument("--api-key",      default=None,   help="Open Cloud API key")
    parser.add_argument("--saved",        action="store_true",
                        help="Publish as 'Saved' (draft) instead of 'Published' (live)")
    args = parser.parse_args()

    # Load .env if present
    env_path = Path(__file__).parent.parent / ".env"
    if env_path.exists():
        for line in env_path.read_text().split("\n"):
            m = __import__("re").match(r"^([A-Z_]+)=(.+)", line)
            if m and m.group(1) not in os.environ:
                os.environ[m.group(1)] = m.group(2).strip().strip('"')

    api_key     = args.api_key    or os.environ.get("ROBLOX_API_KEY")
    universe_id = args.universe_id or int(os.environ.get("ROBLOX_UNIVERSE_ID", 0))
    place_id    = args.place_id   or int(os.environ.get("ROBLOX_PLACE_ID",    0))

    if not api_key:
        print("✗  ROBLOX_API_KEY not set. Add to .env or pass --api-key")
        print("   Get a key at: https://create.roblox.com/credentials")
        sys.exit(1)
    if not universe_id or not place_id:
        print("✗  ROBLOX_UNIVERSE_ID and ROBLOX_PLACE_ID must be set.")
        print("   Find them in the URL at create.roblox.com/dashboard/creations")
        sys.exit(1)

    place_path = Path(args.place)
    if not place_path.exists():
        print(f"✗  File not found: {place_path}")
        sys.exit(1)

    version_type = "Saved" if args.saved else "Published"
    print(f"\n🚀  Publishing to Roblox ({version_type}) …\n")
    publish(place_path, universe_id, place_id, api_key, version_type)


if __name__ == "__main__":
    main()

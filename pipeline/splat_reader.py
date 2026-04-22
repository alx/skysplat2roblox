"""
splat_reader.py — Parse Gaussian Splat source files

Supported formats:
  .ply    — standard / gaussian-splat PLY (ascii + binary_little_endian)
  .splat  — compact binary viewer format (32 bytes / gaussian)
  .obj    — simple wavefront OBJ mesh (vertices only, no faces needed)

Returns an N×7 float32 numpy array: [x, y, z, r, g, b, a]
  xyz in scene units (usually metres)
  rgb in [0, 1]
  a   in [0, 1] (opacity; 1.0 for mesh/simple point cloud sources)
"""

from __future__ import annotations
import struct
import numpy as np
from pathlib import Path


# ── PLY parser ────────────────────────────────────────────────────────────────

_PLY_DTYPE_MAP = {
    "float":   "f4", "float32": "f4",
    "double":  "f8", "float64": "f8",
    "int":     "i4", "int32":   "i4",
    "uint":    "u4", "uint32":  "u4",
    "short":   "i2", "int16":   "i2",
    "ushort":  "u2", "uint16":  "u2",
    "char":    "i1", "int8":    "i1",
    "uchar":   "u1", "uint8":   "u1",
}


def read_ply(path: Path) -> np.ndarray:
    """Parse PLY → N×7 float32 (x y z r g b a).

    Handles both simple XYZRGB point clouds and full Gaussian Splat PLY
    (with SH f_dc_* coefficients for colour and logit-sigmoid opacity).
    """
    with open(path, "rb") as f:
        header_lines, data_start = _parse_ply_header(f)

    props, n_verts, is_binary, is_big_endian = _extract_ply_meta(header_lines)

    if is_binary:
        with open(path, "rb") as f:
            f.seek(data_start)
            raw = np.frombuffer(
                f.read(n_verts * sum(np.dtype(t).itemsize for _, t in props)),
                dtype=np.dtype([(n, t) for n, t in props])
            )
    else:
        with open(path, "rb") as f:
            f.seek(data_start)
            rows = [list(map(float, f.readline().split())) for _ in range(n_verts)]
        names = [n for n, _ in props]
        raw = {n: np.array([r[i] for r in rows]) for i, n in enumerate(names)}
        raw = _dict_to_structured(raw, props)

    return _ply_structured_to_xyzrgba(raw, props, n_verts)


def _parse_ply_header(f):
    lines = []
    while True:
        line = f.readline().decode("ascii", errors="ignore").strip()
        lines.append(line)
        if line == "end_header":
            break
    return lines, f.tell()


def _extract_ply_meta(lines):
    props = []
    n_verts = 0
    is_binary = False
    is_big_endian = False
    in_vertex = False

    for line in lines:
        parts = line.split()
        if not parts:
            continue
        if parts[0] == "format":
            is_binary = parts[1] != "ascii"
            is_big_endian = parts[1] == "binary_big_endian"
        elif parts[0] == "element" and parts[1] == "vertex":
            n_verts = int(parts[2])
            in_vertex = True
        elif parts[0] == "element" and parts[1] != "vertex":
            in_vertex = False
        elif parts[0] == "property" and in_vertex:
            dtype_str = parts[1]
            prop_name = parts[2]
            dtype = _PLY_DTYPE_MAP.get(dtype_str, "f4")
            if is_big_endian:
                dtype = ">" + dtype
            props.append((prop_name, dtype))

    return props, n_verts, is_binary, is_big_endian


def _dict_to_structured(d: dict, props) -> np.ndarray:
    n = len(next(iter(d.values())))
    dt = np.dtype([(n, t) for n, t in props])
    arr = np.zeros(n, dtype=dt)
    for name, _ in props:
        if name in d:
            arr[name] = d[name]
    return arr


def _sigmoid(x):
    return 1.0 / (1.0 + np.exp(-x))


def _sh0_to_rgb(sh: np.ndarray) -> np.ndarray:
    """Convert DC spherical harmonic coefficient to RGB [0,1]."""
    # SH band-0 colour: C = 0.5 + SH_0 * 0.28209  (1/(2*sqrt(pi)))
    return np.clip(0.5 + sh * 0.28209479177387814, 0.0, 1.0)


def _ply_structured_to_xyzrgba(raw, props, n):
    names = {p[0] for p in props}
    xyz = np.column_stack([raw["x"].astype("f4"),
                           raw["y"].astype("f4"),
                           raw["z"].astype("f4")])

    # ── Colour ───────────────────────────────────────────────────────────────
    if "f_dc_0" in names:
        # Gaussian Splat SH DC coefficients
        r = _sh0_to_rgb(raw["f_dc_0"].astype("f4"))
        g = _sh0_to_rgb(raw["f_dc_1"].astype("f4"))
        b = _sh0_to_rgb(raw["f_dc_2"].astype("f4"))
    elif "red" in names:
        r = raw["red"].astype("f4") / 255.0
        g = raw["green"].astype("f4") / 255.0
        b = raw["blue"].astype("f4") / 255.0
    elif "diffuse_red" in names:
        r = raw["diffuse_red"].astype("f4") / 255.0
        g = raw["diffuse_green"].astype("f4") / 255.0
        b = raw["diffuse_blue"].astype("f4") / 255.0
    else:
        r = g = b = np.full(n, 0.7, dtype="f4")

    # ── Opacity ──────────────────────────────────────────────────────────────
    if "opacity" in names:
        a = _sigmoid(raw["opacity"].astype("f4"))
    elif "alpha" in names:
        a = raw["alpha"].astype("f4") / 255.0
    else:
        a = np.ones(n, dtype="f4")

    return np.column_stack([xyz, r, g, b, a]).astype("f4")


# ── .splat binary parser ─────────────────────────────────────────────────────
# Format: 32 bytes / gaussian
#   xyz    : float32 × 3  (12 bytes)  — position
#   scale  : float32 × 3  (12 bytes)  — log-scale of each axis
#   color  : uint8  × 4   ( 4 bytes)  — rgba [0,255]
#   rot    : uint8  × 4   ( 4 bytes)  — quaternion wxyz [0,255] → [-1,1]

_SPLAT_DTYPE = np.dtype([
    ("x",  "<f4"), ("y",  "<f4"), ("z",  "<f4"),
    ("sx", "<f4"), ("sy", "<f4"), ("sz", "<f4"),
    ("r",  "u1"),  ("g",  "u1"),  ("b",  "u1"),  ("a",  "u1"),
    ("qw", "u1"),  ("qx", "u1"),  ("qy", "u1"),  ("qz", "u1"),
])
assert _SPLAT_DTYPE.itemsize == 32


def read_splat(path: Path) -> np.ndarray:
    """.splat binary → N×7 float32 (x y z r g b a)."""
    data = np.fromfile(path, dtype=_SPLAT_DTYPE)
    xyz = np.column_stack([data["x"], data["y"], data["z"]]).astype("f4")
    rgb = np.column_stack([data["r"], data["g"], data["b"]]).astype("f4") / 255.0
    a   = data["a"].astype("f4") / 255.0
    return np.column_stack([xyz, rgb, a]).astype("f4")


# ── .obj parser ───────────────────────────────────────────────────────────────

def read_obj(path: Path) -> np.ndarray:
    """Wavefront OBJ → N×7 (vertices only; color from vertex comments if present)."""
    verts = []
    with open(path, "r", errors="ignore") as f:
        for line in f:
            parts = line.strip().split()
            if not parts or parts[0] != "v":
                continue
            x, y, z = float(parts[1]), float(parts[2]), float(parts[3])
            r = float(parts[4]) if len(parts) > 4 else 0.7
            g = float(parts[5]) if len(parts) > 5 else 0.7
            b = float(parts[6]) if len(parts) > 6 else 0.7
            # Normalise: OBJ colour is [0,1] already; if >1 it's [0,255]
            if r > 1.0 or g > 1.0 or b > 1.0:
                r, g, b = r / 255.0, g / 255.0, b / 255.0
            verts.append([x, y, z, r, g, b, 1.0])
    return np.array(verts, dtype="f4") if verts else np.zeros((0, 7), dtype="f4")


# ── Public entry point ────────────────────────────────────────────────────────

def load(path: str | Path) -> np.ndarray:
    """Auto-detect format; return N×7 float32 (x y z r g b a)."""
    path = Path(path)
    suffix = path.suffix.lower()
    if suffix == ".ply":
        pts = read_ply(path)
    elif suffix == ".splat":
        pts = read_splat(path)
    elif suffix == ".obj":
        pts = read_obj(path)
    else:
        raise ValueError(f"Unsupported format: {suffix}. Use .ply, .splat, or .obj")

    print(f"  ✓ Loaded {len(pts):,} points from {path.name}")
    return pts


# ── Tiny synthetic test data ─────────────────────────────────────────────────

def make_test_points(n: int = 10_000, seed: int = 42) -> np.ndarray:
    """Generate a synthetic hilly landscape for testing."""
    rng = np.random.default_rng(seed)
    x = rng.uniform(-50, 50, n).astype("f4")
    z = rng.uniform(-50, 50, n).astype("f4")
    y = (
        5 * np.sin(x * 0.1) * np.cos(z * 0.1)
        + 2 * np.sin(x * 0.3)
        + rng.uniform(-0.5, 0.5, n)
    ).astype("f4")
    r = np.clip(0.3 + y * 0.03, 0.1, 0.9).astype("f4")
    g = np.clip(0.6 - y * 0.01, 0.2, 0.9).astype("f4")
    b = np.clip(0.2 + z * 0.004, 0.1, 0.5).astype("f4")
    a = np.ones(n, dtype="f4")
    return np.column_stack([x, y, z, r, g, b, a])

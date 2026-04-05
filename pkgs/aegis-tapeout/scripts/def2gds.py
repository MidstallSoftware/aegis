"""Convert a DEF file to GDS, merging with cell and macro GDS libraries.

Environment variables:
  CELL_GDS_DIR  - directory containing PDK standard cell GDS files
  MACRO_GDS_DIR - directory containing tile macro GDS files (optional)
  LEF_DIR       - directory containing LEF files for cell/macro definitions
  TECH_LEF      - path to tech LEF file
  DEF_FILE      - path to routed DEF file
  OUT_GDS       - output GDS path
"""

import glob
import os

import pya

cell_gds_dir = os.environ["CELL_GDS_DIR"]
macro_gds_dir = os.environ.get("MACRO_GDS_DIR", "")
lef_dir = os.environ.get("LEF_DIR", "")
tech_lef = os.environ.get("TECH_LEF", "")
def_file = os.environ["DEF_FILE"]
out_gds = os.environ["OUT_GDS"]

layout = pya.Layout()

# Read tech LEF first (layer definitions)
if tech_lef and os.path.exists(tech_lef):
    print(f"Reading tech LEF: {tech_lef}")
    layout.read(tech_lef)

# Read all cell LEF files for geometry definitions
if lef_dir and os.path.isdir(lef_dir):
    lef_files = sorted(glob.glob(os.path.join(lef_dir, "*.lef")))
    print(f"Reading {len(lef_files)} cell LEF files from {lef_dir}")
    for lef in lef_files:
        if "tech" not in os.path.basename(lef).lower():
            layout.read(lef)

# Read all standard cell GDS files from the PDK
gds_files = sorted(glob.glob(os.path.join(cell_gds_dir, "*.gds")))
print(f"Reading {len(gds_files)} cell GDS files from {cell_gds_dir}")
for gds in gds_files:
    layout.read(gds)

# Read tile macro GDS files
if macro_gds_dir and os.path.isdir(macro_gds_dir):
    macro_files = sorted(glob.glob(os.path.join(macro_gds_dir, "*.gds")))
    print(f"Reading {len(macro_files)} macro GDS files from {macro_gds_dir}")
    for gds in macro_files:
        layout.read(gds)

# Read the routed DEF (references cells and macros by name)
print(f"Reading DEF: {def_file}")
layout.read(def_file)

layout.write(out_gds)
print(f"Wrote {out_gds}")

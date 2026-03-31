"""Convert a DEF file to GDS, merging with cell GDS library.

Environment variables:
  CELL_GDS  - path to cell GDS library
  DEF_FILE  - path to routed DEF file
  OUT_GDS   - output GDS path
"""

import os
import pya

cell_gds = os.environ["CELL_GDS"]
def_file = os.environ["DEF_FILE"]
out_gds = os.environ["OUT_GDS"]

layout = pya.Layout()
layout.read(cell_gds)
layout.read(def_file)
layout.write(out_gds)

print(f"Wrote {out_gds}")

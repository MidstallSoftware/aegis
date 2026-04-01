# Apply PCF-style IO constraints for Aegis
# Reads blinky.pcf and constrains IO cells to specific BELs

import os

pcf_file = os.environ.get("PCF_FILE", "blinky.pcf")

with open(pcf_file) as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) == 3 and parts[0] == "set_io":
            signal, bel = parts[1], parts[2]
            for cname, cell in ctx.cells:
                if cname == signal:
                    cell.setAttr("BEL", bel)
                    break

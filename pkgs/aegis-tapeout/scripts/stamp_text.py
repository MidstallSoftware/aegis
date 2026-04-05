"""Stamp text into a GDS file on a comment/documentation layer.

Places text (e.g. a Nix store path) as polygon outlines on a
non-routing layer so it's visible in the die but doesn't affect
DRC or signal integrity.

Environment variables:
  GDS_FILE   - path to input GDS file (modified in-place)
  STAMP_TEXT - text string to stamp
  LAYER      - (optional) GDS layer number, default 236
  DATATYPE   - (optional) GDS datatype, default 0
  FONT_SIZE  - (optional) text height in microns, default 50
  X_OFFSET   - (optional) X position in microns from left edge, default 50
  Y_OFFSET   - (optional) Y position in microns from top edge, default 50
"""

import os

import pya

gds_file = os.environ["GDS_FILE"]
stamp_text = os.environ["STAMP_TEXT"]
layer_num = int(os.environ.get("LAYER", "236"))
datatype = int(os.environ.get("DATATYPE", "0"))
font_height_um = float(os.environ.get("FONT_SIZE", "80"))
x_offset = float(os.environ.get("X_OFFSET", "50"))
y_offset = float(os.environ.get("Y_OFFSET", "50"))

layout = pya.Layout()
layout.read(gds_file)

# Find top cell (largest bounding box)
top_cell = None
best_area = 0
for ci in range(layout.cells()):
    c = layout.cell(ci)
    bbox = c.bbox()
    area = bbox.width() * bbox.height()
    if area > best_area:
        best_area = area
        top_cell = c

if top_cell is None:
    print("Warning: No cells found, skipping text stamp")
else:
    li = layout.layer(layer_num, datatype)
    dbu = layout.dbu
    die_bbox = top_cell.bbox()
    available_w_um = (die_bbox.width() * dbu) - 2 * x_offset

    gen = pya.TextGenerator.default_generator()

    # text() args: string, target_dbu, height_in_microns
    # Probe a single character to measure width
    probe = gen.text("X", dbu, font_height_um)
    char_w_um = probe.bbox().width() * dbu

    # Split text into lines that fit within the available die width
    if char_w_um > 0:
        chars_per_line = max(1, int(available_w_um / (char_w_um * 1.1)))
    else:
        chars_per_line = len(stamp_text)

    lines = []
    for i in range(0, len(stamp_text), chars_per_line):
        lines.append(stamp_text[i : i + chars_per_line])

    # Render each line and stack top-down from the top of the die
    line_spacing_um = font_height_um * 1.4
    anchor_x_dbu = die_bbox.left + int(x_offset / dbu)
    anchor_y_dbu = die_bbox.top - int(y_offset / dbu)

    for i, line in enumerate(lines):
        text_region = gen.text(line, dbu, font_height_um)
        text_bbox = text_region.bbox()

        dx = anchor_x_dbu - text_bbox.left
        dy = anchor_y_dbu - text_bbox.top - int(i * line_spacing_um / dbu)
        text_region.move(dx, dy)

        top_cell.shapes(li).insert(text_region)

    tmp_file = gds_file + ".tmp.gds"
    layout.write(tmp_file)
    os.replace(tmp_file, gds_file)

    total_h = len(lines) * line_spacing_um
    print(
        f"Stamped {len(lines)} line(s) on layer {layer_num}/{datatype}, "
        f"height {font_height_um:.0f} um/line, total {total_h:.0f} um tall"
    )

"""Render a GDS file to a PNG image.

Zooms to show the actual placed cell content area.

Environment variables:
  GDS_FILE       - path to input GDS file
  OUT_PNG        - output PNG path
  TOP_CELL_NAME  - (optional) name of the top cell to render
  IMG_WIDTH      - (optional) image width in pixels, default 2048
  IMG_HEIGHT     - (optional) image height in pixels, default 2048
"""

import os

import pya

gds_file = os.environ["GDS_FILE"]
out_png = os.environ["OUT_PNG"]
top_name = os.environ.get("TOP_CELL_NAME", "")
img_w = int(os.environ.get("IMG_WIDTH", "2048"))
img_h = int(os.environ.get("IMG_HEIGHT", "2048"))

layout = pya.Layout()
layout.read(gds_file)

# Find top cell by name, or pick the largest
top_cell = None
if top_name:
    for ci in range(layout.cells()):
        c = layout.cell(ci)
        if c.name == top_name:
            top_cell = c
            break

if top_cell is None:
    best_area = 0
    for ci in range(layout.cells()):
        c = layout.cell(ci)
        bbox = c.bbox()
        area = bbox.width() * bbox.height()
        if area > best_area:
            best_area = area
            top_cell = c

if top_cell is None:
    print("Warning: No cells found, skipping render")
else:
    view = pya.LayoutView()
    cv = view.show_layout(layout, False)
    view.max_hier()
    view.set_current_cell_path(cv, [top_cell.cell_index()])
    view.set_config("background-color", "#000000")

    # Zoom to the full top cell bounding box (die boundary)
    dbox = pya.DBox(top_cell.bbox()) * layout.dbu
    margin = max(dbox.width(), dbox.height()) * 0.05
    dbox = dbox.enlarged(margin, margin)
    view.zoom_box(dbox)

    view.save_image(out_png, img_w, img_h)
    print(f"Rendered {top_cell.name} ({img_w}x{img_h}) to {out_png}")

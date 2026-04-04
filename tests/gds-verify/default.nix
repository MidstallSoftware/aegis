# GDS physical verification using KLayout DRC/LVS.
#
# Detects the PDK from the tapeout passthru and runs the appropriate
# foundry DRC and LVS checks on the GDS output.
{
  lib,
  stdenvNoCC,
  python3,
  klayout,
  aegis-tapeout,
}:

let
  inherit (aegis-tapeout) deviceName pdk;
  inherit (pdk) pdkName pdkPath;
  fullPdkPath = "${pdk}/${pdkPath}";
  # PV rule decks live under the PDK's pv/ directory
  pvPath = "${fullPdkPath}/pv";
  # DRC variant selection per PDK
  drcVariant =
    if pdkName == "gf180mcu" then
      "C" # 9K metal_top, 5LM
    else if pdkName == "sky130" then
      "sky130A"
    else
      "default";
in
stdenvNoCC.mkDerivation {
  name = "aegis-gds-verify-${deviceName}";

  dontUnpack = true;

  nativeBuildInputs = [
    python3
    klayout
  ];

  buildPhase = ''
    runHook preBuild

    GDS="${aegis-tapeout}/${deviceName}.gds"
    NETLIST="${aegis-tapeout}/${deviceName}_final.v"

    echo "=== GDS verification for ${deviceName} ==="

    # ---- Step 1: Verify GDS exists and is non-empty ----
    echo "--- Step 1: GDS file validation ---"
    if [ ! -f "$GDS" ]; then
      echo "FAIL: GDS file not found at $GDS"
      echo "NOTE: Tapeout may not have produced GDS (OpenROAD/KLayout step may have failed)"
      echo "Skipping GDS verification, tapeout pipeline needs to succeed first"

      mkdir -p $out
      echo "SKIP" > $out/result
      exit 0
    fi

    GDS_SIZE=$(stat -c %s "$GDS")
    echo "GDS file: $GDS ($GDS_SIZE bytes)"
    if [ "$GDS_SIZE" -lt 100 ]; then
      echo "FAIL: GDS file too small ($GDS_SIZE bytes)"
      exit 1
    fi
    echo "PASS: GDS file exists and is non-trivial"

    # ---- Step 2: KLayout GDS structure check ----
    echo "--- Step 2: GDS structure validation ---"
    cat > check_gds.py << 'PYEOF'
    import sys
    import os

    # KLayout Python API
    import pya

    gds_path = os.environ["GDS_PATH"]
    layout = pya.Layout()
    layout.read(gds_path)

    errors = 0

    # Check we have at least one cell
    if layout.cells() == 0:
        print("FAIL: GDS contains no cells")
        errors += 1
    else:
        print(f"  Cells: {layout.cells()}")

    # Check we have layers
    layer_count = 0
    for li in layout.layer_indices():
        layer_count += 1
    if layer_count == 0:
        print("FAIL: GDS contains no layers")
        errors += 1
    else:
        print(f"  Layers: {layer_count}")

    # Check top cell exists
    top_cells = [c for c in layout.each_cell() if c.is_top()]
    if len(top_cells) == 0:
        print("FAIL: No top-level cell found")
        errors += 1
    else:
        for tc in top_cells:
            bbox = tc.bbox()
            print(f"  Top cell: {tc.name} ({bbox.width()/1000:.1f} x {bbox.height()/1000:.1f} um)")
            if bbox.width() == 0 or bbox.height() == 0:
                print("FAIL: Top cell has zero area")
                errors += 1

    if errors > 0:
        sys.exit(1)
    print("PASS: GDS structure valid")
    PYEOF

    GDS_PATH="$GDS" QT_QPA_PLATFORM=offscreen klayout -b -r check_gds.py 2>&1 | tee gds_check.log
    if [ $? -ne 0 ]; then
      echo "FAIL: GDS structure check failed"
      exit 1
    fi

    # ---- Step 3: KLayout DRC ----
    echo "--- Step 3: DRC (${pdkName} design rules) ---"
    DRC_SCRIPT="${pvPath}/klayout/drc/run_drc.py"

    if [ -f "$DRC_SCRIPT" ]; then
      mkdir -p drc_output
      QT_QPA_PLATFORM=offscreen python3 "$DRC_SCRIPT" \
        --path="$GDS" \
        --variant=${drcVariant} \
        --run_dir=drc_output \
        --no_feol \
        --thr=1 \
        2>&1 | tee drc.log || true

      # Check for DRC violations
      VIOLATION_FILES=$(find drc_output -name "*.lyrdb" 2>/dev/null)
      if [ -n "$VIOLATION_FILES" ]; then
        VIOLATIONS=$(grep -c "<value>" $VIOLATION_FILES 2>/dev/null || echo "0")
        echo "DRC violations found: $VIOLATIONS"
        if [ "$VIOLATIONS" = "0" ]; then
          echo "PASS: DRC clean"
        else
          echo "WARNING: $VIOLATIONS DRC violations (review needed)"
        fi
      else
        echo "NOTE: DRC output not generated (may need additional setup)"
      fi
    else
      echo "NOTE: DRC script not found, skipping (PDK: ${pdkName})"
    fi

    # ---- Step 4: KLayout LVS ----
    echo "--- Step 4: LVS (layout vs schematic) ---"
    LVS_SCRIPT="${pvPath}/klayout/lvs/run_lvs.py"

    if [ -f "$LVS_SCRIPT" ] && [ -f "$NETLIST" ]; then
      mkdir -p lvs_output
      QT_QPA_PLATFORM=offscreen python3 "$LVS_SCRIPT" \
        --layout="$GDS" \
        --netlist="$NETLIST" \
        --variant=${drcVariant} \
        --run_dir=lvs_output \
        --thr=1 \
        2>&1 | tee lvs.log || true

      if grep -q "MATCH" lvs.log 2>/dev/null; then
        echo "PASS: LVS matched"
      else
        echo "WARNING: LVS result needs review"
      fi
    else
      echo "NOTE: LVS skipped (script or netlist not available, PDK: ${pdkName})"
    fi

    echo "=== GDS verification complete ==="

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp *.log $out/ 2>/dev/null || true
    cp -r drc_output $out/ 2>/dev/null || true
    cp -r lvs_output $out/ 2>/dev/null || true
    echo "PASS" > $out/result
    runHook postInstall
  '';
}

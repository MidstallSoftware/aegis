{
  lib,
  stdenv,
  mkShell,
  yosys,
  openroad,
  xschem,
  klayout,
  magic-vlsi,
  ngspice,
  surfer,
  aegis-ip,
}:

lib.extendMkDerivation {
  constructDrv = stdenv.mkDerivation;

  excludeDrvArgNames = [
    "pdk"
    "cellLib"
    "clockPeriodNs"
    "dieWidthUm"
    "dieHeightUm"
    "coreUtilization"
  ];

  extendDrvArgs =
    finalAttrs:
    {
      name ? "aegis-tapeout-${aegis-ip.deviceName}",
      pdk,
      cellLib ? pdk.cellLib,
      clockPeriodNs ? 20,
      dieWidthUm ? null,
      dieHeightUm ? null,
      coreUtilization ? 0.5,
      ...
    }@args:

    assert lib.assertMsg (
      clockPeriodNs > 0
    ) "aegis-tapeout: clockPeriodNs must be > 0, got ${toString clockPeriodNs}";
    assert lib.assertMsg (
      coreUtilization > 0.0 && coreUtilization <= 1.0
    ) "aegis-tapeout: coreUtilization must be in (0, 1], got ${toString coreUtilization}";

    let
      deviceName = aegis-ip.deviceName;
      pdkPath = "${pdk}/${pdk.pdkPath}";
      libsRef = "${pdkPath}/libs.ref/${cellLib}";
    in
    builtins.removeAttrs args [
      "pdk"
      "cellLib"
      "clockPeriodNs"
      "dieWidthUm"
      "dieHeightUm"
      "coreUtilization"
    ]
    // {
      inherit name;

      dontUnpack = true;
      dontConfigure = true;

      nativeBuildInputs = (args.nativeBuildInputs or [ ]) ++ [
        yosys
        openroad
        xschem
        klayout
      ];

      buildPhase = ''
        runHook preBuild

        # Find PDK files
        LIB_FILE=$(find ${libsRef}/lib -name '*tt*' -name '*.lib' | head -1)
        if [ -z "$LIB_FILE" ]; then
          LIB_FILE=$(find ${libsRef}/lib -name '*.lib' | head -1)
        fi
        echo "Using liberty: $LIB_FILE"

        TECH_LEF=$(find ${libsRef}/lef -name '*tech*.lef' | head -1)
        echo "Using tech LEF: $TECH_LEF"

        # ================================================================
        # Stage 1: Yosys synthesis
        # ================================================================
        echo "=== Stage 1: Yosys synthesis ==="

        # Write TCL prologue with variables, then source generated script
        cat > synth.tcl << YOSYS_EOF
        set SV_FILE "${aegis-ip}/${deviceName}.sv"
        set LIB_FILE "$LIB_FILE"
        set CELL_LIB "${cellLib}"
        set DEVICE_NAME "${deviceName}"
        source ${aegis-ip}/${deviceName}-yosys.tcl
        YOSYS_EOF
        yosys -c synth.tcl > yosys.log 2>&1

        # ================================================================
        # Stage 2: SDC constraints
        # ================================================================
        echo "=== Stage 2: Generating constraints ==="

        cat > constraints.sdc << EOF
        create_clock [get_ports clk] -name clk -period ${toString clockPeriodNs}
        EOF

        # ================================================================
        # Stage 3: OpenROAD place and route
        # ================================================================
        echo "=== Stage 3: OpenROAD place and route ==="

        # Write TCL prologue with variables, then source generated script
        cat > pnr.tcl << OPENROAD_EOF
        set LIB_FILE "$LIB_FILE"
        set TECH_LEF "$TECH_LEF"
        set CELL_LEF_DIR "${libsRef}/lef"
        set SYNTH_V "${deviceName}_synth.v"
        set SDC_FILE "constraints.sdc"
        set DEVICE_NAME "${deviceName}"
        set SITE_NAME "${pdk.siteName}"
        set UTILIZATION ${toString coreUtilization}
        set CELL_LIB "${cellLib}"
        ${lib.optionalString (dieWidthUm != null && dieHeightUm != null) ''
          set DIE_AREA "0 0 ${toString dieWidthUm} ${toString dieHeightUm}"
        ''}
        source ${aegis-ip}/${deviceName}-openroad.tcl
        OPENROAD_EOF
        openroad -exit pnr.tcl > openroad.log 2>&1 || true

        # ================================================================
        # Stage 4: GDS generation via KLayout
        # ================================================================
        echo "=== Stage 4: GDS generation ==="

        if [ -f "${deviceName}_final.def" ]; then
          CELL_GDS=$(find ${libsRef}/gds -name '*.gds' | head -1)

          if [ -n "$CELL_GDS" ]; then
            CELL_GDS="$CELL_GDS" \
            DEF_FILE="${deviceName}_final.def" \
            OUT_GDS="${deviceName}.gds" \
            QT_QPA_PLATFORM=offscreen \
            klayout -b -r ${./scripts/def2gds.py} \
              > klayout.log 2>&1 || true

            # ================================================================
            # Stage 5: Render layout image
            # ================================================================
            if [ -f "${deviceName}.gds" ]; then
              echo "=== Stage 5: Render layout image ==="

              GDS_FILE="${deviceName}.gds" \
              OUT_PNG="${deviceName}_layout.png" \
              TOP_CELL_NAME="$TOP_MODULE" \
              QT_QPA_PLATFORM=offscreen \
              klayout -b -r ${./scripts/render_layout.py} \
                >> klayout.log 2>&1 || true
            fi
          else
            echo "Warning: No cell GDS found, skipping GDS generation"
          fi
        else
          echo "Warning: No DEF output from OpenROAD, skipping GDS generation"
        fi

        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall

        mkdir -p $out

        # Synthesis artifacts
        cp ${deviceName}_synth.v $out/ 2>/dev/null || true
        cp synth.ys $out/${deviceName}-yosys.tcl 2>/dev/null || true
        cp yosys.log $out/ 2>/dev/null || true
        cp constraints.sdc $out/ 2>/dev/null || true

        # PnR artifacts
        cp ${deviceName}_final.def $out/ 2>/dev/null || true
        cp ${deviceName}_final.v $out/ 2>/dev/null || true
        cp pnr.tcl $out/${deviceName}-openroad.tcl 2>/dev/null || true
        cp openroad.log $out/ 2>/dev/null || true
        cp timing.rpt $out/ 2>/dev/null || true
        cp area.rpt $out/ 2>/dev/null || true
        cp power.rpt $out/ 2>/dev/null || true

        # GDS for fab submission
        cp ${deviceName}.gds $out/ 2>/dev/null || true
        cp ${deviceName}_layout.png $out/ 2>/dev/null || true
        cp klayout.log $out/ 2>/dev/null || true

        # Source IP artifacts for reference
        cp ${aegis-ip}/${deviceName}.json $out/ 2>/dev/null || true
        cp ${aegis-ip}/${deviceName}-xschem.tcl $out/ 2>/dev/null || true
        cp ${aegis-ip}/${deviceName}-xschem.sch $out/ 2>/dev/null || true

        runHook postInstall
      '';

      passthru = {
        inherit
          pdk
          cellLib
          clockPeriodNs
          coreUtilization
          ;
        inherit (aegis-ip)
          deviceName
          width
          height
          tracks
          ;
        ip = aegis-ip;
        shell = mkShell {
          name = "aegis-tapeout-${aegis-ip.deviceName}-shell";

          packages = [
            yosys
            openroad
            xschem
            klayout
            magic-vlsi
            ngspice
            surfer
          ];

          PDK_NAME = pdk.pdkName;
          PDK_CELL_LIB = cellLib;
        };
      }
      // (args.passthru or { });
    };
}

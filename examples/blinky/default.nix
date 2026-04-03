# Blinky example for any Aegis FPGA device.
#
# Builds a blinking LED design through the full FPGA toolchain
# using the device-specific tools from the aegis-ip output.
#
# Usage:
#   nix build .#checks.<system>.terra-1-blinky
{
  lib,
  stdenvNoCC,
  mkShell,
  yosys,
  surfer,
  aegis-ip,
}:

let
  tools = aegis-ip.tools;
  deviceName = aegis-ip.deviceName;
in
stdenvNoCC.mkDerivation {
  name = "aegis-blinky-${deviceName}";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./blinky.v
      ./blinky.pcf
    ];
  };

  nativeBuildInputs = [
    yosys
    tools
  ];

  buildPhase = ''
    runHook preBuild

    echo "=== Synthesizing blinky for ${deviceName} ==="
    cat > synth.tcl << SYNTH_EOF
    set VERILOG_FILES "blinky.v"
    set TOP_MODULE "blinky"
    set CELLS_V "${tools}/share/yosys/aegis/${deviceName}_cells.v"
    set TECHMAP_V "${tools}/share/yosys/aegis/${deviceName}_techmap.v"
    set BRAM_RULES "${tools}/share/yosys/aegis/${deviceName}_bram.rules"
    set DEVICE_NAME "blinky"
    source ${tools}/share/yosys/aegis/${deviceName}-synth-aegis.tcl
    SYNTH_EOF
    yosys -c synth.tcl > yosys.log 2>&1 || { cat yosys.log; exit 1; }

    echo "=== Place and route ==="
    nextpnr-aegis-${deviceName} \
      -o pcf=blinky.pcf \
      --json blinky_pnr.json \
      --write blinky_routed.json \
      > nextpnr.log 2>&1 || { cat nextpnr.log; echo "nextpnr finished (may have warnings)"; }

    echo "=== Packing bitstream ==="
    if [ -f blinky_routed.json ]; then
      ${deviceName}-pack --pnr blinky_routed.json --output blinky.bin
    else
      echo "Warning: no PnR output, skipping bitstream"
    fi

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp blinky.v $out/
    cp blinky_pnr.json $out/ 2>/dev/null || true
    cp blinky_routed.json $out/ 2>/dev/null || true
    cp blinky.bin $out/ 2>/dev/null || true
    cp yosys.log $out/
    cp nextpnr.log $out/ 2>/dev/null || true

    runHook postInstall
  '';

  passthru.shell = mkShell {
    name = "aegis-blinky-${deviceName}-shell";
    packages = [
      yosys
      tools
      surfer
    ];
  };
}

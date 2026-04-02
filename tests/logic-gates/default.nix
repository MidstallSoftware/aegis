# Combinational logic gates test.
#
# Verifies AND, OR, XOR, NOT LUT configurations by checking
# that the toolchain (synth + PnR + pack) completes successfully.
{
  lib,
  stdenvNoCC,
  yosys,
  aegis-ip,
  aegis-pack,
  aegis-sim,
}:

let
  tools = aegis-ip.tools;
  deviceName = aegis-ip.deviceName;
in
stdenvNoCC.mkDerivation {
  name = "aegis-logic-gates-${deviceName}";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./gates.v
      ./gates.pcf
    ];
  };

  nativeBuildInputs = [
    yosys
    tools
    aegis-pack
    aegis-sim
  ];

  buildPhase = ''
    runHook preBuild

    echo "=== Synthesizing logic gates ==="
    cat > synth.tcl << SYNTH_EOF
    set VERILOG_FILES "gates.v"
    set TOP_MODULE "gates"
    set CELLS_V "${tools}/share/yosys/aegis/${deviceName}_cells.v"
    set TECHMAP_V "${tools}/share/yosys/aegis/${deviceName}_techmap.v"
    set BRAM_RULES "${tools}/share/yosys/aegis/${deviceName}_bram.rules"
    set DEVICE_NAME "gates"
    source ${tools}/share/yosys/aegis/${deviceName}-synth-aegis.tcl
    SYNTH_EOF
    yosys -c synth.tcl > yosys.log 2>&1 || { cat yosys.log; exit 1; }

    echo "=== Place and route ==="
    nextpnr-aegis-${deviceName} \
      -o pcf=gates.pcf \
      --json gates_pnr.json \
      --write gates_routed.json \
      > nextpnr.log 2>&1 || { cat nextpnr.log; exit 1; }

    echo "=== Packing bitstream ==="
    aegis-pack \
      --descriptor ${aegis-ip}/${deviceName}.json \
      --pnr gates_routed.json \
      --output gates.bin

    echo "=== Simulating ==="
    aegis-sim \
      --descriptor ${aegis-ip}/${deviceName}.json \
      --bitstream gates.bin \
      --monitor-pin w2,w3,w4,w5 \
      --cycles 10 \
      2>&1 | tee sim.log

    if grep -q "Simulation complete" sim.log; then
      echo "PASS: Logic gates toolchain completed"
    else
      echo "FAIL: Simulation did not complete"
      exit 1
    fi

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp sim.log $out/
    cp gates.bin $out/
    echo "PASS" > $out/result
    runHook postInstall
  '';
}

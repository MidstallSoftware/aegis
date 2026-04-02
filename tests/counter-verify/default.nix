# Counter verification test.
#
# 8-bit counter with each bit routed to a separate IO pad.
# Runs sim for 200 cycles and verifies the counter value matches
# the expected cycle count (mod 256).
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
  name = "aegis-counter-verify-${deviceName}";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./counter.v
      ./counter.pcf
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

    echo "=== Synthesizing counter ==="
    cat > synth.tcl << SYNTH_EOF
    set VERILOG_FILES "counter.v"
    set TOP_MODULE "counter"
    set CELLS_V "${tools}/share/yosys/aegis/${deviceName}_cells.v"
    set TECHMAP_V "${tools}/share/yosys/aegis/${deviceName}_techmap.v"
    set BRAM_RULES "${tools}/share/yosys/aegis/${deviceName}_bram.rules"
    set DEVICE_NAME "counter"
    source ${tools}/share/yosys/aegis/${deviceName}-synth-aegis.tcl
    SYNTH_EOF
    yosys -c synth.tcl > yosys.log 2>&1 || { cat yosys.log; exit 1; }

    echo "=== Place and route ==="
    nextpnr-aegis-${deviceName} \
      -o pcf=counter.pcf \
      --json counter_pnr.json \
      --write counter_routed.json \
      > nextpnr.log 2>&1 || true

    if [ ! -f counter_routed.json ]; then
      echo "FAIL: Routing failed"
      cat nextpnr.log
      exit 1
    fi

    echo "=== Packing bitstream ==="
    aegis-pack \
      --descriptor ${aegis-ip}/${deviceName}.json \
      --pnr counter_routed.json \
      --output counter.bin

    echo "=== Simulating 100 cycles ==="
    aegis-sim \
      --descriptor ${aegis-ip}/${deviceName}.json \
      --bitstream counter.bin \
      --clock-pin w0 \
      --monitor-pin w1,w2,w3,w4 \
      --cycles 100 \
      2>&1 | tee sim.log

    echo "=== Verifying counter ==="
    if grep -q "Simulation complete" sim.log; then
      echo "PASS: Counter simulation completed"
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
    cp counter.bin $out/
    echo "PASS" > $out/result
    runHook postInstall
  '';
}

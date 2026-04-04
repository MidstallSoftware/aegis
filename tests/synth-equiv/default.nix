# Synthesis equivalence checking with SymbiYosys.
#
# Proves that Yosys synthesis preserves functional behavior by comparing
# the original Verilog design against the synthesized netlist using
# formal equivalence checking (SAT-based).
{
  lib,
  stdenvNoCC,
  yosys,
  sby,
  z3,
  aegis-ip,
  design ? "comb",
}:

let
  inherit (aegis-ip) tools deviceName;
in
stdenvNoCC.mkDerivation {
  name = "aegis-synth-equiv-${design}-${deviceName}";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./${design}.v
      ./cells_sim.v
    ];
  };

  nativeBuildInputs = [
    yosys
    sby
    z3
    tools
  ];

  buildPhase = ''
    runHook preBuild

    echo "=== Synthesis equivalence check: ${design} ==="

    # Step 1: Synthesize the design with the Aegis techmap
    cat > synth.tcl << SYNTH_EOF
    set VERILOG_FILES "${design}.v"
    set TOP_MODULE "${design}"
    set CELLS_V "${tools}/share/yosys/aegis/${deviceName}_cells.v"
    set TECHMAP_V "${tools}/share/yosys/aegis/${deviceName}_techmap.v"
    set BRAM_RULES "${tools}/share/yosys/aegis/${deviceName}_bram.rules"
    set DEVICE_NAME "${design}_synth"
    source ${tools}/share/yosys/aegis/${deviceName}-synth-aegis.tcl
    SYNTH_EOF
    yosys -c synth.tcl > yosys.log 2>&1 || { cat yosys.log; exit 1; }

    echo "=== Running formal equivalence check ==="

    # Step 2: Run equivalence check directly in Yosys
    cat > equiv.ys << EQUIV_EOF
    read_verilog -formal ${design}.v
    proc
    memory
    flatten
    rename ${design} gold

    read_json ${design}_synth_pnr.json
    read_verilog cells_sim.v
    rename ${design} gate

    equiv_make gold gate equiv
    hierarchy -top equiv
    equiv_simple
    equiv_struct
    equiv_induct 5
    equiv_status -assert
    EQUIV_EOF

    # List files available for equiv check
    echo "Files in working directory:"
    ls -la *.v *.json 2>/dev/null || true

    yosys equiv.ys 2>&1 | tee equiv.log
    RESULT=$?

    if [ $RESULT -eq 0 ]; then
      echo "PASS: Synthesis equivalence verified for ${design}"
    else
      echo "FAIL: Synthesis equivalence check failed for ${design}"
      exit 1
    fi

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp sby.log $out/ 2>/dev/null || true
    echo "PASS" > $out/result
    runHook postInstall
  '';
}

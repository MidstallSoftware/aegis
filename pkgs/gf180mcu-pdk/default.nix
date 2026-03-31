{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
}:

let
  # Standard cell library (7-track, 5V)
  fd_sc_mcu7t5v0 = fetchFromGitHub {
    owner = "google";
    repo = "globalfoundries-pdk-libs-gf180mcu_fd_sc_mcu7t5v0";
    rev = "43beb45e4d323a76239de436db2df6732e9a689b";
    hash = "sha256-wmXGAUwXbz4TyeIRQZhnspIaNw0G3+tYdIrUIr8XAgw=";
  };

  # PVT corners to generate merged liberty files for
  corners = [
    "ff_125C_1v98"
    "ff_125C_3v60"
    "ff_125C_5v50"
    "ff_n40C_1v98"
    "ff_n40C_3v60"
    "ff_n40C_5v50"
    "ss_125C_1v62"
    "ss_125C_3v00"
    "ss_125C_4v50"
    "ss_n40C_1v62"
    "ss_n40C_3v00"
    "ss_n40C_4v50"
    "tt_025C_1v80"
    "tt_025C_3v30"
    "tt_025C_5v00"
  ];
in
stdenvNoCC.mkDerivation {
  pname = "gf180mcu-pdk";
  version = "0-unstable-2025-03-31";

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    local sc=$out/share/pdk/gf180mcu/libs.ref/gf180mcu_fd_sc_mcu7t5v0
    mkdir -p $sc/{lib,lef,gds,verilog,spice}

    # Merge per-cell liberty files into single .lib per PVT corner
    ${lib.concatMapStringsSep "\n" (corner: ''
      echo "Merging liberty for corner: ${corner}"
      local header="${fd_sc_mcu7t5v0}/liberty/gf180mcu_fd_sc_mcu7t5v0__${corner}.lib"
      local merged="$sc/lib/gf180mcu_fd_sc_mcu7t5v0__${corner}.lib"

      # Copy header, remove trailing closing brace
      sed '$ d' "$header" > "$merged"

      # Append all per-cell liberty fragments for this corner
      find ${fd_sc_mcu7t5v0}/cells -name "*__${corner}.lib" -print0 | sort -z | xargs -0 cat >> "$merged"

      # Close the library block
      echo "}" >> "$merged"
    '') corners}

    # Tech LEF files
    cp ${fd_sc_mcu7t5v0}/tech/*.lef $sc/lef/

    find ${fd_sc_mcu7t5v0}/cells -name '*.lef' -exec cp -n {} $sc/lef/ \;
    find ${fd_sc_mcu7t5v0}/cells -name '*.gds' -exec cp -n {} $sc/gds/ \;
    find ${fd_sc_mcu7t5v0}/cells -name '*.behavioral.v' -exec cp -n {} $sc/verilog/ \;
    find ${fd_sc_mcu7t5v0}/cells -name '*.spice' -exec cp -n {} $sc/spice/ \;

    # Simulation models
    if [ -d "${fd_sc_mcu7t5v0}/models" ]; then
      mkdir -p $out/share/pdk/gf180mcu/models
      cp -r ${fd_sc_mcu7t5v0}/models/* $out/share/pdk/gf180mcu/models/
    fi

    runHook postInstall
  '';

  passthru = {
    cellLib = "gf180mcu_fd_sc_mcu7t5v0";
    siteName = "GF018hv5v_mcu_sc7";
    pdkName = "gf180mcu";
    pdkPath = "share/pdk/gf180mcu";
  };

  meta = {
    description = "GlobalFoundries GF180MCU 180nm PDK standard cell library";
    homepage = "https://github.com/google/gf180mcu-pdk";
    license = lib.licenses.asl20;
    platforms = lib.platforms.all;
  };
}

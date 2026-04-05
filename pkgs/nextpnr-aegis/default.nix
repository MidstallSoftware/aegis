{
  nextpnr,
}:

nextpnr.overrideAttrs (old: {
  pname = "nextpnr-aegis";

  # Only build the generic architecture (which includes our Aegis viaduct)
  cmakeFlags =
    builtins.map (flag: if builtins.match ".*-DARCH=.*" flag != null then "-DARCH=generic" else flag)
      (
        builtins.filter (
          flag:
          # Remove flags for architectures we don't build
          builtins.match ".*ICESTORM.*" flag == null
          && builtins.match ".*TRELLIS.*" flag == null
          && builtins.match ".*HIMBAECHEL.*" flag == null
          && builtins.match ".*GOWIN.*" flag == null
          && builtins.match ".*BEYOND.*" flag == null
        ) (old.cmakeFlags or [ ])
      );

  postPatch = (old.postPatch or "") + ''
    # Add Aegis viaduct uarch
    mkdir -p generic/viaduct/aegis
    cp ${../../nextpnr-aegis/aegis.cc} generic/viaduct/aegis/aegis.cc
    cp ${../../nextpnr-aegis/aegis_test.cc} generic/viaduct/aegis/aegis_test.cc

    # Register uarch source in CMakeLists.txt
    sed -i '/viaduct\/example\/example.cc/a\    viaduct/aegis/aegis.cc' generic/CMakeLists.txt

    # Register test source in CMakeLists.txt
    sed -i 's|add_nextpnr_architecture(''${family}|set(AEGIS_TEST_SOURCES viaduct/aegis/aegis_test.cc)\nadd_nextpnr_architecture(''${family}|' generic/CMakeLists.txt
    sed -i 's|MAIN_SOURCE  main.cc|TEST_SOURCES ''${AEGIS_TEST_SOURCES}\n    MAIN_SOURCE  main.cc|' generic/CMakeLists.txt
  '';
})

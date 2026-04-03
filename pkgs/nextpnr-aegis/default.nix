{
  nextpnr,
  aegisSrc ? ../..,
}:

nextpnr.overrideAttrs (old: {
  pname = "nextpnr-aegis";
  postPatch = (old.postPatch or "") + ''
    # Add Aegis viaduct uarch
    mkdir -p generic/viaduct/aegis
    cp ${aegisSrc}/nextpnr-aegis/aegis.cc generic/viaduct/aegis/aegis.cc
    cp ${aegisSrc}/nextpnr-aegis/aegis_test.cc generic/viaduct/aegis/aegis_test.cc

    # Register uarch source in CMakeLists.txt
    sed -i '/viaduct\/example\/example.cc/a\    viaduct/aegis/aegis.cc' generic/CMakeLists.txt

    # Register test source in CMakeLists.txt
    sed -i 's|add_nextpnr_architecture(''${family}|set(AEGIS_TEST_SOURCES viaduct/aegis/aegis_test.cc)\nadd_nextpnr_architecture(''${family}|' generic/CMakeLists.txt
    sed -i 's|MAIN_SOURCE  main.cc|TEST_SOURCES ''${AEGIS_TEST_SOURCES}\n    MAIN_SOURCE  main.cc|' generic/CMakeLists.txt
  '';
})

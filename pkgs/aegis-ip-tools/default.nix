{
  lib,
  callPackage,
  flakever,
  mkShell,
  buildDartApplication,
  yq,
  dart,
}:
let
  shell = mkShell {
    name = "aegis-ip-tools-dev-shell";

    packages = [
      dart
      yq
    ];
  };
in
buildDartApplication (finalAttrs: {
  pname = "aegis-ip-tools";
  inherit (flakever) version;

  src = lib.fileset.toSource {
    root = ../../ip;
    fileset = lib.fileset.unions [
      ../../ip/bin
      ../../ip/data
      ../../ip/lib
      ../../ip/test
      ../../ip/pubspec.lock
      ../../ip/pubspec.yaml
    ];
  };

  pubspecLock = lib.importJSON ../../ip/pubspec.lock.json;

  dartEntryPoints = {
    "bin/aegis-genip" = "bin/aegis_genip.dart";
    "bin/aegis-sim" = "bin/aegis_sim.dart";
  };

  doCheck = true;

  checkPhase = ''
    runHook preCheck
    packageRun test -r expanded
    runHook postCheck
  '';

  postInstall = ''
    mkdir -p $out/share/aegis-ip
    cp data/descriptor.schema.json $out/share/aegis-ip/
  '';

  passthru = {
    inherit shell;
    mkIp = callPackage ../aegis-ip { aegis-ip-tools = finalAttrs.finalPackage; };
  };
})

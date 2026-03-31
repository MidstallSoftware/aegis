{
  lib,
  craneLib,
}:

let
  src = lib.fileset.toSource {
    root = ../..;
    fileset = lib.fileset.unions [
      ../../Cargo.toml
      ../../Cargo.lock
      ../../crates
      ../../ip/data/descriptor.schema.json
    ];
  };

  commonArgs = {
    inherit src;
    pname = "aegis-pack";
    strictDeps = true;
    cargoExtraArgs = "--package aegis-pack";
  };

  cargoArtifacts = craneLib.buildDepsOnly commonArgs;
in
craneLib.buildPackage (
  commonArgs
  // {
    inherit cargoArtifacts;

    meta = {
      description = "Bitstream packer for Aegis FPGA";
      mainProgram = "aegis-pack";
    };
  }
)

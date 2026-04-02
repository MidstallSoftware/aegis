{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    flake-parts.url = "github:hercules-ci/flake-parts";
    flakever.url = "github:numinit/flakever";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    crane.url = "github:ipetkov/crane";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-parts,
      flakever,
      treefmt-nix,
      crane,
      ...
    }@inputs:
    let
      flakeverConfig = flakever.lib.mkFlakever {
        inherit inputs;

        digits = [
          1
          2
          2
        ];
      };
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.flake-parts.flakeModules.easyOverlay
        inputs.treefmt-nix.flakeModule
      ];

      flake.versionTemplate = "1.1pre-<lastModifiedDate>-<rev>";

      systems = [
        "aarch64-linux"
        "x86_64-linux"
      ];

      perSystem =
        {
          system,
          pkgs,
          ...
        }:
        let
          inherit (pkgs) lib;
          craneLib = crane.mkLib pkgs;
        in
        {
          _module.args.pkgs = import inputs.nixpkgs {
            inherit system;
            overlays = [
              self.overlays.default
            ];
          };

          treefmt.programs = {
            black.enable = true;
            clang-format.enable = true;
            dart-format.enable = true;
            jsonfmt.enable = true;
            nixfmt.enable = true;
            rustfmt.enable = true;
          };

          legacyPackages = pkgs;

          overlayAttrs = {
            flakever = flakeverConfig;
            aegis-ip-tools = pkgs.callPackage ./pkgs/aegis-ip-tools { };
            aegis-pack = pkgs.callPackage ./pkgs/aegis-pack { inherit craneLib; };
            aegis-sim = pkgs.callPackage ./pkgs/aegis-sim { inherit craneLib; };
            nextpnr-aegis = pkgs.callPackage ./pkgs/nextpnr-aegis { };
            gf180mcu-pdk = pkgs.callPackage ./pkgs/gf180mcu-pdk { };
            sky130-pdk = pkgs.callPackage ./pkgs/sky130-pdk { };
          };

          packages = {
            default = pkgs.aegis-ip-tools;
            ip-tools = pkgs.aegis-ip-tools;
            terra-1 = pkgs.aegis-ip-tools.mkIp {
              deviceName = "terra_1";
              width = 48;
              height = 64;
              tracks = 4;
              serdesCount = 4;
              bramColumnInterval = 16;
              dspColumnInterval = 24;
              clockTileCount = 2;
            };
            terra-1-tapeout = self.packages.${system}.terra-1.mkTapeout {
              pdk = pkgs.gf180mcu-pdk;
              clockPeriodNs = 20;
            };
          };

          checks =
            let
              terra-1 = self.packages.${system}.terra-1;
            in
            {
              terra-1-blinky = pkgs.callPackage ./examples/blinky {
                aegis-ip = terra-1;
              };
              terra-1-blinky-sim = pkgs.callPackage ./tests/blinky-sim {
                aegis-ip = terra-1;
              };
              terra-1-counter = pkgs.callPackage ./tests/counter-verify {
                aegis-ip = terra-1;
              };
              terra-1-shift-register = pkgs.callPackage ./tests/shift-register {
                aegis-ip = terra-1;
              };
              terra-1-logic-gates = pkgs.callPackage ./tests/logic-gates {
                aegis-ip = terra-1;
              };
            };

          devShells = {
            default = pkgs.aegis-ip-tools.shell;
            ip-tools = pkgs.aegis-ip-tools.shell;
            terra-1 = self.packages.${system}.terra-1.shell;
            terra-1-tapeout = self.packages.${system}.terra-1-tapeout.shell;
            terra-1-blinky = self.checks.${system}.terra-1-blinky.shell;
          };
        };
    };
}

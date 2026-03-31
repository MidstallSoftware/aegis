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

          checks = {
            terra-1-blinky = pkgs.callPackage ./examples/blinky {
              aegis-ip = self.packages.${system}.terra-1;
            };
          };

          devShells = {
            default = pkgs.aegis-ip-tools.shell;
            ip-tools = pkgs.aegis-ip-tools.shell;
          };
        };
    };
}

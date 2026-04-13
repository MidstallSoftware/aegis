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
        "aarch64-darwin"
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
            athena = pkgs.callPackage ./pkgs/athena { inherit craneLib; };
            athena-cosmic = pkgs.callPackage ./pkgs/athena {
              inherit craneLib;
              enableCosmic = true;
            };
            nextpnr-aegis = pkgs.callPackage ./pkgs/nextpnr-aegis { };
            gf180mcu-pdk = pkgs.callPackage ./pkgs/gf180mcu-pdk { };
            sky130-pdk = pkgs.callPackage ./pkgs/sky130-pdk { };
          };

          packages =
            let
              devices = import ./devices.nix {
                inherit (pkgs) aegis-ip-tools gf180mcu-pdk sky130-pdk;
              };

              mkDevicePackages = name: cfg: {
                "${name}" = cfg.ip;
                "${name}-tapeout" = cfg.ip.mkTapeout cfg.tapeout;
                "${name}-deb" = cfg.ip.deb;
                "${name}-docker" = cfg.ip.docker;
              };
            in
            {
              default = pkgs.aegis-ip-tools;
              ip-tools = pkgs.aegis-ip-tools;
              athena = pkgs.athena.override {
                dataPacks = [ self.packages.${system}.terra-1 ];
              };
              athena-cosmic = pkgs.athena-cosmic.override {
                dataPacks = [ self.packages.${system}.terra-1 ];
              };
              athena-deb = self.packages.${system}.athena.passthru.deb;
            }
            // lib.foldl' (acc: name: acc // mkDevicePackages name devices.${name}) { } (
              builtins.attrNames devices
            );

          checks =
            let
              devices = builtins.filter (
                name:
                let
                  pkg = self.packages.${system}.${name};
                in
                pkg ? deviceName && !(pkg ? tileMacros)
              ) (builtins.attrNames self.packages.${system});
              mkDeviceChecks =
                name:
                let
                  ip = self.packages.${system}.${name};
                  tapeout = self.packages.${system}."${name}-tapeout";
                in
                {
                  "${name}-blinky" = pkgs.callPackage ./examples/blinky {
                    aegis-ip = ip;
                  };
                  "${name}-blinky-sim" = pkgs.callPackage ./tests/blinky-sim {
                    aegis-ip = ip;
                  };
                  "${name}-counter" = pkgs.callPackage ./tests/counter-verify {
                    aegis-ip = ip;
                  };
                  "${name}-shift-register" = pkgs.callPackage ./tests/shift-register {
                    aegis-ip = ip;
                  };
                  "${name}-logic-gates" = pkgs.callPackage ./tests/logic-gates {
                    aegis-ip = ip;
                  };
                  "${name}-tile-bits" = pkgs.callPackage ./tests/tile-bits-consistency {
                    aegis-ip = ip;
                  };
                  "${name}-synth-equiv-comb" = pkgs.callPackage ./tests/synth-equiv {
                    aegis-ip = ip;
                    design = "comb";
                  };
                  "${name}-synth-equiv-counter" = pkgs.callPackage ./tests/synth-equiv {
                    aegis-ip = ip;
                    design = "counter";
                  };
                  "${name}-formal-ip" = pkgs.callPackage ./tests/formal-ip {
                    aegis-ip = ip;
                  };
                  "${name}-gds-verify" = pkgs.callPackage ./tests/gds-verify {
                    aegis-tapeout = tapeout;
                  };
                };
            in
            lib.foldl' (acc: name: acc // mkDeviceChecks name) { } devices;

          devShells =
            let
              devices = builtins.filter (
                name:
                let
                  pkg = self.packages.${system}.${name};
                in
                pkg ? deviceName && !(pkg ? tileMacros)
              ) (builtins.attrNames self.packages.${system});
              mkDeviceShells = name: {
                "${name}" = self.packages.${system}.${name}.shell;
                "${name}-tapeout" = self.packages.${system}."${name}-tapeout".shell;
                "${name}-blinky" = self.checks.${system}."${name}-blinky".shell;
              };
            in
            {
              default = pkgs.aegis-ip-tools.shell;
              ip-tools = pkgs.aegis-ip-tools.shell;
              athena = pkgs.athena.shell;
            }
            // lib.foldl' (acc: name: acc // mkDeviceShells name) { } devices;
        };
    };
}

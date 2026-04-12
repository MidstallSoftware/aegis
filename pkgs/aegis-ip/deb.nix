{
  lib,
  stdenvNoCC,
  dpkg,
  patchelf,
  removeReferencesTo,
  aegis-ip,
  aegis-ip-tools,
  aegis-pack,
  aegis-sim,
  nextpnr-aegis,
}:

let
  inherit (aegis-ip) deviceName;

  system = stdenvNoCC.hostPlatform.system;

  archMap = {
    "x86_64-linux" = {
      deb = "amd64";
      interpreter = "/lib64/ld-linux-x86-64.so.2";
      libDir = "/usr/lib/x86_64-linux-gnu";
    };
    "aarch64-linux" = {
      deb = "arm64";
      interpreter = "/lib/ld-linux-aarch64.so.1";
      libDir = "/usr/lib/aarch64-linux-gnu";
    };
  };

  arch = archMap.${system};

  version = aegis-ip-tools.version;

  # Debian package names only allow lowercase alphanums, '+', '-', and '.'
  debName = builtins.replaceStrings [ "_" ] [ "-" ] deviceName;

  patchBinary = bin: name: ''
    cp ${bin}/bin/${name} $pkg/usr/bin/${name}
    chmod u+w $pkg/usr/bin/${name}
    patchelf --set-interpreter ${arch.interpreter} $pkg/usr/bin/${name}
    patchelf --set-rpath ${arch.libDir} $pkg/usr/bin/${name}
    remove-references-to -t ${bin} $pkg/usr/bin/${name}
  '';
in

stdenvNoCC.mkDerivation {
  pname = "aegis-${deviceName}-deb";
  inherit version;

  dontUnpack = true;
  dontConfigure = true;

  nativeBuildInputs = [
    dpkg
    patchelf
    removeReferencesTo
  ];

  allowedReferences = [ ];

  buildPhase = ''
    runHook preBuild

    pkg=$TMPDIR/pkg
    mkdir -p $pkg/DEBIAN
    mkdir -p $pkg/usr/bin
    mkdir -p $pkg/usr/share/aegis/${deviceName}
    mkdir -p $pkg/usr/share/yosys/aegis

    # DEBIAN/control
    cat > $pkg/DEBIAN/control <<CONTROL
    Package: aegis-${debName}
    Version: ${version}
    Architecture: ${arch.deb}
    Maintainer: Midstall <info@midstall.com>
    Description: Aegis FPGA toolchain for ${deviceName}
     Place-and-route, bitstream packer, cycle-accurate simulator,
     and device support files for the Aegis ${deviceName} FPGA.
    Depends: libc6, libstdc++6, libboost-filesystem-dev | libboost-filesystem1.83.0, libboost-program-options-dev | libboost-program-options1.83.0, libboost-thread-dev | libboost-thread1.83.0, python3
    Priority: optional
    Section: electronics
    CONTROL

    # Strip leading whitespace from control file (heredoc indentation)
    sed -i 's/^    //' $pkg/DEBIAN/control

    # Patch and install ELF binaries
    ${patchBinary aegis-pack "aegis-pack"}
    ${patchBinary aegis-sim "aegis-sim"}
    ${patchBinary nextpnr-aegis "nextpnr-generic"}

    # Remove references to the other Nix store inputs
    for bin in $pkg/usr/bin/*; do
      remove-references-to -t ${aegis-pack} "$bin"
      remove-references-to -t ${aegis-sim} "$bin"
      remove-references-to -t ${nextpnr-aegis} "$bin"
      remove-references-to -t ${aegis-ip} "$bin"
    done

    # Device-specific wrapper scripts
    cat > $pkg/usr/bin/${deviceName}-sim <<'WRAPPER'
    #!/bin/sh
    exec /usr/bin/aegis-sim --descriptor /usr/share/aegis/${deviceName}/${deviceName}.json "$@"
    WRAPPER

    cat > $pkg/usr/bin/${deviceName}-pack <<'WRAPPER'
    #!/bin/sh
    exec /usr/bin/aegis-pack --descriptor /usr/share/aegis/${deviceName}/${deviceName}.json "$@"
    WRAPPER

    cat > $pkg/usr/bin/nextpnr-aegis-${deviceName} <<'WRAPPER'
    #!/bin/sh
    exec /usr/bin/nextpnr-generic --uarch aegis -o device=${toString aegis-ip.width}x${toString aegis-ip.height}t${toString aegis-ip.tracks} "$@"
    WRAPPER

    # Strip heredoc indentation and set executable
    for wrapper in $pkg/usr/bin/${deviceName}-sim $pkg/usr/bin/${deviceName}-pack $pkg/usr/bin/nextpnr-aegis-${deviceName}; do
      sed -i 's/^    //' "$wrapper"
      chmod +x "$wrapper"
    done

    # Install device data files
    for f in ${deviceName}.json ${deviceName}.sv ${deviceName}_cells.v ${deviceName}_techmap.v ${deviceName}-synth-aegis.tcl; do
      if [ -f ${aegis-ip}/$f ]; then
        cp ${aegis-ip}/$f $pkg/usr/share/aegis/${deviceName}/
        remove-references-to -t ${aegis-ip} $pkg/usr/share/aegis/${deviceName}/$f
      fi
    done

    # BRAM rules (optional)
    if [ -f ${aegis-ip}/${deviceName}_bram.rules ]; then
      cp ${aegis-ip}/${deviceName}_bram.rules $pkg/usr/share/aegis/${deviceName}/
    fi

    # Symlink EDA files for Yosys discoverability
    for f in $pkg/usr/share/aegis/${deviceName}/${deviceName}_cells.v \
             $pkg/usr/share/aegis/${deviceName}/${deviceName}_techmap.v \
             $pkg/usr/share/aegis/${deviceName}/${deviceName}-synth-aegis.tcl; do
      if [ -f "$f" ]; then
        ln -s ../aegis/${deviceName}/$(basename "$f") $pkg/usr/share/yosys/aegis/
      fi
    done
    if [ -f $pkg/usr/share/aegis/${deviceName}/${deviceName}_bram.rules ]; then
      ln -s ../aegis/${deviceName}/${deviceName}_bram.rules $pkg/usr/share/yosys/aegis/
    fi

    # Build the .deb
    dpkg-deb --build $pkg $TMPDIR/aegis-${debName}_${version}_${arch.deb}.deb

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    cp $TMPDIR/aegis-${debName}_${version}_${arch.deb}.deb $out
    runHook postInstall
  '';
}

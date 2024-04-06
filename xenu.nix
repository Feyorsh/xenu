{
  lib,
  stdenv,
  darwin,
  runCommand,
}:
let
  # see https://github.com/NixOS/nixpkgs/blob/ff0dbd94265ac470dda06a657d5fe49de93b4599/pkgs/applications/editors/vim/macvim.nix
  buildSymlinks = runCommand "xenu-build-symlinks" {} ''
    mkdir -p $out/bin
    ln -s /usr/bin/swiftc $out/bin
  '';
in stdenv.mkDerivation {
  pname = "xenu";
  version = "0.0.1";
  src = ./xenu;
  # we need to wait for MacOS SDK >= 14 to be added to nixpkgs; in the future, you may not need xcode to build this (yay!)
  # nativeBuildInputs = [ swift ];  <-- uses apple_sdk_11, would need to be overridden
  # buildInputs = [ darwin.apple_sdk_14_0.frameworks.Foundation darwin.apple_sdk_14_0.frameworks.Virtualization ];
  nativeBuildInputs = [ buildSymlinks darwin.xcode_15_1 darwin.sigtool ];

  buildPhase = ''
    runHook preBuild
    swiftc $src/main.swift
    codesign -f --entitlements $src/xenu.entitlements -s - ./main
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    mv main $out/bin/xenu
    runHook postInstall
  '';

  # necessary for keeping entitlements
  dontStrip = true;

  sandboxProfile = ''
    (allow file-read* file-write* process-exec mach-lookup)
    ; block homebrew dependencies
    (deny file-read* file-write* process-exec mach-lookup (subpath "/usr/local") (with no-log))
  '';

  meta = with lib; {
    description = "Command line interface to Apple Virtualization";
    homepage = "https://github.com/Feyorsh/xenu";
    license = licenses.gpl3;
    maintainers = [ ];
    platforms = platforms.darwin;
    hydraPlatforms = [];
  };
}

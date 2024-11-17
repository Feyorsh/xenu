{ lib
, stdenv
, fetchFromGitHub
, fetchurl
, sigtool
, swift
, swiftpm
, swiftpm2nix
, swiftPackages
, apple-sdk_13
, darwinMinVersionHook
}:
let
  generated = swiftpm2nix.helpers ./generated;
in
swiftPackages.stdenv.mkDerivation (finalAttrs: {
  pname = "xenu";
  version = "0.0.4";

  src = ./.;

  strictDeps = true;

  nativeBuildInputs = [
    swift
    swiftpm
    sigtool
  ];

  buildInputs = [
    apple-sdk_13
    (darwinMinVersionHook "13.0")
  ];

  configurePhase = generated.configure;

  swiftpmBuildConfig = "debug";
  swiftpmFlags = [
    "--disable-package-manifest-caching"
  ];

  installPhase = ''
    runHook preInstall

    binPath="$(swiftpmBinPath)"
    install -Dm755 "$(swiftpmBinPath)/xenu" -t $out/bin
    codesign --force --entitlements ./Resources/Xenu.entitlements --sign - $out/bin/xenu

    runHook postInstall
  '';

  # necessary to keep entitlements
  dontStrip = true;

  meta = with lib; {
    description = "Command line interface to Apple Virtualization";
    homepage = "https://github.com/Feyorsh/xenu";
    license = licenses.gpl3;
    mainProgram = "xenu";
    platforms = platforms.darwin;
  };
})

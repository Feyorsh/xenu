{ lib
, stdenv
, fetchFromGitHub
, fetchurl
, swift
, swiftpm
, swiftpm2nix
, swiftPackages
, Virtualization
, Foundation
}:
let
  generated = swiftpm2nix.helpers ./generated;
in
swiftPackages.stdenv.mkDerivation (finalAttrs: {
  pname = "xenu";
  version = "0.0.2";

  # TODO make this the flake's self input?
  src = ./.;

  nativeBuildInputs = [ swift swiftpm ];

  # TODO this needs the newer version of the macOS sdk that landed in nixpkgs a few months ago
  buildInputs = [ Foundation Virtualization ];

  configurePhase = generated.configure;

  # installPhase = ''
  #   runHook preInstall
  #   install -Dm755 .build/${stdenv.hostPlatform.darwinArch}-apple-macosx/release/dockutil -t $out/bin
  #   runHook postInstall
  # '';
  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp $swiftpmBinPath/xenu $out/bin/

    runHook postInstall
  '';

  meta = with lib; {
    description = "Command line interface to Apple Virtualization";
    homepage = "https://github.com/Feyorsh/xenu";
    license = licenses.gpl3;
    mainProgram = "xenu";
    platforms = platforms.darwin;
  };
})

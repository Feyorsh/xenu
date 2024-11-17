{ lib
, stdenv
, fetchFromGitHub
, fetchurl
, swift
, swiftpm
, swiftpm2nix
, swiftPackages
, apple-sdk_15
}:
let
  generated = swiftpm2nix.helpers ./generated;
in
swiftPackages.stdenv.mkDerivation (finalAttrs: {
  pname = "xenu";
  version = "0.0.2";

  src = ./.;

  nativeBuildInputs = [ swift swiftpm ];

  # preBuild = ''
  #   ${darwin.xcode_15_1}/Contents/Developer/usr/bin/xcodebuild -sdk -version
  #   env
  # '';

  buildInputs = [
    apple-sdk_15 # TODO could go lower to 13, iirc there's a hook?
  ];

  configurePhase = generated.configure;

  # TODO think this installPhase is unnecessary
  installPhase = ''
    runHook preInstall
    install -Dm755 .build/${swiftPackages.stdenv.hostPlatform.darwinArch}-apple-macosx/release/xenu -t $out/bin
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

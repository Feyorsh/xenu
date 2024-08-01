# Rosetta landed in virt.fw in SDK version 13, and currently only 12 is in nixpkgs. Use the system version for now
# { lib
# , stdenv
# , fetchFromGitHub
# , fetchurl
# , swift
# , swiftpm
# , swiftpm2nix
# , swiftPackages
# # , Virtualization
# # , Foundation
# , darwin
# }:
# let
#   generated = swiftpm2nix.helpers ./generated;
# in
# swiftPackages.stdenv.mkDerivation (finalAttrs: {
#   pname = "xenu";
#   version = "0.0.2";

#   # TODO make this the flake's self input?
#   src = ./.;

#   nativeBuildInputs = [ swift swiftpm ];

#   # __propagatedImpureHostDeps = [
#   #   # "/System/Library/Frameworks"
#   #   "/System/Library/Frameworks/Virtualization.framework/Versions/Current/"
#   #   "/System/Library/Frameworks/Virtualization.framework"
#   #   "/System/Library/Frameworks/Foundation.framework"
#   # ];

#   # NIX_SWIFTFLAGS_COMPILE = "-Fsystem /System/Library/Frameworks";

#   # env = {
#   # SDK_PATH = "/Syst"
#   # };

#   preBuild = ''
#     ${darwin.xcode_15_1}/Contents/Developer/usr/bin/xcodebuild -sdk -version
#     env
#   '';

#   buildInputs = [
#     darwin.xcode_15_1
#     Foundation
#     Virtualization
#   ];
#   # buildInputs = with darwin.apple_sdk_12_3.frameworks; [
#   #   Foundation
#   #   Virtualization
#   #   AppKit
#   #   Cocoa
#   # ];

#   configurePhase = generated.configure;

#   installPhase = ''
#     runHook preInstall
#     install -Dm755 .build/${swiftPackages.stdenv.hostPlatform.darwinArch}-apple-macosx/release/xenu -t $out/bin
#     runHook postInstall
#   '';

#   meta = with lib; {
#     description = "Command line interface to Apple Virtualization";
#     homepage = "https://github.com/Feyorsh/xenu";
#     license = licenses.gpl3;
#     mainProgram = "xenu";
#     platforms = platforms.darwin;
#   };
# })

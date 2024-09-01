{ lib
, stdenv
, swiftpm
, swiftpm2nix
, xcode
, sigtool
, runCommandLocal
, makeWrapper
, writeShellScriptBin
}:
let
  generated = swiftpm2nix.helpers ./generated;

  configuration = "debug";

  # this is less brittle than it seems because swiftpm is
  # open source and all `xcrun` invocations can be audited
  xcrun' = writeShellScriptBin "xcrun"
    ''
      if [[ "$3" == "--show-sdk-platform-path" ]]; then
        echo ${xcode}/Contents/Developer/Platforms/MacOSX.platform
      elif [[ "$3" == "--show-sdk-path" ]]; then
        echo ${xcode}/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX14.2.sdk
      elif [[ "$1" == "--find" ]]; then
        echo ${xcode}/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/$2
      else
        exit 1
      fi
    '';

  swift' = let exe = "swift-build"; in lib.getExe' (runCommandLocal exe { nativeBuildInputs = [ makeWrapper ]; }
    ''
      mkdir -p $out/bin
      makeWrapper ${swiftpm}/bin/.swift-package-wrapped $out/bin/${exe} \
        --argv0 ${exe} \
        --add-flags "-c ${configuration}" \
        --add-flags "-j $((enableParallelBuilding?NIX_BUILD_CORES:1))" \
        --prefix PATH : ${xcrun'}/bin
    '') exe;
in

stdenv.mkDerivation rec {
  pname = "xenu";
  version = "0.0.3";

  src = ./.;

  nativeBuildInputs = [ sigtool ];

  configurePhase = generated.configure;

  buildPhase = ''
    runHook preBuild
    ${swift'}
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    binPath="$(${swift'} --show-bin-path)"
    mkdir -p $out/bin
    cp $binPath/xenu $out/bin/xenu
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
}

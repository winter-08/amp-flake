{ pkgs, release }:
let
  inherit (pkgs) lib stdenvNoCC;
  platform = release.platforms.${pkgs.stdenv.hostPlatform.system};
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
in
stdenvNoCC.mkDerivation {
  pname = "amp-desktop";
  inherit (platform) version;
  src = pkgs.fetchurl { inherit (platform) url hash; };

  nativeBuildInputs = [ pkgs.makeWrapper ]
    ++ lib.optionals isDarwin [ pkgs.undmg ]
    ++ lib.optionals (!isDarwin) [ pkgs.dpkg pkgs.autoPatchelfHook pkgs.wrapGAppsHook3 ];
  buildInputs = lib.optionals (!isDarwin) (with pkgs; [
    alsa-lib at-spi2-atk at-spi2-core cairo cups dbus expat glib gtk3
    libgbm libnotify libxkbcommon nspr nss pango systemd
    libx11 libxcb libxcomposite libxdamage libxext libxfixes libxrandr
    stdenv.cc.cc.lib
  ]);
  runtimeDependencies = lib.optionals (!isDarwin) [ pkgs.systemd ];
  dontWrapGApps = true;
  dontStrip = true;
  strictDeps = true;

  unpackPhase = if isDarwin then ''
    runHook preUnpack
    undmg "$src"
    runHook postUnpack
  '' else ''
    runHook preUnpack
    dpkg-deb -x "$src" .
    runHook postUnpack
  '';

  installPhase = if isDarwin then ''
    runHook preInstall
    mkdir -p "$out/Applications" "$out/bin"
    cp -R Amp.app "$out/Applications/"
    makeWrapper /usr/bin/open "$out/bin/amp-desktop" \
      --add-flags '-a' --add-flags "$out/Applications/Amp.app" --add-flags '--args'
    runHook postInstall
  '' else ''
    runHook preInstall
    mkdir -p "$out/lib/amp-desktop" "$out/share" "$out/bin"
    cp -R opt/amp/. "$out/lib/amp-desktop/"
    cp -R usr/share/applications usr/share/icons "$out/share/"
    substituteInPlace "$out/share/applications/amp-desktop.desktop" \
      --replace-fail /opt/amp/amp-desktop "$out/bin/amp-desktop"
    runHook postInstall
  '';

  preFixup = lib.optionalString (!isDarwin) ''
    makeWrapper "$out/lib/amp-desktop/amp-desktop" "$out/bin/amp-desktop" \
      "''${gappsWrapperArgs[@]}" \
      --prefix PATH : ${lib.makeBinPath [ pkgs.xdg-utils ]} \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ pkgs.libGL pkgs.libnotify ]}
  '';

  meta = {
    description = "Amp desktop app";
    homepage = "https://ampcode.com/app";
    license = lib.licenses.unfree;
    mainProgram = "amp-desktop";
    platforms = builtins.attrNames release.platforms;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}

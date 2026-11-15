{ appimageTools, autoPatchelfHook, bash, fetchurl, gtk3, lib, libepoxy, libgcrypt, procps, python3, stdenv, zlib }:

let
  pname = "clashmi";
  version = "1.0.32.1803";
  src = fetchurl {
    url = "https://github.com/KaringX/clashmi/releases/download/v${version}/clashmi_${version}_linux_amd64.AppImage";
    hash = "sha256-kuF6FkiO3Xbn5vtNDXUnc2zlQCG2e8bv7xz4KeT0qG8=";
  };
  contents = appimageTools.extract { inherit pname version src; };
in
stdenv.mkDerivation {
  inherit pname version;
  src = contents;
  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ gtk3 libepoxy libgcrypt stdenv.cc.cc.lib zlib ];
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/opt/clashmi" "$out/bin"
    cp -a . "$out/opt/clashmi/"
    chmod -R u+w "$out/opt/clashmi"
    addAutoPatchelfSearchPath "$out/opt/clashmi/lib" "$out/opt/clashmi/usr/lib"
    cat > "$out/bin/clashmi" <<EOF
    #!${bash}/bin/bash
    running=0
    while read -r pid; do
      if [ "\$pid" != "\$\$" ]; then running=1; fi
    done < <(${procps}/bin/pgrep -u "\$UID" -x clashmi || true)
    if [ "\$running" = 0 ]; then
      ${python3}/bin/python3 ${../scripts/clashmi-profile.py}
    fi
    runtime="/var/lib/pino-clashmi/''${out##*/}"
    if [ ! -x "\$runtime/clashmi" ]; then
      echo 'Clash Mi runtime is missing; run pino os rebuild first.' >&2
      exit 1
    fi
    exec "\$runtime/clashmi" "\$@"
    EOF
    chmod 0755 "$out/bin/clashmi"
    install -Dm644 clashmi.desktop "$out/share/applications/clashmi.desktop"
    substituteInPlace "$out/share/applications/clashmi.desktop" \
      --replace-fail 'Exec=LD_LIBRARY_PATH=usr/lib clashmi %u' 'Exec=clashmi %u'
    for size in 128 256; do
      install -Dm644 usr/share/icons/hicolor/"$size"x"$size"/apps/clashmi.png \
        "$out/share/icons/hicolor/''${size}x''${size}/apps/clashmi.png"
    done
    runHook postInstall
  '';
  meta = {
    description = "Clash Mi proxy client";
    homepage = "https://github.com/KaringX/clashmi";
    license = lib.licenses.gpl3Only;
    platforms = [ "x86_64-linux" ];
    mainProgram = "clashmi";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}

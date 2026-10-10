{ pkgs, ... }:

let
  # Upstream Linux tarballs include the GUI, CLI, desktop entries, and icons.
  mkCraftApp =
    {
      pname,
      version,
      hash,
      description,
    }:
    pkgs.stdenv.mkDerivation {
      inherit pname version;

      src = pkgs.fetchurl {
        url = "https://github.com/storytold/${pname}/releases/download/v${version}/${pname}-${version}-linux-x86_64.tar.gz";
        inherit hash;
      };

      nativeBuildInputs = with pkgs; [
        autoPatchelfHook
        makeWrapper
      ];

      buildInputs = with pkgs; [
        alsa-lib
        stdenv.cc.cc.lib
      ];

      # winit/wgpu load the display and graphics libraries dynamically.
      runtimeDependencies = map pkgs.lib.getLib (
        with pkgs;
        [
          fontconfig
          libGL
          libx11
          libxcursor
          libxi
          libxrandr
          libxkbcommon
          vulkan-loader
          wayland
        ]
      );

      dontBuild = true;
      dontStrip = true;

      installPhase = ''
        runHook preInstall
        mkdir -p "$out"
        cp -r bin share "$out/"
        substituteInPlace "$out/share/applications/ai.storyteller.${pname}.desktop" \
          --replace-fail "Exec=${pname}" "Exec=$out/bin/${pname}"
        wrapProgram "$out/bin/${pname}" \
          --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.xdg-utils ]}
        runHook postInstall
      '';

      meta = {
        inherit description;
        homepage = "https://getartcraft.com/apps/${pname}";
        license = with pkgs.lib.licenses; [
          mit
          asl20
        ];
        platforms = [ "x86_64-linux" ];
        sourceProvenance = [ pkgs.lib.sourceTypes.binaryNativeCode ];
        mainProgram = pname;
      };
    };
in
{
  home.packages = [
    (mkCraftApp {
      pname = "photocraft";
      version = "0.6.0";
      hash = "sha256-tl/XAbY2DTugsFkAR0v5LZkmx2gC/vp76ZZpD8vDlsY=";
      description = "Layer-based image editor";
    })
    (mkCraftApp {
      pname = "filmcraft";
      version = "0.5.0";
      hash = "sha256-viGD+YWcATy/Lo3ClSRTJQOj63XiFWr2F71N9/+tQN0=";
      description = "Non-linear video editor";
    })
    (mkCraftApp {
      pname = "effectcraft";
      version = "0.7.0";
      hash = "sha256-/+x316LjSdn7AMjruQKvwsuO9UyKLVjdQEurFfW4Q4c=";
      description = "Motion graphics and visual effects compositor";
    })
  ];
}

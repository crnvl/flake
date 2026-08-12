{ pkgs, ... }:

let
  wine = pkgs.wineWow64Packages.stagingFull;

  winetricks = pkgs.symlinkJoin {
    name = "winetricks-wrapped";
    paths = [ pkgs.winetricks ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/winetricks \
        --set-default WINE_BIN ${wine}/bin/.wine \
        --set-default WINESERVER_BIN ${wine}/bin/wineserver \
        --prefix PATH : ${wine}/bin
    '';
  };

  wineEnv = ''
    export WINEPREFIX="$HOME/.local/share/wineprefixes/audio"
    export WINEARCH=win64
    export WINEFSYNC=1
    export WINEDEBUG="''${WINEDEBUG:--all}"
  '';

  findInPrefix = ''
    find_in_prefix() {
      find "$WINEPREFIX/drive_c" -maxdepth 8 -iname "$1" -print -quit 2>/dev/null || true
    }
  '';

  wine-audio = pkgs.writeShellApplication {
    name = "wine-audio";
    runtimeInputs = [ wine ];
    text = ''
      ${wineEnv}
      exec wine "$@"
    '';
  };

  fl-prefix-bootstrap = pkgs.writeShellApplication {
    name = "fl-prefix-bootstrap";
    runtimeInputs = [
      wine
      winetricks
      pkgs.coreutils
    ];
    text = ''
      ${wineEnv}

      wait_wine() {
        timeout 120 wineserver -w || true
      }

      if [ ! -x "${wine}/bin/.wine" ]; then
        echo "expected unwrapped wine binary at ${wine}/bin/.wine" >&2
        echo "nixpkgs wrapper layout changed; winetricks arch detection will fail" >&2
        exit 1
      fi

      mkdir -p "$WINEPREFIX"

      echo ">> initialising prefix at $WINEPREFIX"
      wineboot --init
      wait_wine

      echo ">> installing core components"
      winetricks -q win10 corefonts vcrun2022 gdiplus powershell dxvk
      wait_wine

      echo ">> installing extra fonts"
      if ! winetricks -q allfonts; then
        echo "warning: allfonts failed, continuing" >&2
      fi
      wait_wine

      echo ">> applying window management settings"
      wine reg add 'HKCU\Software\Wine\X11 Driver' /v Managed /d Y /f
      wait_wine

      echo
      echo "prefix ready."
      echo "install FL Studio with:  wine-audio /path/to/installer.exe"
    '';
  };

  fl-studio = pkgs.writeShellApplication {
    name = "fl-studio";
    runtimeInputs = [
      wine
      pkgs.findutils
    ];
    text = ''
      ${wineEnv}
      ${findInPrefix}

      fl="$(find_in_prefix 'FL64.exe')"

      if [ -z "$fl" ]; then
        echo "FL Studio not found under $WINEPREFIX" >&2
        echo "install it first:  wine-audio /path/to/flstudio_installer.exe" >&2
        exit 1
      fi

      exec wine "$fl" "$@"
    '';
  };

  native-access = pkgs.writeShellApplication {
    name = "native-access";
    runtimeInputs = [
      wine
      pkgs.findutils
    ];
    text = ''
      ${wineEnv}
      ${findInPrefix}

      na="$(find_in_prefix 'Native Access.exe')"

      if [ -z "$na" ]; then
        echo "Native Access not found under $WINEPREFIX" >&2
        exit 1
      fi

      exec wine "$na" --disable-gpu --disable-gpu-compositing "$@"
    '';
  };

  ntk-daemon = pkgs.writeShellApplication {
    name = "ntk-daemon";
    runtimeInputs = [
      wine
      pkgs.findutils
    ];
    text = ''
      ${wineEnv}
      ${findInPrefix}

      case "''${1:-start}" in
        install)
          setup="$(find_in_prefix 'NTKDaemon*Setup*.exe')"
          if [ -z "$setup" ]; then
            echo "NTKDaemon installer not found; install Native Access first" >&2
            exit 1
          fi
          echo ">> $setup"
          exec wine "$setup"
          ;;
        start)
          daemon="$(find_in_prefix 'NTKDaemon.exe')"
          if [ -z "$daemon" ]; then
            echo "NTKDaemon not installed; run: ntk-daemon install" >&2
            exit 1
          fi
          echo ">> $daemon"
          wine "$daemon" &
          echo "started in background"
          ;;
        *)
          echo "usage: ntk-daemon {install|start}" >&2
          exit 1
          ;;
      esac
    '';
  };

  ni-iso-install = pkgs.writeShellApplication {
    name = "ni-iso-install";
    runtimeInputs = [
      wine
      pkgs.p7zip
      pkgs.findutils
      pkgs.coreutils
    ];
    text = ''
      ${wineEnv}

      iso="''${1:-}"

      if [ -z "$iso" ] || [ ! -f "$iso" ]; then
        echo "usage: ni-iso-install <library.iso>" >&2
        exit 1
      fi

      base="$(basename "$iso" .iso)"
      work="''${XDG_CACHE_HOME:-$HOME/.cache}/ni-iso/$base"

      echo ">> extracting $base"
      rm -rf "$work"
      mkdir -p "$work"

      if ! 7z x -y -o"$work" "$iso" >/dev/null; then
        echo "extraction failed; try the mount path instead:" >&2
        echo "  ni-iso-mount $iso" >&2
        exit 1
      fi

      mapfile -t exes < <(find "$work" -maxdepth 3 -iname '*.exe' | sort)

      if [ "''${#exes[@]}" -eq 0 ]; then
        echo "no installer found in $work" >&2
        exit 1
      fi

      installer="''${exes[0]}"

      if [ "''${#exes[@]}" -gt 1 ]; then
        for e in "''${exes[@]}"; do
          case "$e" in
            *[Ss]etup*) installer="$e"; break ;;
          esac
        done
      fi

      echo ">> $installer"

      if wine "$installer"; then
        rm -rf "$work"
        echo ">> done, extracted files removed"
      else
        echo ">> installer returned an error; files kept at $work" >&2
        exit 1
      fi
    '';
  };

  authenticodeOrder = pkgs.writeText "authenticode-order.py" ''
    import sys


    def parse(buf, off, end):
        out = []
        while off < end:
            start = off
            tag = buf[off]
            off += 1
            if tag & 0x1F == 0x1F:
                while buf[off] & 0x80:
                    off += 1
                off += 1
            size = buf[off]
            off += 1
            if size & 0x80:
                n = size & 0x7F
                size = int.from_bytes(buf[off:off + n], "big")
                off += n
            out.append((tag, start, off, off + size))
            off += size
        return out


    def children(buf, node):
        return parse(buf, node[2], node[3])


    with open(sys.argv[1], "rb") as fh:
        data = fh.read()

    content = parse(data, 0, len(data))[0]
    signed = children(data, children(data, content)[1])[0]
    signers = [n for n in children(data, signed) if n[0] == 0x31][-1]
    signer = children(data, signers)[0]

    attrs = None
    for node in children(data, signer):
        if node[0] == 0xA0:
            attrs = node
            break

    if attrs is None:
        print("no authenticated attributes, nothing to check")
        sys.exit(0)

    items = [data[n[1]:n[3]] for n in children(data, attrs)]
    want = sorted(items)

    print("authenticated attributes: " + str(len(items)))
    print("actual order:   " + ", ".join(x[:2].hex() for x in items))
    print("required order: " + ", ".join(x[:2].hex() for x in want))
    print("")

    if items == want:
        print("PASS: attributes are DER-sorted, Wine can verify this signature")
        sys.exit(0)

    print("FAIL: attributes are not DER-sorted")
    print("Wine re-encodes and sorts them, so WinVerifyTrust returns 0x80096004")
    sys.exit(1)
  '';

  authenticode-check = pkgs.writeShellApplication {
    name = "authenticode-check";
    runtimeInputs = [
      pkgs.osslsigncode
      pkgs.python3
      pkgs.coreutils
    ];
    text = ''
      pe="''${1:-}"

      if [ -z "$pe" ] || [ ! -f "$pe" ]; then
        echo "usage: authenticode-check <file.exe|file.dll>" >&2
        exit 2
      fi

      tmp="$(mktemp -d)"
      trap 'rm -rf "$tmp"' EXIT

      if ! osslsigncode extract-signature -in "$pe" -out "$tmp/sig.der" >/dev/null 2>&1; then
        echo "no Authenticode signature found in $pe" >&2
        exit 2
      fi

      echo "file: $pe"
      python3 ${authenticodeOrder} "$tmp/sig.der"
    '';
  };

  ni-iso-mount = pkgs.writeShellApplication {
    name = "ni-iso-mount";
    runtimeInputs = [
      pkgs.udisks
      pkgs.gnugrep
      pkgs.coreutils
    ];
    text = ''
      iso="''${1:-}"

      if [ -z "$iso" ] || [ ! -f "$iso" ]; then
        echo "usage: ni-iso-mount <library.iso>" >&2
        exit 1
      fi

      loop="$(udisksctl loop-setup -f "$iso" | grep -oE '/dev/loop[0-9]+' || true)"

      if [ -z "$loop" ]; then
        echo "could not attach $iso to a loop device" >&2
        exit 1
      fi

      echo ">> attached as $loop"
      udisksctl mount -t udf -o unhide -b "$loop"
      echo
      echo "run the installer with:  wine-audio /run/media/$USER/<volume>/<Setup>.exe"
      echo "detach afterwards with:  udisksctl loop-delete -b $loop"
    '';
  };
in
{
  environment.systemPackages = [
    wine
    winetricks

    wine-audio
    fl-prefix-bootstrap
    fl-studio
    native-access
    ntk-daemon
    ni-iso-install
    ni-iso-mount
    authenticode-check
  ];
}

authenticode-check
];
}2212
{ lib, ... }:

# PHP 8.4.27 and 8.5.12 fix CVE-2026-109618 and CVE-2026-109619, two
# critical unauthenticated RCEs in PHP-FPM:
# https://www.php.net/archive/2026.php#2026-10-21-5
#
# nixpkgs has them (NixOS/nixpkgs#576853), but they haven't reached
# nixos-unstable yet, so PHP and its extensions are rebuilt here from the
# fixed releases. Nextcloud uses php84, Roundcube php85 (also `php`). Once
# nixpkgs is at or past these versions this leaves PHP alone, and the file
# can go.
let
  fixed = {
    php84 = {
      version = "8.4.27";
      hash = "sha256-slMKh3xyL0sIyeF0owywi6wrfhkD7m6eMV8KqfX4LCQ=";
    };
    php85 = {
      version = "8.5.12";
      hash = "sha256-/7YO3EN87WO1E35JhNs3moERxQBJxxFRDYuVgnfvwag=";
    };
  };
in
{
  nixpkgs.overlays = [
    (
      final: prev:
      lib.mapAttrs (
        name:
        { version, hash }:
        if lib.versionOlder prev.${name}.version version then
          (prev.${name}.overrideAttrs {
            inherit version;
            src = final.fetchurl {
              url = "https://www.php.net/distributions/php-${version}.tar.bz2";
              inherit hash;
            };
          }).withExtensions
            (
              { enabled, ... }:
              map (
                ext:
                # The releases add out-of-memory tests that run php with -n,
                # which skips loading the extension under test; same fix as
                # in nixpkgs.
                if ext.extensionName == "filter" then
                  ext.overrideAttrs (old: {
                    postConfigure = (old.postConfigure or "") + ''
                      substituteInPlace \
                        tests/oom_filter_input.phpt \
                        tests/oom_filter_input_array.phpt \
                        tests/oom_filter_default_encoded.phpt \
                        --replace-fail "'-n'," "'-n', '-d', 'extension=$PWD/modules/filter.so',"
                    '';
                  })
                else
                  ext
              ) enabled
            )
        else
          prev.${name}
      ) fixed
    )
  ];
}

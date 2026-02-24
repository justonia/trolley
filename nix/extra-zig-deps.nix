# Extra Zig dependencies not covered by ghostty/build.zig.zon.nix.
# When updating a dep: change the url, update the zig hash from
# runtime/build.zig.zon, and run `nix-prefetch-url <url>` piped through
# `nix hash to-sri --type sha256` to get the new nix hash.
{
  lib,
  linkFarm,
  fetchurl,
  fetchgit,
  runCommandLocal,
  zig_0_15,
  name ? "zig-extra-packages",
}: let
  unpackZigArtifact = {
    name,
    artifact,
  }:
    runCommandLocal name
    {
      nativeBuildInputs = [zig_0_15];
    }
    ''
      hash="$(zig fetch --global-cache-dir "$TMPDIR" ${artifact})"
      mv "$TMPDIR/p/$hash" "$out"
      chmod 755 "$out"
    '';

  fetchZig = {
    name,
    url,
    hash,
  }: let
    artifact = fetchurl {inherit url hash;};
  in
    unpackZigArtifact {inherit name artifact;};

  fetchZigArtifact = {
    name,
    url,
    hash,
  }: let
    parts = lib.splitString "://" url;
    proto = builtins.elemAt parts 0;
    path = builtins.elemAt parts 1;
    fetcher = {
      http = fetchZig {
        inherit name hash;
        url = "http://${path}";
      };
      https = fetchZig {
        inherit name hash;
        url = "https://${path}";
      };
    };
  in
    fetcher.${proto};
in
  linkFarm name [
    {
      name = "N-V-__8AAL40TADEbrysYHBl-UIZO4KiG4chP8pLDVDINGH4";
      path = fetchZigArtifact {
        name = "glfw";
        url = "https://github.com/glfw/glfw/archive/refs/tags/3.4.tar.gz";
        hash = "sha256-wDjTQgAjTQcfrpNFvEVeSo8vVEq2AVB2XXcE4I89rAE=";
      };
    }
  ]

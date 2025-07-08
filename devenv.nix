{ pkgs ? import (fetchTarball "https://github.com/NixOS/nixpkgs/archive/nixos-23.11.tar.gz") {} }:

pkgs.mkShell {
  buildInputs = [
    (pkgs.ruby_3_2.withPackages (ps: [
      ps.nokogiri
    ]))
    pkgs.playerctl # Für den Spotify-Selektor
  ];
}

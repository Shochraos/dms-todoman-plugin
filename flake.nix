{
  description = "Todoman Tasks plugin for DuxShell";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { nixpkgs, ... }:
    let
      inherit (nixpkgs) lib;
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forSystems = build: lib.genAttrs systems (system: build nixpkgs.legacyPackages.${system});
      backendPython = pkgs: pkgs.python3.withPackages (ps: [ ps.icalendar ps.python-dateutil ]);
    in
    {
      packages = forSystems (pkgs: {
        default = pkgs.callPackage ./nix/package.nix { backendPython = backendPython pkgs; };
      });

      devShells = forSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            (backendPython pkgs)
            pkgs.todoman
            (pkgs.writeShellScriptBin "nix" (
              ''
                nativeNix=${lib.getExe pkgs.nix}
                coreutils=${pkgs.coreutils}/bin
                storeDir=${builtins.storeDir}
              '' + builtins.readFile ./nix/dank-todoman-dev-build.sh
            ))
          ];
        };
      });
    };
}

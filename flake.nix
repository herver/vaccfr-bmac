{
  description = "BMAC dev shell (PHP 8.5 + Composer + Node 22)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in {
      devShells = forAllSystems (pkgs:
        let
          php = pkgs.php85.buildEnv {
            extensions = { enabled, all }: enabled ++ [ all.redis ];
            extraConfig = "memory_limit = -1";
          };
        in {
          default = pkgs.mkShell {
            packages = [ php php.packages.composer pkgs.nodejs_22 ];
          };
        });
    };
}

{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    self.submodules = true;
  };

  outputs = { self, nixpkgs }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ];
    in
      {
      packages = forAllSystems (system: {
        default = nixpkgs.legacyPackages.${system}.callPackage ./packaging/linux/nix/package.nix {
          src = self;
        };
      });

      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/idescriptor";
        };
      });

      devShells = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in {
          default = pkgs.mkShell {
            inputsFrom = [ self.packages.${system}.default ];

            packages = with pkgs; [
              cargo
              rustc
              rustfmt
            ];
          };
        });

      nixosModules.default = { config, lib, pkgs, ... }:
        let
          cfg = config.programs.idescriptor;
          idescriptorPkg = self.packages.${pkgs.system}.default;
        in
          {
          imports = [ ./packaging/linux/nix/nixos-module.nix ];

          config = lib.mkIf cfg.enable {
            programs.idescriptor.package = lib.mkDefault idescriptorPkg;
          };
        };

      homeManagerModules.default = { config, lib, pkgs, ... }:
        let
          cfg = config.programs.idescriptor;
          idescriptorPkg = self.packages.${pkgs.system}.default;
        in
          {
          imports = [ ./packaging/linux/nix/hm-module.nix ];

          config = lib.mkIf cfg.enable {
            programs.idescriptor.package = lib.mkDefault idescriptorPkg;
          };
        };
    };
}

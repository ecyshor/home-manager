{
  description = "Home Manager configuration of nicu";

  inputs = {
    # Specify the source of Home Manager and Nixpkgs.
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Newer nixpkgs pin used only for proton-drive-cli (absent from the main pin;
    # bumping the main pin breaks the mistral-vibe override).
    nixpkgs-proton.url = "github:nixos/nixpkgs/e338dea6276803157d93bf2210283556ecc7febd";

    nixvim = {
        url = "github:nix-community/nixvim";
        inputs.nixpkgs.follows = "nixpkgs";
    };

  };

  outputs = { self, nixpkgs, nixpkgs-proton, home-manager, nixvim, ... }:
    let
      personalGit = {
        name = "Nicu Reut";
        email = "contact@nicu.dev";
      };

      # One Home Manager configuration. `modules` are host-specific on top of the
      # shared ./home.nix; `args` are passed through extraSpecialArgs.
      mkHome = { system, modules, args }:
        home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};
          modules = [
            ./home.nix
            nixvim.homeModules.nixvim
          ] ++ modules;
          extraSpecialArgs = {
            # Flake source store path; recorded on activation so the repo .envrc can
            # tell whether the checked-out tree still needs `home-manager switch`.
            flakeSelf = self;
            protonPkgs = nixpkgs-proton.legacyPackages.${system};
          } // args;
        };
    in {
      # Personal laptop (XPS): claude-code, mistral-vibe, and AI neovim integrations
      homeConfigurations."nicu" = mkHome {
        system = "x86_64-linux";
        modules = [ ./linux.nix ./hosts/xps/home.nix ];
        args = {
          git = personalGit;
          personalLaptop = true;
          antigravity = true;
        };
      };

      homeConfigurations."nicu@nicu-da-dell-pro-max" = mkHome {
        system = "x86_64-linux";
        modules = [ ./linux.nix ./hosts/work/home.nix ];
        args = {
          git = {
            name = "Nicu Reut";
            email = "nicu.reut@digitalasset.com";
          };
          personalLaptop = false;
          antigravity = false;
        };
      };

      # Personal MacBook (Apple Silicon): same personal setup as the XPS minus
      # Antigravity and the Linux desktop/system modules.
      homeConfigurations."nicu@Simonas-MacBook-Pro" = mkHome {
        system = "aarch64-darwin";
        modules = [ ./hosts/mac/home.nix ];
        args = {
          git = personalGit;
          personalLaptop = true;
          antigravity = false;
        };
      };
    };
}

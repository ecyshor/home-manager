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
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      homeConfigurations."nicu" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs; 

        # Specify your home configuration modules here, for example,
        # the path to your home.nix.
        modules = [ 
            ./home.nix 
            ./hosts/xps/home.nix
            nixvim.homeModules.nixvim
       ];

        # Optionally use extraSpecialArgs
        # to pass through arguments to home.nix
        extraSpecialArgs = {
          # Flake source store path; recorded on activation so the repo .envrc can
          # tell whether the checked-out tree still needs `home-manager switch`.
          flakeSelf = self;
          git = {
            name = "Nicu Reut";
            email = "contact@nicu.dev";
          };
          # Personal laptop (XPS): claude-code, mistral-vibe, and AI neovim integrations
          personalLaptop = true;
          protonPkgs = nixpkgs-proton.legacyPackages.${system};
        };
    };
    homeConfigurations."nicu@nicu-da-dell-pro-max" = home-manager.lib.homeManagerConfiguration {
      inherit pkgs; 

      # Specify your home configuration modules here, for example,
      # the path to your home.nix.
      modules = [ 
          ./home.nix 
          ./hosts/work/home.nix

          nixvim.homeModules.nixvim
     ];

      # Optionally use extraSpecialArgs
      # to pass through arguments to home.nix
      extraSpecialArgs = {
        # Flake source store path; recorded on activation so the repo .envrc can
        # tell whether the checked-out tree still needs `home-manager switch`.
        flakeSelf = self;
        git = {
          name = "Nicu Reut";
          email = "nicu.reut@digitalasset.com";
        };
        personalLaptop = false;
      };
    };
  };
}

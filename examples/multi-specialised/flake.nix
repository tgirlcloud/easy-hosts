{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    easy-hosts.url = "github:isabelroses/easy-hosts";
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ inputs.easy-hosts.flakeModule ];

      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];

      easyHosts = {
        autoConstruct = true;
        path = ./hosts;

        perClass = class: {
          # only nixos systems will get this module
          modules = inputs.nixpkgs.lib.optionals (class == "nixos") [
            ./modules/nixos.nix
          ];
        };
      };
    };
}

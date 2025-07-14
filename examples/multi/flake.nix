{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    easy-hosts.url = "github:tgirlcloud/easy-hosts";
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ inputs.easy-hosts.flakeModule ];

      systems = [ "x86_64-linux" ];

      easy-hosts = {
        autoConstruct = true;
        path = ./hosts;

        # Reduce size of the image
        hosts.test3.tags = [ "minimal" ];

        perTag =
          let
            tags = {
              minimal =
                { modulesPath, ... }:
                {
                  imports = [ "${modulesPath}/profiles/minimal.nix" ];
                };
            };
          in
          tag: {
            modules = [ tags.${tag} ];
          };
      };
    };
}

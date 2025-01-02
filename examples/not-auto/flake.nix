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
        "x86_64-nixos"
        "aarch64-darwin"
      ];

      easyHosts.hosts = {
        test = {
          arch = "x86_64";
          class = "nixos";
        };

        test2 = {
          arch = "x86_64";
          class = "darwin";
        };
      };
    };
}

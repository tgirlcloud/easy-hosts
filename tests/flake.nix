{
  inputs = {
    nixpkgs.url = "https://channels.nixos.org/nixpkgs-unstable/nixexprs.tar.xz";

    # you need nixos/nix >= 2.28 to eval this flake
    easy-hosts.url = "path:../.";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      # required for eval
      systems = [ "x86_64-linux" ];

      # do the thing
      imports = [ inputs.easy-hosts.flakeModule ];

      easy-hosts = {
        # add our system tags
        perTag = tag: {
          modules = [
            { system.nixos.tags = [ tag ]; }
          ];
        };

        # setup grub as the bootloader if the class is nixos
        # if this doesn't run then well classes are broken
        perClass = class: {
          modules =
            if class == "nixos" then
              [
                {
                  boot.loader.grub = {
                    enable = true;
                    device = "/dev/sda";
                  };
                }
              ]
            else
              [ ];
        };

        # finally do the thing we all came for
        hosts = {
          test1 = {
            class = "nixos";
            arch = "x86_64";

            # test some tags
            tags = [
              "laptop"
              "headless"
            ];

            modules = [
              {
                # remove fs assertion
                fileSystems."/".label = "root";
              }
            ];
          };
        };
      };
    };
}

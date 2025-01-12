{
  lib,
  inputs,
  config,
  withSystem,
  ...
}:
let
  inherit (builtins) concatLists attrNames;
  inherit (lib.options) mkOption literalExpression;
  inherit (lib) types;

  inherit (import ./lib.nix { inherit lib inputs withSystem; })
    constructSystem
    mkHosts
    buildHosts
    ;

  cfg = config.easyHosts;

  mkBasicParams = name: {
    modules = mkOption {
      # we really expect a list of paths but i want to accept lists of lists of lists and so on
      # since they will be flattened in the final function that applies the settings
      type = types.listOf types.anything;
      default = [ ];
      description = "${name} modules to be included in the system";
      example = literalExpression ''
        [ ./hardware-configuration.nix ./networking.nix ]
      '';
    };

    specialArgs = mkOption {
      type = types.lazyAttrsOf types.raw;
      default = { };
      description = "${name} special arguments to be passed to the system";
      example = literalExpression ''
        { foo = "bar"; }
      '';
    };
  };
in
{
  options = {
    easyHosts = {
      autoConstruct = lib.mkEnableOption "Automatically construct hosts";

      path = mkOption {
        type = types.nullOr types.path;
        default = null;
        example = literalExpression "./hosts";
      };

      onlySystem = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = literalExpression "aarch64-darwin";
      };

      shared = mkBasicParams "Shared";

      perClass = mkOption {
        default = _: {
          modules = [ ];
          specialArgs = { };
        };
        type = types.functionTo (
          types.submodule {
            options = mkBasicParams "Per class";
          }
        );
      };

      additionalClasses = mkOption {
        default = { };
        type = types.attrsOf types.str;
        description = "Additional classes and thier rescpective mappings to already existing classes";
        example = lib.literalExpression ''
          {
            wsl = "nixos";
            rpi = "nixos";
            macos = "darwin";
          }
        '';
      };

      hosts = mkOption {
        default = { };
        type = types.attrsOf (
          types.submodule (
            { name, ... }:
            let
              self = cfg.hosts.${name};
            in
            {
              options = {
                # keep this up to date with
                # https://github.com/NixOS/nixpkgs/blob/75a43236cfd40adbc6138029557583eb77920afd/lib/systems/flake-systems.nix#L1
                arch = mkOption {
                  type = types.enum [
                    "x86_64"
                    "aarch64"
                    "armv6l"
                    "armv7l"
                    "i686"
                    "powerpc64le"
                    "riscv64"
                  ];
                  default = "x86_64";
                  example = "aarch64";
                };

                class = mkOption {
                  type = types.enum (concatLists [
                    [
                      "nixos"
                      "darwin"
                      "iso"
                    ]

                    (attrNames cfg.additionalClasses)
                  ]);
                  default = "nixos";
                  example = "darwin";
                };

                system = mkOption {
                  type = types.str;
                  default = constructSystem cfg self.class self.arch;
                  example = "aarch64-darwin";
                };

                path = mkOption {
                  type = types.nullOr types.path;
                  default = null;
                  example = literalExpression "./hosts/myhost";
                };

                deployable = mkOption {
                  type = types.bool;
                  default = false;
                };
              } // (mkBasicParams name);
            }
          )
        );
      };
    };
  };

  config = {
    # if the user has made it such that they want the hosts to be constructed automatically
    # i.e. from the file paths then we will do that
    easyHosts.hosts = lib.mkIf cfg.autoConstruct (buildHosts cfg);

    flake = mkHosts cfg;
  };
}

{
  lib,
  inputs,
  config,
  withSystem,
  ...
}:
let
  inherit (lib.options) mkOption literalExpression;
  inherit (lib) types;

  inherit (import ./lib.nix { inherit lib inputs withSystem; })
    constructSystem
    mkHosts
    buildHosts
    ;

  cfg = config.easyHosts;
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

      shared = {
        modules = mkOption {
          # we really expect a list of paths but i want to accept lists of lists of lists and so on
          # since they will be flattened in the final function that applies the settings
          type = types.listOf types.anything;
          default = [ ];
        };

        specialArgs = mkOption {
          type = types.attrs;
          default = { };
        };
      };

      perClass = mkOption {
        default = _: {
          modules = [ ];
          specialArgs = { };
        };

        type = types.functionTo (
          types.submodule {
            options = {
              modules = mkOption {
                type = types.listOf types.anything;
                default = [ ];
              };

              specialArgs = mkOption {
                type = types.attrs;
                default = { };
              };
            };
          }
        );
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
                arch = mkOption {
                  type = types.str;
                  default = "x86_64";
                };

                class = mkOption {
                  type = types.str;
                  default = "nixos";
                };

                system = mkOption {
                  type = types.str;
                  default = constructSystem self.class self.arch;
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

                modules = mkOption {
                  type = types.listOf types.anything;
                  default = [ ];
                };

                specialArgs = mkOption {
                  type = types.attrs;
                  default = { };
                };
              };
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

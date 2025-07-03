{
  lib,
  inputs,
  config,
  withSystem,
  ...
}:
let
  inherit (builtins) concatLists attrNames;
  inherit (lib.options) mkOption mkEnableOption literalExpression;
  inherit (lib) types;
  inherit (lib.modules) mkRenamedOptionModule;

  inherit (import ./lib.nix { inherit lib inputs withSystem; })
    constructSystem
    mkHosts
    buildHosts
    ;

  cfg = config.easy-hosts;

  mkBasicParams = name: {
    modules = mkOption {
      # we really expect a list of paths but i want to accept lists of lists of lists and so on
      # since they will be flattened in the final function that applies the settings
      type = types.listOf types.deferredModule;
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
    easy-hosts = {
      autoConstruct = lib.mkEnableOption "Automatically construct hosts";

      path = mkOption {
        type = types.nullOr types.path;
        default = null;
        example = literalExpression "./hosts";
        description = "Path to the directory containing the host files";
      };

      onlySystem = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = literalExpression "aarch64-darwin";
        description = "Only construct the hosts with for this platform";
      };

      shared = mkBasicParams "Shared";

      perClass = mkOption {
        default = _: {
          modules = [ ];
          specialArgs = { };
        };
        defaultText = ''
          class: {
            modules = [ ];
            specialArgs = { };
          };
        '';

        type = types.functionTo (
          types.submodule {
            options = mkBasicParams "Per class";
          }
        );

        example = literalExpression ''
          class: {
            modules = [
              { system.nixos.label = class; }
            ];

            specialArgs = { };
          }
        '';

        description = "Per class settings";
      };

      additionalClasses = mkOption {
        default = { };
        type = types.attrsOf types.str;
        description = "Additional classes and their respective mappings to already existing classes";
        example = lib.literalExpression ''
          {
            wsl = "nixos";
            rpi = "nixos";
            macos = "darwin";
          }
        '';
      };

      hosts = mkOption {
        description = "Hosts to be defined by the flake";

        default = { };

        type = types.attrsOf (
          types.submodule (
            { name, config, ... }:
            {
              options = {
                nixpkgs = mkOption {
                  type = types.anything;
                  default = inputs.nixpkgs or (throw "cannot find nixpkgs input");
                  defaultText = literalExpression "inputs.nixpkgs";
                  example = literalExpression "inputs.nixpkgs-unstable";
                  description = "The nixpkgs flake to be used for the host";
                };

                nix-darwin = mkOption {
                  type = types.anything;
                  default = inputs.darwin or inputs.nix-darwin or null;
                  defaultText = literalExpression "inputs.darwin or inputs.nix-darwin";
                  example = literalExpression "inputs.my-nix-darwin";
                  description = "The nix-darwin flake to be used for the host";
                };

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
                  description = "The architecture of the host";
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
                  description = "The class of the host";
                };

                system = mkOption {
                  type = types.str;
                  default = constructSystem cfg.additionalClasses config.arch config.class;
                  example = "aarch64-darwin";
                  description = "The system to be used for the host";
                  internal = true; # this should ideally be set by easy-hosts
                };

                path = mkOption {
                  type = types.nullOr types.path;
                  default = null;
                  example = literalExpression "./hosts/myhost";
                  description = "Path to the directory containing the host files";
                };

                deployable = mkEnableOption "Is this host deployable" // {
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

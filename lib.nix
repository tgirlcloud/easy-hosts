{
  lib,
  inputs,
  withSystem,
  ...
}:
let
  inherit (inputs) self;

  inherit (builtins)
    readDir
    elemAt
    filter
    pathExists
    foldl'
    ;
  inherit (lib.lists) optionals singleton flatten;
  inherit (lib.attrsets)
    recursiveUpdate
    foldAttrs
    attrValues
    mapAttrs
    filterAttrs
    ;
  inherit (lib.modules) mkDefault evalModules;

  classToOS = class: if (class == "darwin") then "darwin" else "linux";
  classToND = class: if (class == "darwin") then "darwin" else "nixos";

  redefineClass =
    cfg: class:
    (
      (cfg.additionalClasses or { })
      // {
        linux = "nixos";
      }
    ).${class} or class;

  constructSystem =
    config: class: arch:
    let
      class' = redefineClass config class;
      os = classToOS class';
    in
    "${arch}-${os}";

  splitSystem =
    system:
    let
      sp = builtins.split "-" system;
      arch = elemAt sp 0;
      class = elemAt sp 2;
    in
    {
      inherit arch class;
    };

  /**
    mkHost is a function that uses withSystem to give us inputs' and self'
    it also assumes the the system type either nixos or darwin and uses the appropriate

    # Type

    ```
    mkHost :: AttrSet -> AttrSet
    ```

    # Example

    ```nix
      mkHost {
        name = "myhost";
        path = "/path/to/host";
        system = "x86_64-linux";
        class = "nixos";
        modules = [ ./module.nix ];
        specialArgs = { foo = "bar"; };
      }
    ```
  */
  mkHost =
    {
      name,
      path,
      # by the time we recive the argument here it can only be one of
      # nixos, darwin, or iso. The redefineClass function should be used prior
      class,
      system,
      modules ? [ ],
      specialArgs ? { },
      ...
    }:
    withSystem system (
      { self', inputs', ... }:
      let
        darwinInput =
          if (inputs ? darwin) then
            inputs.darwin
          else if (inputs ? nix-darwin) then
            inputs.nix-darwin
          else
            throw "cannot find nix-darwin input";

        # create the modulesPath based on the system, we need
        modulesPath =
          if class == "darwin" then "${darwinInput}/modules" else "${inputs.nixpkgs}/nixos/modules";

        # we need to import the module list for our system
        # this is either the nixos modules list provided by nixpkgs
        # or the darwin modules list provided by nix darwin
        baseModules = import "${modulesPath}/module-list.nix";

        eval = evalModules {
          # we use recursiveUpdate such that users can "override" the specialArgs
          #
          # This should only be used for special arguments that need to be evaluated
          # when resolving module structure (like in imports).
          specialArgs = recursiveUpdate {
            inherit
              # these are normal args that people expect to be passed
              lib
              self # even though self is just the same as `inputs.self`
              inputs

              # these come from flake-parts
              self'
              inputs'

              # we need to set this beacuse some modules require it sadly
              # you may also recall `modulesPath + /installer/scan/not-detected.nix`
              modulesPath
              ;
          } specialArgs;

          # A nominal type for modules. When set and non-null, this adds a check to
          # make sure that only compatible modules are imported.
          class = classToND class;

          modules = flatten [
            # bring in all of our base modules
            baseModules

            # import our host system paths
            (
              if path != null then
                path
              else
                (filter pathExists [
                  # if the previous path does not exist then we will try to import some paths with some assumptions
                  "${self}/hosts/${name}/default.nix"
                  "${self}/systems/${name}/default.nix"
                ])
            )

            # get an installer profile from nixpkgs to base the Isos off of
            # this is useful because it makes things alot easier
            (optionals (class == "iso") [
              "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal-new-kernel.nix"
            ])

            (singleton {
              # some modules to have these arguments, like documentation.nix
              # <https://github.com/NixOS/nixpkgs/blob/9692553cb583e8dca46b66ab76c0eb2ada1a4098/nixos/modules/misc/documentation.nix>
              _module.args = {
                inherit baseModules;

                # this should in the future be the modules that the user added without baseModules
                modules = [ ];

                # TODO: remove in 25.05
                # https://github.com/NixOS/nixpkgs/blob/9692553cb583e8dca46b66ab76c0eb2ada1a4098/nixos/lib/eval-config.nix#L38
                extraModules = [ ];
              };

              # we set the systems hostname based on the host value
              # which should be a string that is the hostname of the system
              networking.hostName = name;

              nixpkgs = {
                # you can also do this as `inherit system;` with the normal `lib.nixosSystem`
                # however for evalModules this will not work, so we do this instead
                hostPlatform = mkDefault system;

                # The path to the nixpkgs sources used to build the system.
                # This is automatically set up to be the store path of the nixpkgs flake used to build
                # the system if using lib.nixosSystem, and is otherwise null by default.
                # so that means that we should set it to our nixpkgs flake output path
                flake.source = inputs.nixpkgs.outPath;
              };
            })

            # if we are on darwin we need to import the nixpkgs source, its used in some
            # modules, if this is not set then you will get an error
            (optionals (class == "darwin") (singleton {
              # without supplying an upstream nixpkgs source, nix-darwin will not be able to build
              # and will complain and log an error demanding that you must set this value
              nixpkgs.source = mkDefault inputs.nixpkgs;

              system = {
                # i don't quite know why this is set but upstream does it so i will too
                checks.verifyNixPath = false;

                # we use these values to keep track of what upstream revision we are on, this also
                # prevents us from recreating docs for the same configuration build if nothing has changed
                darwinVersionSuffix = ".${darwinInput.shortRev or darwinInput.dirtyShortRev or "dirty"}";
                darwinRevision = darwinInput.rev or darwinInput.dirtyRev or "dirty";
              };
            }))

            # import any additional modules that the user has provided
            modules
          ];
        };
      in
      if ((classToND class) == "nixos") then
        { nixosConfigurations.${name} = eval; }
      else
        {
          darwinConfigurations.${name} = eval // {
            system = eval.config.system.build.toplevel;
          };
        }
    );

  foldAttrsReccursive = foldl' (acc: attrs: recursiveUpdate acc attrs) { };

  mkHosts =
    easyHostsConfig:
    foldAttrs (host: acc: host // acc) { } (
      attrValues (
        mapAttrs (
          name: hostConfig:
          mkHost {
            inherit name;

            inherit (hostConfig) system path;

            class = redefineClass easyHostsConfig hostConfig.class;

            # merging is handled later
            modules = [
              (hostConfig.modules or [ ])
              (easyHostsConfig.shared.modules or [ ])
              ((easyHostsConfig.perClass hostConfig.class).modules or [ ])
            ];

            specialArgs = foldAttrsReccursive [
              (hostConfig.specialArgs or { })
              (easyHostsConfig.shared.specialArgs or { })
              ((easyHostsConfig.perClass hostConfig.class).specialArgs or { })
            ];
          }
        ) easyHostsConfig.hosts
      )
    );

  normaliseHosts =
    cfg: hosts:
    if (cfg.onlySystem == null) then
      foldAttrs (acc: host: acc // host) { } (
        attrValues (
          mapAttrs (
            system: hosts':
            mapAttrs (
              name: _:
              let
                inherit (splitSystem system) arch class;
              in
              {
                inherit arch class;
                system = constructSystem cfg arch class;
                path = "${cfg.path}/${system}/${name}";
              }
            ) hosts'
          ) hosts
        )
      )
    else
      mapAttrs (
        host: _:
        let
          inherit (splitSystem cfg.onlySystem) arch class;
        in
        {
          inherit arch class;
          system = constructSystem cfg arch class;
          path = "${cfg.path}/${host}";
        }
      ) hosts;

  buildHosts =
    cfg:
    let
      hostsDir = readDir cfg.path;

      hosts =
        if (cfg.onlySystem != null) then
          hostsDir
        else
          mapAttrs (path: _: readDir "${cfg.path}/${path}") (
            filterAttrs (_: type: type == "directory") hostsDir
          );
    in
    normaliseHosts cfg hosts;
in
{
  inherit
    constructSystem
    mkHost
    mkHosts
    buildHosts
    ;
}

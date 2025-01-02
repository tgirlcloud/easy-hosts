{
  lib,
  inputs,
  withSystem,
  ...
}:
let
  inherit (inputs) self;

  constructSystem =
    target: arch:
    if (target == "iso" || target == "nixos") then "${arch}-linux" else "${arch}-${target}";

  inherit (builtins)
    readDir
    elemAt
    filter
    pathExists
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
      class ? "nixos",
      system ? "x86_64-linux",
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

        eval = evalModules {
          # we use recursiveUpdate such that users can "override" the specialArgs
          #
          # This should only be used for special arguments that need to be evaluated
          # when resolving module structure (like in imports).
          specialArgs = recursiveUpdate {
            # create the modulesPath based on the system, we need
            modulesPath =
              if class == "darwin" then "${darwinInput}/modules" else "${inputs.nixpkgs}/nixos/modules";

            # laying it out this way is completely arbitrary, however it looks nice i guess
            inherit lib;
            inherit self self';
            inherit inputs inputs';
          } specialArgs;

          # A nominal type for modules. When set and non-null, this adds a check to
          # make sure that only compatible modules are imported.
          class = if class == "iso" then "nixos" else class;

          modules = flatten [
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

            # we need to import the module list for our system
            # this is either the nixos modules list provided by nixpkgs
            # or the darwin modules list provided by nix darwin
            (import (
              if class == "darwin" then
                "${darwinInput}/modules/module-list.nix"
              else
                "${inputs.nixpkgs}/nixos/modules/module-list.nix"
            ))

            (singleton {
              # TODO: learn what this means and why its needed to build the iso
              _module.args.modules = [ ];

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
      if (class == "nixos" || class == "iso") then
        { nixosConfigurations.${name} = eval; }
      else
        {
          darwinConfigurations.${name} = eval // {
            system = eval.config.system.build.toplevel;
          };
        }
    );

  foldAttrsReccursive = builtins.foldl' (acc: attrs: recursiveUpdate acc attrs) { };

  mkHosts =
    makeHostsConfig:
    foldAttrs (host: acc: host // acc) { } (
      attrValues (
        mapAttrs (
          name: cfg:
          mkHost {
            inherit name;

            inherit (cfg) class system path;

            # merging is handled later
            modules = [
              (cfg.modules or [ ])
              (makeHostsConfig.shared.modules or [ ])
              ((makeHostsConfig.perClass cfg.class).modules or [ ])
            ];

            specialArgs = foldAttrsReccursive [
              (cfg.specialArgs or { })
              (makeHostsConfig.shared.specialArgs or { })
              ((makeHostsConfig.perClass cfg.class).specialArgs or { })
            ];
          }
        ) makeHostsConfig.hosts
      )
    );

  onlyDirs = filterAttrs (_: type: type == "directory");

  splitSystem =
    system:
    let
      sp = builtins.split "-" system;
      arch = elemAt sp 0;
      class = if ((elemAt sp 2) == "linux") then "nixos" else elemAt sp 2;
    in
    {
      inherit arch class;
    };

  normaliseHosts =
    cfg: hosts:
    if (cfg.onlySystem == null) then
      foldAttrs (acc: host: acc // host) { } (
        attrValues (
          mapAttrs (
            system: hosts':
            mapAttrs (name: _: {
              inherit (splitSystem system) arch class;
              path = "${cfg.path}/${system}/${name}";
            }) hosts'
          ) hosts
        )
      )
    else
      mapAttrs (host: _: {
        inherit (splitSystem cfg.onlySystem) arch class;
        path = "${cfg.path}/${host}";
      }) hosts;

  buildHosts =
    cfg:
    let
      hostsDir = readDir cfg.path;

      hosts =
        if (cfg.onlySystem != null) then
          hostsDir
        else
          mapAttrs (path: _: readDir "${cfg.path}/${path}") (onlyDirs hostsDir);
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

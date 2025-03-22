{
  lib,
  inputs,
  withSystem,
  ...
}:
let
  inherit (inputs) self;

  inherit (builtins) readDir;
  inherit (lib)
    elemAt
    filter
    pathExists
    foldl'
    optionals
    singleton
    concatLists
    recursiveUpdate
    foldAttrs
    attrValues
    mapAttrs
    filterAttrs
    mkDefault
    evalModules
    mergeAttrs
    assertMsg
    ;

  classToOS = class: if (class == "darwin") then "darwin" else "linux";
  classToND = class: if (class == "darwin") then "darwin" else "nixos";

  redefineClass =
    cfg: class: ({ linux = "nixos"; } // (cfg.additionalClasses or { })).${class} or class;

  constructSystem =
    config: arch: class:
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
      # by the time we receive the argument here it can only be one of
      # nixos, darwin, or iso. The redefineClass function should be used prior
      # nixos, darwin. The redefineClass function should be used prior
      class,
      system,
      nixpkgs,
      nix-darwin,
      modules ? [ ],
      specialArgs ? { },
      ...
    }:
    let
      # create the modulesPath based on the system, we need
      modulesPath = if class == "darwin" then "${nix-darwin}/modules" else "${nixpkgs}/nixos/modules";

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
            # these are normal args that people expect to be passed,
            # but we expect to be evaluated when resolving module structure
            inputs

            # even though self is just the same as `inputs.self`
            # we still pass this as some people will use this
            self

            # we need to set this because some modules require it sadly
            # you may also recall `modulesPath + /installer/scan/not-detected.nix`
            modulesPath
            ;
        } specialArgs;

        # A nominal type for modules. When set and non-null, this adds a check to
        # make sure that only compatible modules are imported.
        class = classToND class;

        modules = concatLists [
          # bring in all of our base modules
          baseModules

          # import our host system paths
          (
            if path != null then
              [ path ]
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
            "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal-new-kernel.nix"
          ])

          # the next 3 singleton's are split up to make it easier to understand as they do things different things

          # recall `specialArgs` would take be preferred when resolving module structure
          # well this is how we do it use it for all args that don't need to rosolve module structure
          (singleton {
            _module.args = withSystem system (
              { self', inputs', ... }:
              {
                inherit self' inputs';
              }
            );
          })

          # some modules to have these arguments, like documentation.nix
          # <https://github.com/NixOS/nixpkgs/blob/9692553cb583e8dca46b66ab76c0eb2ada1a4098/nixos/modules/misc/documentation.nix>
          (singleton {
            _module.args = {
              inherit baseModules;

              # this should in the future be the modules that the user added without baseModules
              modules = [ ];

              # TODO: remove in 25.05
              # https://github.com/NixOS/nixpkgs/blob/9692553cb583e8dca46b66ab76c0eb2ada1a4098/nixos/lib/eval-config.nix#L38
              extraModules = [ ];
            };
          })

          # here we make some basic assumptions about the system the person is using
          # like the system type and the hostname
          (singleton {
            # we set the systems hostname based on the host value
            # which should be a string that is the hostname of the system
            networking.hostName = mkDefault name;

            nixpkgs = {
              # you can also do this as `inherit system;` with the normal `lib.nixosSystem`
              # however for evalModules this will not work, so we do this instead
              hostPlatform = mkDefault system;

              # The path to the nixpkgs sources used to build the system.
              # This is automatically set up to be the store path of the nixpkgs flake used to build
              # the system if using lib.nixosSystem, and is otherwise null by default.
              # so that means that we should set it to our nixpkgs flake output path
              flake.source = nixpkgs.outPath;
            };
          })

          # if we are on darwin we need to import the nixpkgs source, its used in some
          # modules, if this is not set then you will get an error
          (optionals (class == "darwin") (singleton {
            # without supplying an upstream nixpkgs source, nix-darwin will not be able to build
            # and will complain and log an error demanding that you must set this value
            nixpkgs.source = mkDefault nixpkgs;

            system = {
              # i don't quite know why this is set but upstream does it so i will too
              checks.verifyNixPath = false;

              # we use these values to keep track of what upstream revision we are on, this also
              # prevents us from recreating docs for the same configuration build if nothing has changed
              darwinVersionSuffix = ".${nix-darwin.shortRev or nix-darwin.dirtyShortRev or "dirty"}";
              darwinRevision = nix-darwin.rev or nix-darwin.dirtyRev or "dirty";
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
      assert assertMsg (nix-darwin != null) "nix-darwin must be set when class is darwin";
      {
        darwinConfigurations.${name} = eval // {
          system = eval.config.system.build.toplevel;
        };
      };

  foldAttrsRecursive = foldl' (acc: attrs: recursiveUpdate acc attrs) { };

  mkHosts =
    easyHostsConfig:
    foldAttrs mergeAttrs { } (
      attrValues (
        mapAttrs (
          name: hostConfig:
          let
            perClass = easyHostsConfig.perClass hostConfig.class;
          in
          mkHost {
            inherit name;

            inherit (hostConfig)
              system
              path
              nixpkgs
              nix-darwin
              ;

            class = redefineClass easyHostsConfig hostConfig.class;

            modules = concatLists [
              hostConfig.modules
              easyHostsConfig.shared.modules
              perClass.modules
            ];

            specialArgs = foldAttrsRecursive [
              hostConfig.specialArgs
              easyHostsConfig.shared.specialArgs
              perClass.specialArgs
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

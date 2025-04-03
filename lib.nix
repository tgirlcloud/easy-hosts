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
    foldAttrs
    pipe
    optionals
    singleton
    concatLists
    recursiveUpdate
    attrValues
    mapAttrs
    filterAttrs
    mkDefault
    mergeAttrs
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
      evalHost = if class == "darwin" then nix-darwin.lib.darwinSystem else nixpkgs.lib.nixosSystem;
    in
    evalHost {
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
          ;
      } specialArgs;

      modules = concatLists [
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
        }))

        # import any additional modules that the user has provided
        modules
      ];
    };

  toHostOutput =
    {
      name,
      class,
      output,
    }:
    if ((classToND class) == "nixos") then
      { nixosConfigurations.${name} = output; }
    else
      { darwinConfigurations.${name} = output; };

  foldAttrsMerge = foldAttrs mergeAttrs { };

  mkHosts =
    easyHostsConfig:
    pipe easyHostsConfig.hosts [
      (mapAttrs (
        name: hostConfig:
        let
          # memoize the class and perClass values so we don't have to recompute them
          perClass = easyHostsConfig.perClass hostConfig.class;
          class = redefineClass easyHostsConfig hostConfig.class;
        in
        toHostOutput {
          inherit name class;

          output = mkHost {
            inherit name class;

            inherit (hostConfig)
              system
              path
              nixpkgs
              nix-darwin
              ;

            modules = concatLists [
              hostConfig.modules
              easyHostsConfig.shared.modules
              perClass.modules
            ];

            specialArgs = foldAttrsMerge [
              hostConfig.specialArgs
              easyHostsConfig.shared.specialArgs
              perClass.specialArgs
            ];
          };
        }
      ))

      attrValues
      foldAttrsMerge
    ];

  normaliseHost =
    cfg: system: path:
    let
      inherit (splitSystem system) arch class;
    in
    {
      inherit arch class path;
      system = constructSystem cfg arch class;
    };

  normaliseHosts =
    cfg: hosts:
    if (cfg.onlySystem == null) then
      pipe hosts [
        (mapAttrs (system: mapAttrs (name: _: normaliseHost cfg system "${cfg.path}/${system}/${name}")))

        attrValues
        foldAttrsMerge
      ]
    else
      mapAttrs (name: _: normaliseHost cfg cfg.onlySystem "${cfg.path}/${name}") hosts;

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

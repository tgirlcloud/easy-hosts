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

  /**
    classToOS

    # Arguments

    - [class]: The class of the system. This is usually one of `nixos`, `darwin`, or `iso`.

    # Type

    ```
    classToOS :: String -> String
    ```

    # Example

    ```nix
    classToOS "darwin"
    => "darwin"
    ```

    ```nix
    classToOS "nixos"
    => "linux"
    ```
  */
  classToOS = class: if (class == "darwin") then "darwin" else "linux";

  /**
    classToND

    # Arguments

    - [class]: The class of the system. This is usually one of `nixos`, `darwin`, or `iso`.

    # Type

    ```
    classToND :: String -> String
    ```

    # Example

    ```nix
    classToND "darwin"
    => "darwin"
    ```

    ```nix
    classToND "iso"
    => "nixos"
    ```
  */
  classToND = class: if (class == "darwin") then "darwin" else "nixos";

  /**
    redefineClass

    # Arguments

    - [additionalClasses]: A set of additional classes to be used for the system.
    - [class]: The class of the system. This is usually one of `nixos`, `darwin`, or `iso`.

    # Type

    ```
    redefineClass :: AttrSet -> String -> String
    ```

    # Example

    ```nix
    redefineClass { rpi = "nixos"; } "linux"
    => "nixos"
    ```

    ```nix
    redefineClass { rpi = "nixos"; } "rpi"
    => "nixos"
    ```
  */
  redefineClass =
    additionalClasses: class: ({ linux = "nixos"; } // additionalClasses).${class} or class;

  /**
    constructSystem

    # Arguments

    - [additionalClasses]: A set of additional classes to be used for the system.
    - [arch]: The architecture of the system. This is usually one of `x86_64`, `aarch64`, or `armv7l`.
    - [class]: The class of the system. This is usually one of `nixos`, `darwin`, or `iso`.

    # Type

    ```
    constructSystem :: AttrSet -> String -> String -> String
    ```

    # Example

    ```nix
    constructSystem { rpi = "nixos"; } "x86_64" "rpi"
    => "x86_64-linux"
    ```

    ```nix
    constructSystem { rpi = "nixos"; } "x86_64" "linux"
    => "x86_64-linux"
    ```
  */
  constructSystem =
    additionalClasses: arch: class:
    let
      class' = redefineClass additionalClasses class;
      os = classToOS class';
    in
    "${arch}-${os}";

  /**
    splitSystem

    # Arguments

    - [system]: The system to be split. This is usually one of `x86_64-linux`, `aarch64-darwin`, or `armv7l-linux`.

    # Type

    ```
    splitSystem :: String -> AttrSet
    ```

    # Example

    ```nix
    splitSystem "x86_64-linux"
    => { arch = "x86_64"; class = "linux"; }
    ```

    ```nix
    splitSystem "aarch64-darwin"
    => { arch = "aarch64"; class = "darwin"; }
    ```
  */
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

  /**
    toHostOutput

    # Arguments

    - [name]: The name of the host.
    - [class]: The class of the host. This is usually one of `nixos`, `darwin`, or `iso`.
    - [output]: The output of the host.

    # Type

    ```
    toHostOutput :: AttrSet -> AttrSet
    ```

    # Example

    ```nix
      toHostOutput {
        name = "myhost";
        class = "nixos";
        output = { };
      }
      => { nixosConfigurations.myhost = { }; }
    ```
  */
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
  foldAttrsMergeRec = foldAttrs recursiveUpdate { };

  /**
    mkHosts is a function that takes a set of hosts and returns a set of host outputs.

    # Arguments

    - [easyHostsConfig]: The easy-hosts configuration.

    # Type

    ```
    mkHosts :: AttrSet -> AttrSet
    ```
  */
  mkHosts =
    easyHostsConfig:
    pipe easyHostsConfig.hosts [
      (mapAttrs (
        name: hostConfig:
        let
          # memoize the class and perClass values so we don't have to recompute them
          perClass = easyHostsConfig.perClass hostConfig.class;
          perTag = builtins.map (easyHostsConfig.perTag) hostConfig.tags;
          class = redefineClass easyHostsConfig.additionalClasses hostConfig.class;
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

            modules = concatLists (
              [
                hostConfig.modules
                easyHostsConfig.shared.modules
                perClass.modules
              ]
              ++ (builtins.map ({ modules, ... }: modules) perTag)
            );

            specialArgs = foldAttrsMergeRec (
              [
                hostConfig.specialArgs
                easyHostsConfig.shared.specialArgs
                perClass.specialArgs
              ]
              ++ (builtins.map ({ specialArgs, ... }: specialArgs) perTag)
            );
          };
        }
      ))

      attrValues
      foldAttrsMerge
    ];

  /**
    normaliseHost

    # Arguments

    - [additionalClasses]: A set of additional classes to be used for the system.
    - [system]: The system to be normalised. This is usually one of `x86_64-linux`, `aarch64-darwin`, or `armv7l-linux`.
    - [path]: The path to the host.

    # Type

    ```
    normaliseHost :: AttrSet -> String -> String -> AttrSet
    ```

    # Example

    ```nix
      normaliseHost { rpi = "nixos"; } "x86_64-linux" "/path/to/host"
      => { arch = "x86_64"; class = "linux"; path = "/path/to/host"; system = "x86_64-linux"; }
    ```
  */
  normaliseHost =
    additionalClasses: system: path:
    let
      inherit (splitSystem system) arch class;
    in
    {
      inherit arch class path;
      system = constructSystem additionalClasses arch class;
    };

  /**
    normaliseHosts is a function that takes a set of hosts and returns a set of normalised hosts.

    # Arguments

    - [cfg]: The easy-hosts configuration.
    - [hosts]: The hosts to be normalised.

    # Type

    ```
    normaliseHosts :: AttrSet -> AttrSet -> AttrSet
    ```
  */
  normaliseHosts =
    cfg: hosts:
    if (cfg.onlySystem == null) then
      pipe hosts [
        (mapAttrs (
          system:
          mapAttrs (name: _: normaliseHost cfg.additionalClasses system "${cfg.path}/${system}/${name}")
        ))

        attrValues
        foldAttrsMerge
      ]
    else
      mapAttrs (name: _: normaliseHost cfg.additionalClasses cfg.onlySystem "${cfg.path}/${name}") hosts;

  /**
    buildHosts is a function that takes a configuration and returns a set of hosts.
    It is used to build the hosts for the system.

    # Arguments

    - [cfg]: The easy-hosts configuration.

    # Type

    ```
    buildHosts :: AttrSet -> AttrSet
    ```
  */
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

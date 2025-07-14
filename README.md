# Easy Hosts

This is a nix flake module, this means that it is intended to be used alongside [flake-parts](https://flake.parts).

You can find some examples of how to use this module in the [examples](./examples) directory.

## Why use this?

We provide you with the following attributes `self'` and `inputs'` that can be used to make your configuration shorter going from writing. See the below for usage

```diff
- inputs.input-name.packages.${pkgs.system}.package-name
+ inputs'.input-name.packages.package-name

- self.packages.${pkgs.system}.package-name
+ self'.packages.package-name
```

We also can auto construct your hosts based on your file structure. Whilst providing you with a nice api which will allow you to add more settings to your hosts at a later date or consume another flake-module that can work alongside this flake.

## Explanation of the module

> [!TIP]
> You can find rendered documentation on the [flake.parts website](https://flake.parts/options/easy-hosts.html)

- `easy-hosts.autoConstruct`: If set to true, the module will automatically construct the hosts for you from the directory structure of `easy-hosts.path`.

- `easy-hosts.path`: The directory to where the hosts are stored, this *must* be set to use `easy-hosts.autoConstruct`.

- `easy-hosts.onlySystem`: If you only have 1 system type like `aarch64-darwin` then you can use this setting to prevent nesting your directories.

- `easy-hosts.shared`: The shared options for all the hosts.
  - `modules`: A list of modules that will be included in all the hosts.
  - `specialArgs`: A list of special arguments that will be passed to all the hosts.

- `easy-hosts.perClass`: This provides you with the `class` argument such that you can specify what classes get which modules.
  - `modules`: A list of modules that will be included in all the hosts of the given class.
  - `specialArgs`: A list of special arguments that will be passed to all the hosts of the given class.

- `easy-hosts.perTag`: This provides you with the `tag` argument such that you can specify what tags get which modules.
  - `modules`: A list of modules that will be included in all the hosts with the given tag.
  - `specialArgs`: A list of special arguments that will be passed to all the hosts with the given tag.

- `easy-hosts.additionalClasses`: This is an attrset of strings with mappings to any of [ "nixos", "darwin", "iso" ]. The intention here to provide a nicer api for `perClass` to operate, you may find yourself including `wsl` as a class because of this.

- `easy-hosts.hosts.<host>`: The options for the given host.
  - `path`: the path to the host, this is not strictly needed if you have a flat directory called `hosts` or `systems`.
  - `arch`: The architecture of the host.
  - `modules`: A list of modules that will be included in the host.
  - `class`: the class of the host, this can be one of [ "nixos", "darwin", "iso" ] or anything defined by `easy-hosts.additionalClasses`.
  - `tags`: tags that apply to the host, you can use this like `class`, but it allows for multiple of them to be present.
  - `specialArgs`: A list of special arguments that will be passed to the host.
  - `deployable`: this was added for people who may want to consume a deploy-rs or colmena flakeModule.

## Similar projects

- [ez-configs](https://github.com/ehllie/ez-configs)

## Real world examples

- [isabelroses/dotfiles](https://github.com/isabelroses/dotfiles)
- [uncenter/flake](https://github.com/uncenter/flake)

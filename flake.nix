{
  inputs = { };

  outputs =
    { self }:
    {
      flakeModule = import ./flake-module.nix { easy-hosts = self; };
      flakeModules.default = import ./flake-module.nix { easy-hosts = self; };

      templates = {
        multi = {
          path = ./examples/multi;
          description = "A multi-system flake with auto construction enabled, but only using x86_64-linux.";
        };

        multi-specialised = {
          path = ./examples/multi-specialised;
          description = "A multi-system flake with auto construction enabled, using the custom class system of easy-hosts";
        };

        not-auto = {
          path = ./examples/not-auto;
          description = "A flake with auto construction disabled, using only the `easyHosts.hosts` attribute.";
        };

        only = {
          path = ./examples/only;
          description = "A flake with auto construction enabled, with only one class and a more 'flat' structure.";
        };
      };
    };
}

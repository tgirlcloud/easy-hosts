{
  inputs = { };

  outputs = _: {
    flakeModule = ./flake-module.nix;

    templates = {
      multi = {
        path = ./templates/multi;
        description = "A multi-system flake with auto construction enabled, but only using x86_64-linux.";
      };

      multi-specialised = {
        path = ./templates/multi-specialised;
        description = "A multi-system flake with auto construction enabled, using the custom class system of easy-hosts";
      };

      not-auto = {
        path = ./templates/not-auto;
        description = "A flake with auto construction disabled, using only the `easyHosts.hosts` attribute.";
      };

      only = {
        path = ./templates/only;
        description = "A flake with auto construction enabled, with only one class and a more 'flat' structure.";
      };
    };
  };
}

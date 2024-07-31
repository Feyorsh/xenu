{
  description = ''
    *we've got you surrounded! install a real OS!*
    I HATE DEBIAN! I HATE DEBIAN!
  '';

  inputs = {
    # nixpkgs.url = "git+file:///Users/ghuebner/Personal/nixvm";
    nixpkgs.url = "github:NixOS/nixpkgs/master";
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixos-generators }:
    let system = "aarch64-darwin";

        dpkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
    in {
    nixosModules.base = {pkgs, ...}: {
      system.stateVersion = "23.11";

      # Configure networking
      networking.useDHCP = false;
      networking.interfaces.eth0.useDHCP = true;

      # Create user "test"
      services.getty.autologinUser = "pwny";
      users.users.pwny.isNormalUser = true;

      # Enable passwordless ‘sudo’ for the "test" user
      users.users.pwny.extraGroups = ["wheel"];
      security.sudo.wheelNeedsPassword = false;

      nix.nixPath = [
        "nixpkgs=${pkgs.path}"
      ];
      nix.channel.enable = true;
      nix.settings.experimental-features = "nix-command flakes";

      environment.systemPackages = with pkgs; [
        vim
        git
        file
        patchelf
        fd
      ];
    };
    nixosModules.vm = {pkgs, ...}: {
      # no gui
      virtualisation.vmVariant.virtualisation.graphics = false;
      virtualisation.vmVariant.virtualisation.host.pkgs = dpkgs;

      # rosetta
      virtualisation.vmVariant.virtualisation.rosetta.enable = true;
      virtualisation.vmVariant.virtualisation.fileSystems."/run/rosetta" = {
        device = "rosetta";
        fsType = "virtiofs";
      };
      # needed for gdb
      boot.kernel.sysctl = {
        "kernel.yama.ptrace_scope" = 0;
      };

      # tmpfs too small for building e.g. glibc, could change if you don't care about using nix-shell in guest
      virtualisation.vmVariant.virtualisation.writableStoreUseTmpfs = false;

      boot.initrd.availableKernelModules = [ "virtiofs" ];
    };
    nixosConfigurations.linuxVM = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        self.nixosModules.base
        self.nixosModules.vm
      ];
    };

    packages.${system} = {
      # TODO: use self.nixosConfigurations.linuxVM.config.system.build.{initialRamdisk, kernel} maybe? _NOT_ the same thing as build.vm.<...>
      linux = self.nixosConfigurations.linuxVM.config.system.build.vm;
      # xenu = dpkgs.callPackage ./xenu.nix {};

      xenu = dpkgs.callPackage ./rewrite {
        stdenv = dpkgs.darwin.overrideSDK dpkgs.stdenv {
          darwinMinVersion = "10.15";
          darwinSdkVersion = "12.3";
        };
        inherit (dpkgs.darwin.apple_sdk.frameworks) Foundation Virtualization;
      };
    };
    devShells.${system}.default = with dpkgs; mkShell {
      packages = [
        # self.packages.${system}.xenu
        # nix-output-monitor
        swiftpm
        # gdb
      ];
    };
  };
}

{
  description = ''
    *we've got you surrounded! install a real OS!*
    I HATE DEBIAN! I HATE DEBIAN!
  '';

  inputs = {
    nixpkgs.url = "git+file:///Users/ghuebner/Personal/nixvm";
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixos-generators }:
    let system = "aarch64-darwin";
        gdb_overlay = final: prev': {
          gdb = prev'.gdb.overrideAttrs (prev: {
            configurePlatforms = [ ];

            configureFlags = with prev.pkgs.lib; [
              "--program-prefix="

              "--disable-werror"
              "--target=x86_64-linux"
              "--enable-64-bit-bfd"
              "--disable-install-libbfd"
              "--disable-shared" "--enable-static"
              "--with-system-zlib"
              "--with-system-readline"

              "--with-system-gdbinit=/etc/gdb/gdbinit"
              "--with-system-gdbinit-dir=/etc/gdb/gdbinit.d"

              "--with-auto-load-safe-path=/"
            ];
            meta.platforms = prev.meta.platforms ++ [ "aarch64-darwin" ];
          });
        };

        dpkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          # overlays = [ gdb_overlay ];
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
      pwny-iso = nixos-generators.nixosGenerate {
        system = "aarch64-linux";
        format = "iso";
        modules = [
          self.nixosModules.base
          self.nixosModules.vm
        ];
      };
      pwny-vmlinux = self.nixosConfigurations.linuxVM.config.system.build.kernel;
      pwny-initrd = self.nixosConfigurations.linuxVM.config.system.build.initialRamdisk;
      fake-qemu = self.nixosConfigurations.linuxVM.config.system.build.vm;
      xenu = dpkgs.callPackage ./xenu.nix {};
    };
    devShells.${system}.default = with dpkgs; mkShell {
      packages = [
        self.packages.${system}.xenu
        # gdb
      ];
    };
  };
}

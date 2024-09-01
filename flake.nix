{
  description = ''
    *we've got you surrounded! install a real OS!*
    I HATE DEBIAN! I HATE DEBIAN!
  '';

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/master";
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixos-generators }:
    let system = "aarch64-darwin";
        inherit (nixpkgs) lib;

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
    nixosModules.vm = {pkgs, config, ...}: {
      virtualisation.vmVariant.virtualisation.graphics = false;
      virtualisation.vmVariant.virtualisation.host.pkgs = dpkgs;

      # virtualisation.vmVariant.virtualisation.rosetta.enable = true;

      # needed for gdb
      boot.kernel.sysctl = {
        "kernel.yama.ptrace_scope" = 0;
      };

      boot.initrd.availableKernelModules = [ "virtiofs" ];

      # qemu-vm.nix hardcodes the sharedDirectories as 9p; we need them to be virtiofs.
      virtualisation.vmVariant.virtualisation.fileSystems = lib.mkMerge [
        (let
          mkSharedDir = tag: share:
            {
              name = share.target;
              value = lib.mkForce {
                device = tag;
                fsType = "virtiofs";
                neededForBoot = true;
                options = lib.mkIf false [ "dax" ]; # experimental DMA in upstream, apple probably doesn't support it though
              };
            };
        in
          lib.mapAttrs' mkSharedDir config.virtualisation.vmVariant.virtualisation.sharedDirectories)

        # this shouldn't be necessary, and yet it is.
        { "/run/rosetta" = {
            device = "rosetta";
            fsType = "virtiofs";
          }; }
      ];

      # Evil, evil hack! Basically impossible to remove stuff from another module's attrset...
      # There's really no point to the xchg shared directory; it's a holdover from ages ago.
      virtualisation.vmVariant.virtualisation.sharedDirectories = lib.mkForce {
        nix-store = lib.mkIf config.virtualisation.vmVariant.virtualisation.mountHostNixStore {
          source = builtins.storeDir;
          target = "/nix/.ro-store";
          securityModel = "none";
        };
        shared = {
          source = ''"''${SHARED_DIR:-$TMPDIR/xchg}"'';
          target = "/tmp/shared";
          securityModel = "none";
        };
        certs = lib.mkIf config.virtualisation.vmVariant.virtualisation.useHostCerts {
          source = ''"$TMPDIR"/certs'';
          target = "/etc/ssl/certs";
          securityModel = "none";
        };
      };

      # tmpfs too small for building e.g. glibc, could change if you don't care about using nix-shell in guest
      # virtualisation.vmVariant.virtualisation.writableStoreUseTmpfs = false;
    };

    nixosConfigurations.linuxVM = lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        self.nixosModules.base
        self.nixosModules.vm
      ];
    };

    nixosConfigurations.x86linuxVM = lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        self.nixosModules.base
        self.nixosModules.vm
      ];
    };

    apps.${system} = {
      genStoreImg = {
        type = "app";
        program = (dpkgs.writeShellScript "createNixStoreImage" ''
          ${dpkgs.qemu-utils}/bin/qemu-img create -f raw nixos.raw 5120M
          ${dpkgs.e2fsprogs}/bin/mkfs.ext4 -L nixos nixos.raw
        '').outPath;
      };
      kernelParams = {
        type = "app";
        program = (dpkgs.writeShellScript "qemuAppend" ''
          echo ${lib.findFirst (lib.hasPrefix "-append") null self.nixosConfigurations.linuxVM.config.virtualisation.vmVariant.virtualisation.qemu.options}
        '').outPath;
      };
    };

    packages.${system} = {
      # TODO: use self.nixosConfigurations.linuxVM.config.system.build.{initialRamdisk, kernel} maybe? _NOT_ the same thing as build.vm.<...>
      linux = self.nixosConfigurations.linuxVM.config.system.build.vm;
      x86linux = self.nixosConfigurations.x86linuxVM.config.system.build.vm;

      xenu = dpkgs.callPackage ./rewrite { xcode = dpkgs.darwin.xcode_15_1; };
    };
    devShells.${system}.default = with dpkgs; mkShell {
      packages = [
        # self.packages.${system}.xenu
        # gdb
      ];
    };
  };
}

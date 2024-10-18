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

        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

        pkgsCross = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          config.allowUnsupportedSystem = true; # for gdb
          crossSystem = "x86_64-linux";
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
      virtualisation.vmVariant.virtualisation.host.pkgs = pkgs;

      virtualisation.vmVariant.virtualisation.rosetta.enable = true;

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

    apps.${system} = {
      vm = {
        type = "app";
        program = lib.getExe self.packages.${system}.vm;
      };
    };

    packages.${system} = rec {
      # TODO: use self.nixosConfigurations.linuxVM.config.system.build.{initialRamdisk, kernel} maybe? _NOT_ the same thing as build.vm.<...>
      linux = self.nixosConfigurations.linuxVM.config.system.build.vm;

      xenu = pkgs.darwin.callPackage ./xenu { xcode = pkgs.darwin.xcode_15_1; };

      vm = let
        script = { xenu, kernel, initrd, cmdline, storeImgSize }: pkgs.writeShellScriptBin "vm" ''
          NIX_STORE_IMAGE=$(readlink -f "''${NIX_STORE_IMAGE:-./nixos.raw}") || test -z "$NIX_STORE_IMAGE"
          if test -n "$NIX_STORE_IMAGE" && ! test -e "$NIX_STORE_IMAGE"; then
              ${pkgs.qemu-utils}/bin/qemu-img create -f raw nixos.raw "${toString storeImgSize}M"
              ${pkgs.e2fsprogs}/bin/mkfs.ext4 -L nixos nixos.raw
          fi

          ${xenu}/bin/xenu --kernel ${kernel} --initrd ${initrd} --store-image ./nixos.raw --append ${cmdline}
        '';
        linux = self.nixosConfigurations.linuxVM.config.system.build.vm;
        kernel_cmdline = lib.removePrefix "-append " (lib.findFirst (lib.hasPrefix "-append ") null self.nixosConfigurations.linuxVM.config.virtualisation.vmVariant.virtualisation.qemu.options);
      in
        lib.makeOverridable script {
          xenu = xenu;
          kernel = "${linux}/system/kernel";
          initrd = "${linux}/system/initrd";
          cmdline = kernel_cmdline;
          storeImgSize = 5120;
        };
    };
    devShells.${system} = rec {
      x86Shell = pkgsCross.callPackage ({ mkShell, gdb, glibc, patchelf, autoPatchelfHook }: mkShell {
        # these tools run on the build platform, but are configured to target the host platform
        nativeBuildInputs = [ gdb patchelf autoPatchelfHook ];
        # libraries needed for the host platform
        buildInputs = [ glibc ];
      }) {};
      default = x86Shell;
      vcs = with pkgs; mkShellNoCC {
        packages = [
          gh
          darwin.sigtool
          self.packages.${system}.xenu
        ];
      };
    };
    };
}

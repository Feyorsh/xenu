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
    # fyshpkgs = {
    #   url = "git+file:///Users/ghuebner/Personal/fyshpkgs";
	  #   inputs.nixpkgs.follows = "nixpkgs";
    # };
  };

  outputs = { self, nixpkgs, nixos-generators }:
    let system = "aarch64-darwin";
        gdb_overlay = final: prev': {
          gdb = prev'.gdb.overrideAttrs (prev: {
            configurePlatforms = [];

            configureFlags = with prev.pkgs.lib; [
              # Set the program prefix to the current targetPrefix.
              # This ensures that the prefix always conforms to
              # nixpkgs' expectations instead of relying on the build
              # system which only receives `config` which is merely a
              # subset of the platform description.
              #"--program-prefix=${prev.targetPrefix}"
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

              #"--with-gmp=${prev.gmp.dev}"
              #"--with-mpfr=${prev.mpfr.dev}"
              #"--with-expat" "--with-libexpat-prefix=${prev.expat.dev}"
              "--with-auto-load-safe-path=/"
            ];
            # iggy = pkgs.writeText "ignore-errors.py" ''
            #     class IgnoreErrorsCommand (gdb.Command):
            #         """Execute a single command, ignoring all errors.
            #     Only one-line commands are supported.
            #     This is primarily useful in scripts."""

            #         def __init__ (self):
            #             super (IgnoreErrorsCommand, self).__init__ ("ignore-errors",
            #                                                         gdb.COMMAND_OBSCURE,
            #                                                         # FIXME...
            #                                                         gdb.COMPLETE_COMMAND)

            #         def invoke (self, arg, from_tty):
            #             try:
            #                 gdb.execute (arg, from_tty)
            #             except:
            #                 pass

            #     IgnoreErrorsCommand ()
            # '';
            # postInstall = prev.postInstall + ''
            #   cp $iggy $out/share/gdb/python/ignore-errors.py
            # '';
            meta.platforms = prev.meta.platforms ++ [ "aarch64-darwin" ];
          });
          # pwndbg = prev'.pwndbg.overrideAttrs (prev: {
          #   binPath = pkgs.lib.makeBinPath ( with pkgs; [
          #     python3.pkgs.pwntools
          #     python3.pkgs.ropper
          #     python3.pkgs.ropgadget
          #   ]);
          #   meta.broken = false;
          # });
          # gef = prev'.gef.overrideAttrs (prev: let
          #   pythonPath = with prev'.python3.pkgs; makePythonPath [
          #     keystone-engine
          #     unicorn
          #     capstone
          #     final.python3.pkgs.ropper
          #   ];
          # in {
          #   installPhase = ''
          #     mkdir -p $out/share/gef
          #     cp gef.py $out/share/gef
          #     makeWrapper ${pkgs.gdb}/bin/gdb $out/bin/gef \
          #     --add-flags "-q -x $out/share/gef/gef.py" \
          #     --set NIX_PYTHONPATH ${pythonPath} \
          #     --prefix PATH : ${prev'.lib.makeBinPath [
          #         prev'.python3
          #         #bintools-unwrapped # for readelf
          #         final.python3.pkgs.pyelftools
          #         prev'.file
          #         prev'.ps
          #     ]}
          # '';
          # });
          # python3 = prev'.python3.override {
          #   packageOverrides = python-self: python-super: {
          #     ropper = python-super.ropper.overrideAttrs (oldAttrs: {
          #       meta.broken = false;
          #     });
          #     pyelftools = python-super.pyelftools.overrideAttrs (oldAttrs: {
          #       # nativeBuildInputs = oldAttrs.nativeBuildInputs ++ [
          #       #   prev'.makeBinaryWrapper
          #       # ];
          #       # installPhase = ''
          #       #   makeBinaryWrapper $out/bin/readelf.py $out/bin/readelf
          #       # '';
          #       postInstall = ''
          #         cp $out/bin/readelf.py $out/bin/readelf
          #       '';
          #     });
          #   };
          # };
        };

        dpkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [ gdb_overlay ];
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
        # pkgsCross.gnu64.glibc
      ];

      # virtualisation.vmVariant.virtualisation.fileSystems = pkgs.lib.mkForce { };
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

      # tmpfs too small for building e.g. glibc, could change if dependencies weren't dynamic
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
    };
    devShells.${system}.default = with dpkgs; mkShell {
      packages = [
        # swift
        darwin.xcode_15_1
        # utm
        gdb
      ];
    };
  };
}

# Apple virtualization and emulation workbench.
#
# Three separate things live here, and they are genuinely unrelated to one
# another beyond both concerning Apple devices:
#
#   iosvm            experimental iOS virtual machines, on Inferno
#                    (ChefKissInc's QEMU fork for Apple Silicon SoCs).
#   macosvm          macOS virtual machines, on OSX-KVM's OpenCore workflow
#                    and stock QEMU/KVM.
#   legacy-ios-kit   LukeZGD's toolkit for *physical* legacy Apple devices.
#                    It emulates nothing; it talks to real hardware over USB.
#
# Plus the QEMU/libvirt/virt-manager foundation all of this sits on.
#
# No Apple firmware, IPSW or installer media is packaged, fetched or
# redistributed by anything in this module. See the per-tool documentation for
# what the user must supply and where each tool expects to find it.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  user = config.workstation.username;
  inferno = pkgs.callPackage ../packages/apple/inferno.nix { };

  # A self-contained flake in the store from which `iosvm companion build`
  # builds the companion guest.
  #
  # The obvious source would be /etc/nixos itself, and that is what iosvm
  # tried first -- but Nix's path: fetcher copies the *whole* directory, and
  # this one contains root-only backup directories. A non-root user therefore
  # cannot evaluate /etc/nixos as a flake at all ("cannot read directory
  # .../backup-comprehensive-...: Permission denied"), and loosening those
  # permissions to work around it would be the wrong trade.
  #
  # This derivation contains only the companion module and the same flake.lock
  # as the host, so it pins the identical nixpkgs, is world-readable, and is
  # immune to whatever else ends up in /etc/nixos later.
  hostLock = builtins.fromJSON (builtins.readFile ../flake.lock);
  nixpkgsNode = hostLock.nodes.nixpkgs;

  # A lock with only the nixpkgs node, carrying the host's exact pin.
  #
  # Copying the host's flake.lock verbatim does not work: it also locks `boo`
  # and `durdraw`, which this flake does not declare, so Nix decides the lock
  # is stale and tries to rewrite it -- inside the store, which is read-only.
  # Generating a lock that matches this flake's inputs exactly leaves nothing
  # for Nix to update.
  companionLock = builtins.toJSON {
    version = 7;
    root = "root";
    nodes = {
      root.inputs.nixpkgs = "nixpkgs";
      nixpkgs = {
        inherit (nixpkgsNode) locked original;
      };
    };
  };

  companionFlake = pkgs.runCommand "iosvm-companion-flake" {
    flakeLock = companionLock;
    passAsFile = [ "flakeLock" ];
  } ''
    mkdir -p $out
    cp "$flakeLockPath" $out/flake.lock
    cp ${../modules/iosvm-companion.nix} $out/iosvm-companion.nix
    cp ${../packages/apple/inferno.nix} $out/inferno.nix
    cat > $out/flake.nix <<'EOF'
    {
      description = "iosvm companion VM";
      inputs.nixpkgs.url = "${nixpkgsNode.original.url}";
      outputs = { self, nixpkgs }: {
        nixosConfigurations.iosvm-companion = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./iosvm-companion.nix
            ({ pkgs, ... }: {
              virtualisation.qemu.package = pkgs.callPackage ./inferno.nix { };
            })
          ];
        };
      };
    }
    EOF
  '';
  appleVmTools = pkgs.callPackage ../packages/apple/vm-tools.nix { inherit inferno; };
  legacyIosKit = pkgs.callPackage ../packages/apple/legacy-ios-kit.nix { };

  # Launcher icons for the three tools, installed into the hicolor theme.
  appleVmIcons = pkgs.callPackage ../packages/apple/icons.nix { };

  # udev access for Apple devices in DFU and Recovery mode.
  #
  # Two reasons this file exists rather than relying on the packaged rules:
  #
  #   1. nixpkgs' libirecovery ships 39-libirecovery.rules with an
  #      unsubstituted upstream placeholder -- `GROUP="myusergroup"`, a group
  #      that does not exist on any system. udev cannot resolve it, so a device
  #      in DFU or Recovery mode ends up root-owned and mode 0660: unreachable
  #      for a normal user, which is exactly when Legacy iOS Kit needs it.
  #
  #   2. Legacy iOS Kit checks for this specific path and, when it is absent,
  #      tries to create it with `/usr/bin/sudo` -- which does not exist on
  #      NixOS, and could not elevate from inside its FHS sandbox anyway.
  #      Providing the file declaratively makes that code path a no-op.
  #
  # `TAG+="uaccess"` is used rather than upstream's `MODE:="0666"`: logind
  # grants the user at the active seat access to the device, instead of making
  # every Apple device on the machine world-writable.
  appleDeviceUdevRules = pkgs.writeTextFile {
    name = "apple-device-udev-rules";
    destination = "/lib/udev/rules.d/99-libirecovery.rules";
    text = ''
      # Apple devices in normal, Recovery and DFU mode, plus checkra1n DFU.
      # Access is granted to the user at the active seat via logind.
      SUBSYSTEM=="usb", ATTR{idVendor}=="05ac", TAG+="uaccess"
    '';
  };

  # Terminal launchers. These open the tool's overview and then drop into a
  # shell, rather than pretending to be a GUI: both CLIs are interactive, and a
  # desktop entry that flashes a window and vanishes is worse than none.
  #
  # Each Exec is a real script rather than an inline shell snippet, because the
  # desktop-entry spec reserves ';' and quotes in Exec values -- an inline
  # `cmd; exec bash` fails desktop-file-validate outright.
  terminal = "${pkgs.ghostty}/bin/ghostty";

  overviewLauncher =
    name: tool:
    pkgs.writeShellScript "${name}-launcher" ''
      ${appleVmTools}/bin/${tool} list || true
      echo
      echo "Try: ${tool} help"
      echo
      exec ${pkgs.bashInteractive}/bin/bash
    '';

  iosvmDesktop = pkgs.makeDesktopItem {
    name = "iosvm";
    desktopName = "iOS VM Manager";
    comment = "Experimental iOS virtual machines (Inferno / QEMU Apple Silicon)";
    # Provided by appleVmIcons, in the hicolor theme.
    icon = "iosvm";
    exec = "${terminal} -e ${overviewLauncher "iosvm" "iosvm"}";
    terminal = false;
    categories = [
      "System"
      "Emulator"
    ];
    keywords = [
      "iOS"
      "iPhone"
      "emulator"
      "QEMU"
    ];
  };

  macosvmDesktop = pkgs.makeDesktopItem {
    name = "macosvm";
    desktopName = "macOS VM Manager";
    comment = "macOS virtual machines (OSX-KVM / QEMU)";
    icon = "macosvm";
    exec = "${terminal} -e ${overviewLauncher "macosvm" "macosvm"}";
    terminal = false;
    categories = [
      "System"
      "Emulator"
    ];
    keywords = [
      "macOS"
      "OSX"
      "emulator"
      "QEMU"
    ];
  };

  legacyIosKitDesktop = pkgs.makeDesktopItem {
    name = "legacy-ios-kit";
    desktopName = "Legacy iOS Kit";
    comment = "Restore, downgrade and jailbreak physical legacy Apple devices";
    # Provided by appleVmIcons, in the hicolor theme. The previous value,
    # "phone", is a generic icon name that no installed theme here defines, so
    # the entry rendered with the launcher's missing-icon placeholder.
    icon = "legacy-ios-kit";
    exec = "${terminal} -e ${legacyIosKit}/bin/legacy-ios-kit";
    terminal = false;
    # One main category only: "System;Utility" makes the entry show up twice
    # in menus that group by main category.
    categories = [ "System" ];
    keywords = [
      "iOS"
      "iPhone"
      "iPad"
      "iPod"
      "restore"
      "jailbreak"
      "DFU"
    ];
  };
in
{
  # ===================================================== QEMU / libvirt ===
  virtualisation.libvirtd = {
    enable = true;
    # Leave guests running across a rebuild of the host: switching
    # configuration should not take down a macOS VM mid-install.
    onBoot = "ignore";
    onShutdown = "shutdown";

    qemu = {
      # Stock QEMU for libvirt. Inferno is not used here: its Apple machines
      # are driven directly by iosvm, and libvirt has no model for them.
      package = pkgs.qemu_kvm;
      # Run guests as the unprivileged qemu-libvirtd user rather than root.
      runAsRoot = false;
      # Software TPM, so a libvirt-managed guest can have a vTPM.
      swtpm.enable = true;
    };

    # This host's firewall is the iptables-backed NixOS default (networking.nftables
    # is not enabled), so libvirt's virtual networks must use the same backend;
    # mixing the two produces rules that look present but never match.
    firewallBackend = "iptables";
  };

  # OVMF/UEFI firmware for libvirt guests comes from the QEMU package itself in
  # this nixpkgs: the `virtualisation.libvirtd.qemu.ovmf` submodule was removed
  # and all OVMF images shipped with QEMU are exposed automatically. Nothing to
  # declare here, and declaring it would now be an evaluation error.

  programs.virt-manager.enable = true;

  # libvirt ships a "default" NAT network but leaves it stopped and without
  # autostart, so a freshly created guest has no network until someone runs
  # `virsh net-start default` by hand. Marking it autostart is the declarative
  # equivalent; libvirtd starts it from there on boot.
  #
  # It uses 192.168.122.0/24, which is why iosvm's reverse-tethering subnet
  # defaults to 192.168.178.0/24 instead -- the two must not overlap.
  systemd.services.libvirtd.postStart = ''
    ${config.virtualisation.libvirtd.package}/bin/virsh net-autostart default || true
    ${config.virtualisation.libvirtd.package}/bin/virsh net-start default || true
  '';

  # macOS probes model-specific registers that KVM does not implement, and
  # faults if KVM injects #GP for them. OSX-KVM's kvm.conf sets this with a
  # modprobe option; this is the declarative equivalent. `nested=1` gives
  # guests usable nested virtualization, which is what Docker Desktop and
  # Xcode's simulators inside a macOS guest need.
  #
  # Applied at module load: `modprobe -r kvm_intel kvm` and a reload, or a
  # reboot. `macosvm doctor` reports the live value, not the configured one.
  boot.extraModprobeConfig = ''
    options kvm ignore_msrs=1 report_ignored_msrs=0
    options kvm_intel nested=1 emulate_invalid_guest_state=0
  '';

  # ============================================== APFS read-write driver ===
  # linux-apfs-rw, built against this machine's running kernel by nixpkgs
  # rather than insmod'ed from a downloaded blob. It is made available but not
  # autoloaded: it is an out-of-tree filesystem driver that is only needed
  # while patching an iOS root volume, and iosvm loads it on demand.
  #
  # If a future kernel bump breaks the build, this is the line to comment out;
  # everything else in the module keeps working, and `iosvm doctor` reports
  # the driver as unavailable rather than failing.
  boot.extraModulePackages = [ config.boot.kernelPackages.apfs ];

  # =============================================== physical Apple devices ===
  # usbmuxd on the host, for Legacy iOS Kit and the libimobiledevice tools
  # talking to real hardware over USB. The emulated device does not use this:
  # its USB goes to the companion VM instead.
  services.usbmuxd.enable = true;

  # ============================================================= groups ===
  # libvirtd for virt-manager and virsh without sudo; kvm for /dev/kvm (already
  # granted in modules/android-workstation.nix -- NixOS merges these lists, so
  # it is not duplicated); input for the evdev passthrough OSX-KVM's optional
  # setups use.
  users.users.${user}.extraGroups = [
    "libvirtd"
    "kvm"
    "input"
  ];

  # =========================================================== packages ===
  environment.systemPackages = [
    # The three tools this module exists for.
    appleVmTools
    legacyIosKit

    # Inferno is available for manual use, but must not win the system PATH: it
    # installs qemu-system-x86_64, qemu-img and friends too, and everyone else
    # should get stock QEMU rather than a fork maintained for iOS emulation.
    # lowPrio alone is not enough -- nixpkgs already ships qemu_kvm at
    # priority 10, so the two would tie and the winner would be arbitrary.
    # Stock QEMU is raised instead (see hiPrio below), and iosvm is unaffected
    # either way: its wrapper puts Inferno first on its own PATH.
    (lib.lowPrio inferno)

    # Desktop entries and their icons.
    iosvmDesktop
    macosvmDesktop
    legacyIosKitDesktop
    appleVmIcons
  ]
  ++ (with pkgs; [
    # --- virtualization stack -------------------------------------------
    (lib.hiPrio qemu_kvm) # must outrank Inferno for qemu-system-x86_64
    qemu-utils
    virt-manager
    virt-viewer
    spice
    spice-gtk
    spice-protocol
    virtio-win # virtio drivers, useful for any non-Apple guest
    swtpm
    OVMFFull
    virtiofsd
    libguestfs-with-appliance # virt-df, guestfish, virt-cat for VM disks
    dnsmasq
    bridge-utils
    iproute2
    iptables
    nftables
    usbutils
    socat
    dmg2img # OSX-KVM's documented recovery-image converter

    # --- Apple device tooling -------------------------------------------
    # These are the NixOS equivalents of the packages the upstream guides
    # install from AUR or build from source. The full libimobiledevice stack
    # is packaged in nixpkgs, and at recent revisions.
    usbmuxd
    libimobiledevice
    libimobiledevice-glue
    libirecovery
    libplist
    libtatsu
    libusbmuxd
    idevicerestore
    ifuse
    ideviceinstaller

    # --- general tooling the guides call for -----------------------------
    p7zip
    zstd
    xz
    rsync
    jq
    curl
    wget
    git
    python3
    openssh
    pciutils
  ]);

  # ============================================================== udev ===
  # Apple devices in normal, recovery and DFU mode, accessible to the console
  # user without sudo. The libimobiledevice and libirecovery packages ship the
  # rules; this makes NixOS install them.
  services.udev.packages = [
    pkgs.libimobiledevice
    pkgs.libirecovery
    pkgs.usbmuxd
    # Must come after libirecovery: 99- sorts later than its broken 39- rule,
    # so uaccess is applied last and wins.
    appleDeviceUdevRules
  ];

  # =========================================== companion VM flake source ===
  # Where `iosvm companion build` looks by default. Overridable per user with
  # `iosvm config set companion_flake <path>`.
  environment.sessionVariables.IOSVM_COMPANION_FLAKE = "${companionFlake}";

  # ============================================================== docs ===
  environment.etc."apple-virtualization/README".source = ../packages/apple/HOST-README.md;
}

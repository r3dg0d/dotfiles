# NixOS Updater + Storage Optimizer as ordinary desktop utilities:
#   - standalone apps in the launcher (nixos-updater, storage-optimizer)
#   - a small Quickshell widget strip in Ambxst's bar (its own Quickshell
#     instance — not an Ambxst mod)
#   - Rust helpers shared by both, with a narrowly scoped pkexec path for the
#     few operations that need root.
# These replaced the Ambxst mods com.zionsec.nixos-updater and
# com.zionsec.storage-optimizer (removed with `ambxst mods remove`).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.zionsec.desktopTools;
  tools = pkgs.callPackage ../packages/desktop-tools { };
  kver = config.boot.kernelPackages.kernel.version;

  # Root-owned facts the privileged helper trusts (it never takes paths from
  # the user's config). Evaluated from the real system configuration.
  systemJson = builtins.toJSON {
    flakePath = cfg.flakePath;
    flakeAttr = config.networking.hostName;
    kernelAttr = "boot.kernelPackages (linux ${lib.versions.majorMinor kver})";
    kernelBranch = lib.versions.majorMinor kver;
    kernelVersion = kver;
    ambxstPinFile = "${cfg.flakePath}/modules/ambxst.nix";
    stateDir = "/var/lib/nixos-updater";
  };

  # pkexec shows these messages and only accepts these exact binaries.
  polkitActions = pkgs.writeTextDir "share/polkit-1/actions/org.zionsec.desktop-tools.policy" ''
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE policyconfig PUBLIC "-//freedesktop//DTD PolicyKit Policy Configuration 1.0//EN"
      "http://www.freedesktop.org/standards/PolicyKit/1/policyconfig.dtd">
    <policyconfig>
      <vendor>zionsec</vendor>
      <action id="org.zionsec.nixos-updater.privileged">
        <description>Update and rebuild NixOS</description>
        <message>NixOS Updater needs permission to update flake inputs and rebuild the system</message>
        <icon_name>system-software-update</icon_name>
        <defaults>
          <allow_any>no</allow_any>
          <allow_inactive>no</allow_inactive>
          <allow_active>auth_admin_keep</allow_active>
        </defaults>
        <annotate key="org.freedesktop.policykit.exec.path">${tools.updaterHelper}</annotate>
      </action>
      <action id="org.zionsec.storage-optimizer.privileged">
        <description>Clean up system storage</description>
        <message>Storage Optimizer needs permission to remove old NixOS generations, collect Nix garbage and vacuum the journal</message>
        <icon_name>drive-harddisk</icon_name>
        <defaults>
          <allow_any>no</allow_any>
          <allow_inactive>no</allow_inactive>
          <allow_active>auth_admin_keep</allow_active>
        </defaults>
        <annotate key="org.freedesktop.policykit.exec.path">${tools.storageHelper}</annotate>
      </action>
    </policyconfig>
  '';
in
{
  options.zionsec.desktopTools = {
    flakePath = lib.mkOption {
      type = lib.types.str;
      default = "/etc/nixos";
      description = "Flake the updater locks and rebuilds (attribute = networking.hostName).";
    };
    widgets = {
      enable = lib.mkEnableOption "the Quickshell widget strip in the bar" // { default = true; };
      side = lib.mkOption {
        type = lib.types.enum [ "left" "right" ];
        default = "left";
        description = "Bar edge the strip is anchored to.";
      };
      offset = lib.mkOption {
        type = lib.types.int;
        # Ambxst's left cluster (launcher, 10 workspaces, pin) ends at x=411
        # on this 3440px bar; 5px matches Ambxst's own pill gap.
        default = 416;
        description = "Distance in px from that edge.";
      };
      top = lib.mkOption {
        type = lib.types.int;
        default = 4;
        description = "Top margin in px (Ambxst's 36px pills sit 4px into its 40px bar).";
      };
      show = lib.mkOption {
        type = lib.types.listOf (lib.types.enum [ "updater" "storage" ]);
        default = [ "updater" "storage" ];
      };
    };
    updateTimer = lib.mkEnableOption "the hourly tick for background update checks (the helper only checks when interval_hours has elapsed)" // { default = true; };
  };

  config = {
    environment.systemPackages = [
      tools
      polkitActions
    ];

    environment.etc."nixos-updater/system.json".text = systemJson;

    # Backups of flake.nix/flake.lock taken before the updater changes them,
    # and the build result link. Root only.
    systemd.tmpfiles.rules = [ "d /var/lib/nixos-updater 0700 root root -" ];

    # pkexec needs an authentication agent in the session. The widget shell is
    # that agent (Quickshell PolkitAgent, a password prompt styled like the
    # shell on the overlay layer). Only one agent can register per session,
    # so hyprpolkitagent is only the fallback when the widgets are disabled.
    systemd.packages = lib.mkIf (!cfg.widgets.enable) [ pkgs.hyprpolkitagent ];
    systemd.user.services.hyprpolkitagent = lib.mkIf (!cfg.widgets.enable) {
      wantedBy = [ "graphical-session.target" ];
    };

    systemd.user.services.zionsec-tools-widgets = lib.mkIf cfg.widgets.enable {
      description = "Quickshell widgets for NixOS Updater and Storage Optimizer";
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      unitConfig.ConditionEnvironment = "WAYLAND_DISPLAY";
      serviceConfig = {
        ExecStart = tools.widgetsExe;
        Restart = "on-failure";
        RestartSec = 3;
        Environment = [
          "ZS_WIDGETS_SIDE=${cfg.widgets.side}"
          "ZS_WIDGETS_OFFSET=${toString cfg.widgets.offset}"
          "ZS_WIDGETS_TOP=${toString cfg.widgets.top}"
          "ZS_WIDGETS_SHOW=${lib.concatStringsSep "," cfg.widgets.show}"
        ];
      };
    };

    # Background update check: fires hourly, exits immediately unless
    # [checks] automatic = true and interval_hours have passed. No daemon.
    systemd.user.services.nixos-updater-check = {
      description = "NixOS Updater: scheduled read-only update check";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${tools.updaterHelper} check --scheduled";
        Nice = 10;
        IOSchedulingClass = "idle";
        TimeoutStartSec = "5min";
      };
    };
    systemd.user.timers.nixos-updater-check = lib.mkIf cfg.updateTimer {
      description = "NixOS Updater: scheduled update check tick";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnStartupSec = "10min";
        OnUnitActiveSec = "1h";
        RandomizedDelaySec = "5min";
      };
    };
  };
}

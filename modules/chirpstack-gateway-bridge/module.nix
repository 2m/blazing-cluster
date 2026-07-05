{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.chirpstack-gateway-bridge;

  defaultPkg = pkgs.callPackage ../../pkgs/chirpstack-gateway-bridge/package.nix { };

  configDir = cfg.configDir;

  configSource =
    if cfg.configFile != null then
      cfg.configFile
    else
      pkgs.writeText "gateway-bridge.toml" cfg.configText;

  exec = lib.concatStringsSep " " (
    [
      "${cfg.package}/bin/${cfg.binaryName}"
      "-c"
      "${configDir}/gateway-bridge.toml"
    ]
    ++ cfg.extraArgs
  );
in
{
  options.services.chirpstack-gateway-bridge = {
    enable = lib.mkEnableOption "ChirpStack Gateway Bridge";

    package = lib.mkOption {
      type = lib.types.package;
      default = defaultPkg;
      description = "Package providing chirpstack-gateway-bridge.";
    };

    binaryName = lib.mkOption {
      type = lib.types.str;
      default = "chirpstack-gateway-bridge";
      description = "Binary name inside the package /bin.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "chirpstack";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "chirpstack";
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/chirpstack-gateway-bridge";
      description = "Writable state directory (logs/runtime files if configured).";
    };

    configDir = lib.mkOption {
      type = lib.types.str;
      default = "/etc/chirpstack-gateway-bridge";
      description = "Directory containing gateway-bridge.toml.";
    };

    configFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to gateway-bridge.toml to install into configDir.";
    };

    configText = lib.mkOption {
      type = lib.types.lines;
      default = ''
        # Provide TOML via services.chirpstack-gateway-bridge.configFile
        # or override this inline TOML.
      '';
      description = "Inline gateway-bridge.toml content used when configFile is null.";
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra CLI args passed to chirpstack-gateway-bridge.";
    };

    # Minimal dependency: MQTT broker. We’ll just wait for mosquitto.service.
    waitForMosquitto = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Make the service wait for mosquitto.service.";
    };
  };

  config = lib.mkIf cfg.enable {

    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0750 ${cfg.user} ${cfg.group} - -"
      "d ${cfg.configDir} 0755 root root - -"
    ];

    environment.etc."chirpstack-gateway-bridge/gateway-bridge.toml" = {
      source = configSource;
      mode = "0644";
    };

    systemd.services.chirpstack-gateway-bridge = {
      description = "ChirpStack Gateway Bridge";
      wantedBy = [ "multi-user.target" ];

      after = [ "network-online.target" ] ++ lib.optional cfg.waitForMosquitto "mosquitto.service";

      wants = [ "network-online.target" ] ++ lib.optional cfg.waitForMosquitto "mosquitto.service";

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.stateDir;

        ExecStart = exec;

        Restart = "on-failure";
        RestartSec = 2;

        NoNewPrivileges = true;
        ProtectSystem = "no";
        ReadWritePaths = [ cfg.stateDir ];
      };
    };
  };
}

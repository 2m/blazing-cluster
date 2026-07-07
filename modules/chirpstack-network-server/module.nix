{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.chirpstack-network-server;

  defaultPkg = pkgs.callPackage ../../pkgs/chirpstack-network-server/package.nix { };

  configDir = cfg.configDir;

  tomlFormat = pkgs.formats.toml { };

  defaultSettings = import ./chirpstack.nix;
  defaultRegion = import ./region.nix;

  mergedSettings = lib.recursiveUpdate defaultSettings cfg.settings;
  mergedRegion = lib.recursiveUpdate defaultRegion cfg.region;

  configSource = tomlFormat.generate "chirpstack.toml" mergedSettings;

  generatedRegionFiles = lib.mapAttrsToList (name: regionConfig: {
    "chirpstack/region_${name}.toml" = {
      source = tomlFormat.generate "region_${name}.toml" { regions = [ regionConfig ]; };
      mode = "0644";
    };
  }) mergedRegion;

  exec = lib.concatStringsSep " " (
    [
      "${cfg.package}/bin/${cfg.binaryName}"
      "-c"
      configDir
    ]
    ++ cfg.extraArgs
  );
in
{
  options.services.chirpstack-network-server = {
    enable = lib.mkEnableOption "ChirpStack Network Server (SQLite upstream binary)";

    package = lib.mkOption {
      type = lib.types.package;
      default = defaultPkg;
      description = "Package providing the ChirpStack server binary.";
    };

    binaryName = lib.mkOption {
      type = lib.types.str;
      default = "chirpstack-network-server";
      description = "Binary name inside the package's /bin.";
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
      default = "/var/lib/chirpstack";
      description = "Writable state directory (SQLite db, etc).";
    };

    configDir = lib.mkOption {
      type = lib.types.str;
      default = "/etc/chirpstack";
      description = "Directory passed to ChirpStack via -c. Must contain chirpstack.toml.";
    };

    settings = lib.mkOption {
      type = tomlFormat.type;
      default = { };
      description = ''
        chirpstack.toml configuration overrides expressed as a Nix attribute set.
        These values are recursively merged into the default configuration.
      '';
      example = lib.literalExpression ''
        {
          integration.mqtt.server = "tcp://127.0.0.1:1883/";
          network.enabled_regions = [ "eu868" ];
        }
      '';
    };

    region = lib.mkOption {
      type = lib.types.attrsOf tomlFormat.type;
      default = { };
      description = ''
        Region configuration overrides expressed as Nix attribute sets.
        These values are recursively merged into the default region configurations.
        Each top-level attribute is generated as region_<name>.toml using the
        contents of that attribute.
      '';
      example = lib.literalExpression ''
        {
          eu868 = {
            name = "eu868";
            common_name = "EU868";
            gateway.backend.mqtt.server = "tcp://127.0.0.1:1883";
          };
        }
      '';
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra CLI args passed to the chirpstack binary.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open uiPort in the firewall (TCP).";
    };

    uiPort = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Port to open when openFirewall=true. Must match your TOML bind.";
    };
  };

  config = lib.mkIf cfg.enable {

    # Create user/group
    users.groups.${cfg.group} = { };
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      home = cfg.stateDir;
      createHome = true;
    };

    # Ensure dirs exist with sane perms
    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0750 ${cfg.user} ${cfg.group} - -"
      "d ${cfg.configDir} 0755 root root - -"
    ];

    # Install generated and explicit region_*.toml files next to chirpstack.toml.
    environment.etc = lib.mkMerge (
      [
        {
          "chirpstack/chirpstack.toml" = {
            source = configSource;
            mode = "0644";
          };
        }
      ]
      ++ generatedRegionFiles
    );

    # Service
    systemd.services.chirpstack-network-server = {
      description = "ChirpStack Network Server (SQLite)";
      wantedBy = [ "multi-user.target" ];

      # Wait for network + deps
      after = [
        "network-online.target"
        "mosquitto.service"
        "redis.service"
      ];
      wants = [
        "network-online.target"
        "mosquitto.service"
        "redis.service"
      ];

      # If you use a non-default redis unit name (e.g. redis-foo.service),
      # change these. Minimal version assumes redis.service.
      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;

        WorkingDirectory = cfg.stateDir;
        StateDirectory = "chirpstack";
        # (StateDirectory creates /var/lib/chirpstack *only* if it's under /var/lib,
        # but we already do tmpfiles; leaving it doesn't hurt.)

        ExecStart = exec;

        Restart = "on-failure";
        RestartSec = 2;

        # mild hardening without breaking sqlite writes
        NoNewPrivileges = true;
        ProtectSystem = "no";
        ReadWritePaths = [ cfg.stateDir ];
      };
    };

    # Firewall (optional)
    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.uiPort ];
  };
}

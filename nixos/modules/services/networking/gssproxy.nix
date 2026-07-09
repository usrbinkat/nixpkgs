{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.gssproxy;

  serviceConfigText =
    name: svc:
    ''
      [service/${name}]
        mechs = ${svc.mechs}
        cred_store = keytab:${svc.keytab}
        cred_store = ccache:FILE:${svc.ccachePath}
        cred_usage = ${svc.credUsage}
        euid = ${toString svc.euid}
    ''
    + lib.optionalString svc.allowAnyUid "  allow_any_uid = ${lib.boolToYesNo svc.allowAnyUid}\n"
    + lib.optionalString svc.trusted "  trusted = ${lib.boolToYesNo svc.trusted}\n"
    + lib.optionalString svc.impersonate "  impersonate = ${lib.boolToYesNo svc.impersonate}\n"
    + lib.optionalString (svc.program != null) "  program = ${svc.program}\n"
    + lib.optionalString svc.kernelNfsd "  kernel_nfsd = ${lib.boolToYesNo svc.kernelNfsd}\n  socket = /run/gssproxy.sock\n";

  configFile = pkgs.writeText "gssproxy.conf" (
    "[gssproxy]\n\n" + lib.concatStringsSep "\n" (lib.mapAttrsToList serviceConfigText cfg.services)
  );

  serviceOpts = {
    options = {
      mechs = lib.mkOption {
        type = lib.types.str;
        default = "krb5";
        description = "GSSAPI mechanisms to support.";
      };

      keytab = lib.mkOption {
        type = lib.types.str;
        default = "/etc/krb5.keytab";
        description = "Path to the keytab file.";
      };

      ccachePath = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/gssproxy/clients/krb5cc_%U";
        description = "Credential cache path template (`%U` expands to UID).";
      };

      credUsage = lib.mkOption {
        type = lib.types.enum [
          "initiate"
          "accept"
          "both"
        ];
        default = "initiate";
        description = "Credential usage mode.";
      };

      euid = lib.mkOption {
        type = lib.types.int;
        default = 0;
        description = "Effective UID allowed to connect to this service.";
      };

      allowAnyUid = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Allow any UID to use this service.";
      };

      trusted = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Trust the peer's identity claims.";
      };

      impersonate = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable S4U2Self/S4U2Proxy user impersonation via constrained delegation.";
      };

      kernelNfsd = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable kernel NFS server protocol extensions.";
      };

      program = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Restrict this service to a specific program binary (absolute path).";
      };
    };
  };

in
{
  meta.maintainers = [ lib.maintainers.usrbinkat ];

  options.services.gssproxy = {
    enable = lib.mkEnableOption "GSS-Proxy, a privilege-separating GSSAPI credential proxy";

    package = lib.mkPackageOption pkgs "gssproxy" { };

    services = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule serviceOpts);
      default = { };
      description = "GSS-Proxy service definitions.";
      example = lib.literalExpression ''
        {
          nfs-client = {
            allowAnyUid = true;
            impersonate = true;
          };
        }
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = lib.concatLists (
      lib.mapAttrsToList (name: svc: [
        {
          assertion = !(svc.impersonate && svc.credUsage == "accept");
          message = "services.gssproxy.services.${name}: impersonate requires credUsage \"initiate\" or \"both\", not \"accept\".";
        }
        {
          assertion = !(svc.kernelNfsd && !svc.trusted);
          message = "services.gssproxy.services.${name}: kernelNfsd requires trusted = true.";
        }
      ]) cfg.services
    );

    environment.etc."gss/mech.d/gssproxy.conf".text = ''
      gssproxy_v1  2.16.840.1.113730.3.8.15.1  ${cfg.package}/lib/gssproxy/proxymech.so  <interposer>
    '';

    systemd.services.gssproxy = {
      description = "GSSAPI Proxy Daemon";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      restartTriggers = [ configFile ];

      serviceConfig = {
        Type = "notify";
        ExecStart = "${lib.getExe cfg.package} -i -c ${configFile}";
        ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
        Restart = "on-failure";
        StateDirectory = "gssproxy gssproxy/clients gssproxy/rcache";
        StateDirectoryMode = "0700";
        Environment = "KRB5RCACHEDIR=/var/lib/gssproxy/rcache";

        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateDevices = true;
        PrivateIPC = true;
        ProtectClock = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        RestrictNamespaces = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        PrivateMounts = true;
        SystemCallFilter = [ "@system-service" ];
        SystemCallErrorNumber = "EPERM";
        SystemCallArchitectures = "native";
        NoNewPrivileges = true;
        CapabilityBoundingSet = [ "CAP_DAC_OVERRIDE" ];
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
        ];
      };
    };

    systemd.services.rpc-gssd =
      lib.mkIf (config.boot.supportedFilesystems.nfs or config.boot.supportedFilesystems.nfs4 or false)
        {
          after = [ "gssproxy.service" ];
          wants = [ "gssproxy.service" ];
          serviceConfig.Environment = [ "GSS_USE_PROXY=yes" ];
        };
  };
}

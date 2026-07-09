import ../make-test-python.nix (
  { pkgs, lib, ... }:

  let
    security.krb5 = {
      enable = true;
      settings = {
        domain_realm."nfs.test" = "NFS.TEST";
        libdefaults.default_realm = "NFS.TEST";
        realms."NFS.TEST" = {
          admin_server = "server.nfs.test";
          kdc = "server.nfs.test";
        };
      };
    };

    hosts = ''
      192.168.1.1 client.nfs.test
      192.168.1.2 server.nfs.test
    '';

    users = {
      users.alice = {
        isNormalUser = true;
        name = "alice";
        uid = 1000;
      };
    };

  in

  {
    name = "nfsv4-with-gssproxy";

    nodes = {
      client =
        { lib, ... }:
        {
          inherit security users;

          networking.extraHosts = hosts;
          networking.domain = "nfs.test";
          networking.hostName = "client";

          services.gssproxy = {
            enable = true;
            services.nfs-client = {
              allowAnyUid = true;
              impersonate = true;
            };
          };

          virtualisation.fileSystems = {
            "/data" = {
              device = "server.nfs.test:/";
              fsType = "nfs";
              options = [
                "nfsvers=4"
                "sec=krb5p"
                "noauto"
              ];
            };
          };
        };

      server =
        { lib, ... }:
        {
          inherit security users;

          networking.extraHosts = hosts;
          networking.domain = "nfs.test";
          networking.hostName = "server";

          networking.firewall.allowedTCPPorts = [
            111 # rpc
            2049 # nfs
            88 # kerberos
            749 # kerberos admin
          ];

          services.kerberos_server.enable = true;
          services.kerberos_server.realms = {
            "NFS.TEST".acl = [
              {
                access = "all";
                principal = "admin/admin";
              }
            ];
          };

          services.nfs.server.enable = true;
          services.nfs.server.createMountPoints = true;
          services.nfs.server.exports = ''
            /data *(rw,no_root_squash,fsid=0,sec=krb5p)
          '';
        };
    };

    testScript = ''
      server.succeed("mkdir -p /data/alice")
      server.succeed("chown alice:users /data/alice")

      # set up kerberos database
      server.succeed(
          "kdb5_util create -s -r NFS.TEST -P master_key",
          "systemctl restart kadmind.service kdc.service",
      )
      server.wait_for_unit("kadmind.service")
      server.wait_for_unit("kdc.service")

      server.succeed(
          "kadmin.local add_principal -randkey nfs/server.nfs.test",
          "kadmin.local add_principal -randkey nfs/client.nfs.test",
          "kadmin.local add_principal -randkey host/client.nfs.test",
          "kadmin.local add_principal -randkey host/server.nfs.test",
          "kadmin.local add_principal -pw admin_pw admin/admin",
          "kadmin.local add_principal -pw alice_pw alice",
      )

      # ok_to_auth_as_delegate is a safe default for S4U2Self; with a
      # vanilla MIT KDC and no GCD rules it is not strictly required
      # (S4U2Self tickets are forwardable by default in krb5 1.20+)
      # but it is required in FreeIPA environments where GCD rules exist.
      server.succeed(
          "kadmin.local modify_principal +ok_to_auth_as_delegate host/client.nfs.test",
      )

      server.succeed("kadmin.local ktadd nfs/server.nfs.test")
      server.succeed("systemctl start rpc-gssd.service rpc-svcgssd.service")
      server.wait_for_unit("rpc-gssd.service")
      server.wait_for_unit("rpc-svcgssd.service")

      client.systemctl("start network-online.target")
      client.wait_for_unit("network-online.target")

      client.succeed("echo admin_pw | kadmin -p admin/admin ktadd host/client.nfs.test")
      client.succeed("echo admin_pw | kadmin -p admin/admin ktadd nfs/client.nfs.test")

      client.wait_for_unit("gssproxy.service")
      client.succeed("systemctl start rpc-gssd.service")
      client.wait_for_unit("rpc-gssd.service")

      client.succeed(
          "cat /proc/$(pgrep rpc.gssd)/environ | tr '\\0' '\\n' | grep GSS_USE_PROXY=yes"
      )

      with subtest("nfs share mounts with gssproxy (no kinit)"):
          client.succeed("systemctl restart data.mount")
          client.wait_for_unit("data.mount")

      with subtest("access denied without gssproxy or kinit"):
          # Stop gssproxy and verify alice cannot access NFS without
          # either gssproxy impersonation or a Kerberos TGT.
          client.succeed("systemctl stop gssproxy.service")
          client.succeed("umount /data || true")
          client.succeed("systemctl restart data.mount")
          client.wait_for_unit("data.mount")
          client.fail("su alice -c 'ls /data/alice'")
          # Restart gssproxy for the remaining tests
          client.succeed("systemctl start gssproxy.service")
          client.wait_for_unit("gssproxy.service")
          client.succeed("umount /data || true")
          client.succeed("systemctl restart data.mount")
          client.wait_for_unit("data.mount")

      with subtest("alice can access her home via gssproxy impersonation"):
          client.succeed("su alice -c 'ls /data/alice'")
          client.succeed("su alice -c 'echo gssproxy_test >> /data/alice/testfile'")
          server.succeed("test -e /data/alice/testfile")
          server.succeed("grep gssproxy_test /data/alice/testfile")

      with subtest("uids/gids are mapped correctly on nfs share"):
          ids = client.succeed("stat -c '%U %G' /data/alice").split()
          expected = ["alice", "users"]
          assert ids == expected, f"ids incorrect: got {ids} expected {expected}"
    '';

    meta.maintainers = [ lib.maintainers.usrbinkat ];
  }
)

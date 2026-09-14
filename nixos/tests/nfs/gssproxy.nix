import ../make-test-python.nix (
  { pkgs, lib, ... }:

  let
    krb5Package = pkgs.krb5.override { withLdap = true; };
    krbLdapSchema = pkgs.runCommand "krb-ldap-schema" { } ''
      tar -Oxf ${krb5Package.src} \
        ${krb5Package.sourceRoot}/plugins/kdb/ldap/libkdb_ldap/kerberos.openldap.ldif > $out
    '';

    delegation = pkgs.writeText "nfs-delegation.ldif" ''
      dn: krbPrincipalName=host/client.nfs.test@NFS.TEST,cn=NFS.TEST,cn=realms,dc=nfs,dc=test
      changetype: modify
      add: krbAllowedToDelegateTo
      krbAllowedToDelegateTo: nfs/server.nfs.test@NFS.TEST
    '';

    security.krb5 = {
      enable = true;
      settings = {
        domain_realm."nfs.test" = "NFS.TEST";
        libdefaults.default_realm = "NFS.TEST";
        libdefaults.forwardable = true;
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
              program = "${pkgs.nfs-utils}/bin/rpc.gssd";
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
          inherit users;
          security.krb5 = security.krb5 // {
            package = krb5Package;
          };

          networking.extraHosts = hosts;
          networking.domain = "nfs.test";
          networking.hostName = "server";

          networking.firewall.allowedTCPPorts = [
            111 # rpc
            2049 # nfs
            88 # kerberos
            749 # kerberos admin
          ];
          networking.firewall.allowedUDPPorts = [ 88 ];

          services.openldap = {
            enable = true;
            urlList = [ "ldapi:///" ];
            declarativeContents."dc=nfs,dc=test" = ''
              dn: dc=nfs,dc=test
              objectClass: organization
              objectClass: dcObject
              dc: nfs
              o: NFS test
            '';
            settings.children = {
              "cn=schema".includes = [
                "${pkgs.openldap}/etc/schema/core.ldif"
                "${pkgs.openldap}/etc/schema/cosine.ldif"
                krbLdapSchema
              ];
              "olcDatabase={1}mdb".attrs = {
                objectClass = [
                  "olcDatabaseConfig"
                  "olcMdbConfig"
                ];
                olcDatabase = "{1}mdb";
                olcDbDirectory = "/var/lib/openldap/db";
                olcSuffix = "dc=nfs,dc=test";
                olcRootDN = "cn=root,dc=nfs,dc=test";
                olcRootPW = "ldap_test_password";
                olcAccess = [ "to * by * none" ];
              };
            };
          };

          services.kerberos_server.enable = true;
          services.kerberos_server.settings.realms = {
            "NFS.TEST".acl = [
              {
                access = "all";
                principal = "admin/admin";
              }
            ];
          };
          services.kerberos_server.settings.dbmodules."NFS.TEST" = {
            db_library = "kldap";
            ldap_kerberos_container_dn = "cn=realms,dc=nfs,dc=test";
            ldap_kdc_dn = "cn=root,dc=nfs,dc=test";
            ldap_kadmind_dn = "cn=root,dc=nfs,dc=test";
            ldap_service_password_file = "/var/lib/krb5kdc/ldap-password";
            ldap_servers = "ldapi:///";
          };

          services.nfs.server.enable = true;
          services.gssproxy = {
            enable = true;
            services.nfs-server = {
              kernelNfsd = true;
              trusted = true;
              credUsage = "accept";
            };
          };
          systemd.services.rpc-svcgssd.enable = false;
          services.nfs.server.createMountPoints = true;
          services.nfs.server.exports = ''
            /data *(rw,no_root_squash,fsid=0,sec=krb5p)
          '';
        };
    };

    testScript = ''
      server.succeed("mkdir -p /data/alice")
      server.succeed("chown alice:users /data/alice")

      # Create the LDAP-backed realm and its password stash inside the VM.
      # MIT's DB2 backend cannot authorize S4U2Proxy delegation.
      server.wait_for_unit("openldap.service")
      server.succeed(
          "mkdir -p /var/lib/krb5kdc",
          "printf '%s\\n' ldap_test_password ldap_test_password | kdb5_ldap_util -r NFS.TEST stashsrvpw -f /var/lib/krb5kdc/ldap-password cn=root,dc=nfs,dc=test",
          "kdb5_ldap_util -D cn=root,dc=nfs,dc=test -w ldap_test_password -r NFS.TEST create -s -P master_key",
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

      # Permit forwardable S4U2Self tickets and delegation only to this NFS server.
      server.succeed(
          "kadmin.local modify_principal +ok_to_auth_as_delegate host/client.nfs.test",
          "ldapmodify -x -H ldapi:/// -D cn=root,dc=nfs,dc=test -w ldap_test_password -f ${delegation}",
      )

      server.succeed("kadmin.local ktadd nfs/server.nfs.test")
      with subtest("kernel NFS uses gssproxy without rpc-svcgssd"):
          server.succeed("systemctl start auth-rpcgss-module.service")
          server.succeed("systemctl restart gssproxy.service")
          server.succeed("test -S /run/gssproxy.sock")
          server.succeed("test $(cat /proc/net/rpc/use-gss-proxy) = 1")
          server.fail("systemctl is-active rpc-svcgssd.service")

      client.systemctl("start network-online.target")
      client.wait_for_unit("network-online.target")

      client.succeed("echo admin_pw | kadmin -p admin/admin ktadd host/client.nfs.test")
      client.succeed("echo admin_pw | kadmin -p admin/admin ktadd nfs/client.nfs.test")

      client.wait_for_unit("gssproxy.service")
      client.succeed("${lib.getExe pkgs.gssproxy} --version")
      with subtest("service startup waits for sockets and tracks the daemon PID"):
          client.succeed("systemctl stop gssproxy.service")
          client.succeed("rm -f /var/lib/gssproxy/default.sock")
          client.succeed("systemctl start gssproxy.service")
          client.succeed("test -S /var/lib/gssproxy/default.sock")
          client.succeed("test $(cat /run/gssproxy/gssproxy.pid) = $(systemctl show -p MainPID --value gssproxy.service)")
          client.succeed("systemctl reload gssproxy.service")
          client.succeed("systemctl is-active gssproxy.service")
      client.succeed("su alice -c 'test -S /var/lib/gssproxy/default.sock'")
      client.fail("su alice -c 'test -r /var/lib/gssproxy/clients'")
      client.fail("su alice -c 'test -r /var/lib/gssproxy/rcache'")
      client.succeed("systemctl start rpc-gssd.service")
      client.wait_for_unit("rpc-gssd.service")

      client.succeed(
          "cat /proc/$(pgrep rpc.gssd)/environ | tr '\\0' '\\n' | grep GSS_USE_PROXY=yes"
      )

      with subtest("nfs share mounts with gssproxy (no kinit)"):
          client.succeed("systemctl restart data.mount")
          client.wait_for_unit("data.mount")

          client.succeed("grep proxymech.so /proc/$(pgrep rpc.gssd)/maps")

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

      client.fail("journalctl -u gssproxy --no-pager | grep 'Unexpected failure in realpath'")
    '';

    meta.maintainers = [ lib.maintainers.usrbinkat ];
  }
)

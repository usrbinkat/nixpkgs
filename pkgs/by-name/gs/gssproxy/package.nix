{
  lib,
  stdenv,
  fetchFromGitHub,
  autoreconfHook,
  pkg-config,
  libkrb5,
  libverto,
  ding-libs,
  popt,
  systemd,
  keyutils,
  gettext,
  docbook-xsl-nons,
  docbook_xml_dtd_44,
  libxslt,
  libxml2,
  nixosTests,
  nix-update-script,
}:

let
  docbookFiles = "${docbook-xsl-nons}/share/xml/docbook-xsl-nons/catalog.xml:${docbook_xml_dtd_44}/xml/dtd/docbook/catalog.xml";
in

stdenv.mkDerivation (finalAttrs: {
  pname = "gssproxy";
  version = "0.9.2";

  src = fetchFromGitHub {
    owner = "gssapi";
    repo = "gssproxy";
    rev = "v${finalAttrs.version}";
    hash = "sha256-RcT1ge/XxhTaT9hrvcHElAEAbvOtjqep3kdEw5e7WZY=";
  };

  nativeBuildInputs = [
    autoreconfHook
    pkg-config
    gettext
    docbook-xsl-nons
    docbook_xml_dtd_44
    libxslt
    libxml2
  ];

  buildInputs = [
    libkrb5
    libverto
    ding-libs
    popt
    systemd
    keyutils
  ];

  preConfigure = ''
    export SGML_CATALOG_FILES="${docbookFiles}"
  '';

  configureFlags = [
    "--with-pubconf-path=/etc/gssproxy"
    "--with-initscript=systemd"
    "--with-systemd-unit-dir=${placeholder "out"}/lib/systemd/system"
    "--with-systemd-user-unit-dir=${placeholder "out"}/lib/systemd/user"
    "--disable-static"
    "--disable-rpath"
    "--with-gpp-default-behavior=REMOTE_FIRST"
    "--without-selinux"
    "--with-xml-catalog-path=${docbook-xsl-nons}/share/xml/docbook-xsl-nons/catalog.xml"
  ];

  makeFlags = [
    "sbindir=$(out)/bin"
    "SGML_CATALOG_FILES=${docbookFiles}"
  ];

  installFlags = [
    "pubconfpath=$(out)/etc/gssproxy"
    "gpstatedir=$(out)/var/lib/gssproxy"
    "gpclidir=$(out)/var/lib/gssproxy/clients"
    "logpath=$(out)/var/log/gssproxy"
    "systemdunitdir=$(out)/lib/systemd/system"
    "systemduserunitdir=$(out)/lib/systemd/user"
  ];

  postInstall = ''
    install -Dm644 examples/gssproxy.conf $out/share/gssproxy/gssproxy.conf
    install -Dm644 examples/99-network-fs-clients.conf $out/share/gssproxy/99-network-fs-clients.conf
    install -Dm644 examples/24-nfs-server.conf $out/share/gssproxy/24-nfs-server.conf
    install -Dm644 examples/proxymech.conf $out/share/gssproxy/proxymech.conf
  '';

  passthru = {
    tests = {
      nfs4-gssproxy = nixosTests.nfs4.gssproxy;
    };
    updateScript = nix-update-script { };
  };

  meta = {
    description = "Privilege-separating proxy for GSSAPI credential handling";
    longDescription = ''
      GSS-Proxy provides an abstraction layer between GSSAPI clients and
      credentials.  For NFS, it enables constrained delegation (S4U2Self
      and S4U2Proxy) so that NFS clients can impersonate users who
      authenticated via SSH public key without a Kerberos TGT.
    '';
    homepage = "https://github.com/gssapi/gssproxy";
    changelog = "https://github.com/gssapi/gssproxy/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    mainProgram = "gssproxy";
    platforms = lib.platforms.linux;
    maintainers = [ lib.maintainers.usrbinkat ];
  };
})

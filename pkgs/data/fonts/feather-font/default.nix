{ lib, fetchzip }:
let
  version = "1.0";
  pname = "feather-font";
in
fetchzip {
  name = "${pname}-${version}";
  url = "https://github.com/dustinlyons/feather-font/archive/refs/tags/${version}.zip";

  postFetch = ''
    mkdir -p $out/share/fonts/truetype
    unzip -D -j /build/${version}.zip  ${pname}-${version}/feather.ttf -d $out/share/fonts/truetype/
  '';

  sha256 = "sha256-OFD0N+qHetl2z8Vcv4mZAgR6YHifVhdMFBIZYYSQWcs=";

  meta = with lib; {
    homepage = "https://www.feathericons.com/";
    description = "Set of font icons from the open source collection Feather Icons";
    version = version;
    longDescription = ''
      Installs a TTF font: feather
      Fonts provided by https://www.feathericons.com
    '';
    license = licenses.mit;
    maintainers = [ maintainers.dlyons ];
    platforms = platforms.all;
  };
}

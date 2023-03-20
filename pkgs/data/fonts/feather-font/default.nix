{ lib, fetchzip }:
let
  version = "1.0";
in
fetchzip {
  name = "feather-font";

  url = "https://github.com/dustinlyons/feather-font/archive/refs/tags/${version}.zip";

  postFetch = ''
    mkdir -p $out/share/fonts
    unzip -j $downloadedFile \*.ttf -d $out/share/fonts/truetype
  '';

  sha256 = "1jd3gjjfa4vadp6d499n0irz5b22z611kd7q5qgqf6s2fwbxfhiz";

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

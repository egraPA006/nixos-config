# Saved FabFilter installers and their unattended installation options.
{ ... }:
let
  installers = [
    { name = "Micro"; version = "1.3.2"; sha256 = "a5c49099a16f934a6f473a64cf16f6b818f758deb0598a25f4efc38e731105f2"; }
    { name = "One"; version = "3.5.2"; sha256 = "339c427408a087c1d2a1f4d45287afbd4d80fd0e38ae542f7afd7aa44f4ec048"; }
    { name = "Pro-C 2"; version = "2.2.2"; sha256 = "877babb32fd61399a70278df063e4998026c30e4e094412a8fe58775e182e5f8"; }
    { name = "Pro-C 3"; version = "3.0.2"; sha256 = "b1b9e63e6740eae22a2f49dd5d31d50942fb279ce21212a47cd6ef18dbf5e2b5"; }
    { name = "Pro-DS"; version = "1.3.2"; sha256 = "c94189c6dd6734c95347f33f30597ecddbb0535ac928b0ce57abd75a77e20fc2"; }
    { name = "Pro-G"; version = "1.4.2"; sha256 = "9c79ed24f9592c62b373d7b8cc98d7b7db2019ae5fcc78ae852322d7f0f5cde7"; }
    { name = "Pro-L 2"; version = "2.2.6"; sha256 = "7f41650b8c47290df273fa0d516248cc01c94ef9d88ea8f83237a39362878497"; }
    { name = "Pro-L"; version = "1.3.7"; sha256 = "23f770648161155b73a2138a6ffca3687483007b032d060c245e9da0f53fc501"; }
    { name = "Pro-MB"; version = "1.3.3"; sha256 = "ca0ac523f2e5af2c585fa292b09cd6553764253b38063fc1f00e4e4df1eec342"; }
    { name = "Pro-Q 2"; version = "2.3.0"; sha256 = "31d50af0ab46476ac87143aff6d70dbac3cfc17be3360269ff8da6eda3e86405"; }
    { name = "Pro-Q 3"; version = "3.2.9"; sha256 = "dae233d7fa7f8d16cdbe714c01f9fd8c9899bdd8b5c8ebd190b5a581294c0c84"; }
    { name = "Pro-Q 4"; version = "4.1.3"; sha256 = "312c238f69c3323a565fb2b11e7118036f2fb570b04ee0616a30f0e025855414"; }
    { name = "Pro-R 2"; version = "2.0.6"; sha256 = "f72510d7c9a135dee3d15b15838e4e21646102342dbf50eaec2899e653760b19"; }
    { name = "Pro-R"; version = "1.2.0"; sha256 = "7ab8f6967ffaa4a904ae4e3e4356c8825e820cdd5550128f6989ae5afd5b75c7"; }
    { name = "Saturn 2"; version = "2.1.3"; sha256 = "ec2e8f20318e6346297ebfe2d4ea3b4bdd37cea593391b69b2ee30ef6d9e4521"; }
    { name = "Saturn"; version = "1.3.1"; sha256 = "17e8eed14df2855b9404994cc58bc18adc77d5c8acd986329e50366f644108b8"; }
    { name = "Simplon"; version = "1.4.2"; sha256 = "4a99648b5970bb66b95851a35d01ee5c525bcc348129655aa09dc07d8e7e788f"; }
    { name = "Timeless 2"; version = "2.4.1"; sha256 = "bc7ae402678ee7ce97b4a391b7083f5d915bc4e797146c7087ad963c666a8d43"; }
    { name = "Timeless 3"; version = "3.1.0"; sha256 = "49fec61641bf2f72de5e6c4997e562c245a31ec2a6c9d55559d1f9c0ae943d30"; }
    { name = "Twin 2"; version = "2.4.1"; sha256 = "576c9e5b99616b2192a5065f5ba3a991e3fc1ff52fae7d873498e654595d079b"; }
    { name = "Twin 3"; version = "3.0.7"; sha256 = "fa9308f7e0b21b19021c64cfb165c1c28035fdf7dbea44562410dbdb199a2f1b"; }
    { name = "Volcano 2"; version = "2.4.1"; sha256 = "86f0f455c7da77c6b2dfa7d4468cd330fd342821ba8289500c2ef55365eb8400"; }
    { name = "Volcano 3"; version = "3.0.9"; sha256 = "c02a3118a97a39fc2d9e26c647693fdd9a2cdc74b2310fe5a6cb0a339c28de3d"; }
  ];
in
{
  pino.profiles.musicFull.windowsPlugins = builtins.listToAttrs (map (plugin: {
    name = "FabFilter-${plugin.name}";
    value = {
      installer = "FabFilter - Total Bundle v2026.06.25 [R2R]/FF260625/installer/Setup ${plugin.name} v${plugin.version}.exe";
      inherit (plugin) sha256;
      args = [ "/VERYSILENT" "/SUPPRESSMSGBOXES" "/NORESTART" ];
    };
  }) installers);
}

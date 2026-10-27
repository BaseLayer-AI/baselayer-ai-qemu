{
  inputs.nixpkgs.url = "github:nixos/nixpkgs/master";

  outputs = { self, nixpkgs }:
    let
      host = import nixpkgs { system = "aarch64-darwin"; };
      guest = import nixpkgs { system = "aarch64-linux"; };
    in {
      packages = {
        aarch64-darwin.default = host.writeTextFile {
          name = "qemu-aarch64-explore";
          executable = true;
          destination = "/bin/qemu-aarch64-explore";
          text = ''
            #!${host.stdenv.shell}
            ${host.qemu}/bin/qemu-system-aarch64 --help
          '';
        };
      };
    };
}


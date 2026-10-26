{
  inputs.nixpkgs.url = "github:nixos/nixpkgs/master";
  outputs = { self, nixpkgs }:
    let
      host = import nixpkgs { system = "aarch64-darwin"; };
      guest = import nixpkgs { system = "x86_64-linux"; };
    in {
      packages = {
        aarch64-darwin.default = host.writeTextFile {
          name = "qemu-explore";
          executable = true;
          destination = "/bin/qemu-explore";
          text = ''
            #!${host.stdenv.shell}
            ls -lR ${host.qemu}
            ls -lR ${host.qemu-utils}
            ls -lR ${guest.linuxPackages.kernel}
            ls -lR ${guest.busybox}
          '';
        };
      };
    };
}

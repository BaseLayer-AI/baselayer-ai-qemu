{
  description = "Baselayer AI QEMU Research";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }: {
    devShells.aarch64-linux.default = nixpkgs.legacyPackages.aarch64-linux.mkShell {
      buildInputs = with nixpkgs.legacyPackages.aarch64-linux; [
        qemu
        qemu-utils
      ];
    };
  };
}


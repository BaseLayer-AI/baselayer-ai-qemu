{
  inputs.nixpkgs.url = "github:nixos/nixpkgs/master";

  outputs = { self, nixpkgs }: 
    let 
      system = "aarch64-darwin";
      pkgs = import nixpkgs { inherit system; }; 
    in {
      packages = {
        ${system}.default = pkgs.writeTextFile {
          name = "qemu-explore";
          executable = true;
          destination = "/bin/qemu-explore";
          text = ''
            #!${pkgs.stdenv.shell}
            ls -lR ${pkgs.qemu-utils} 
            ls -lR ${pkgs.qemu}
          '';
        };
      };
    };
}


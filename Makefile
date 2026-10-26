all: show version explore boot
show:;nix flake show
version:nix-version 
nix-version:;nix --version
explore:;nix run ./qemu-explore
boot:;nix run ./qemu-boot

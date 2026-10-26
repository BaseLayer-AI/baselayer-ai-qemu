all: show version boot
show:;nix flake show
version:nix-version 
nix-version:;nix --version
boot:;nix run ./qemu-boot-busybox

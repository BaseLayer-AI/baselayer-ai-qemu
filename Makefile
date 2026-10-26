all: show version explore
show:;nix flake show
version:nix-version 
nix-version:;nix --version
explore:;nix run ./qemu-explore
#run:;nix run&&ls

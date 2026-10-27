all: show version run
show:;nix flake show
version:nix-version 
nix-version:;nix --version
run:;nix run 

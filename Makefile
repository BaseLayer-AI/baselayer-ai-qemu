all: version run
version:nix-version 
nix-version:;nix --version
run:
	nix run github:BaseLayer-AI/baselayer-ai-qemu/aarch64-darwin-qemu-boot-busybox --refresh
	nix run github:BaseLayer-AI/baselayer-ai-qemu/aarch64-darwin-qemu-boot-busybox-kernel-heartbeat --refresh

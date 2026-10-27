version:nix-version 
nix-version:;nix --version
macos-26:
	nix run github:BaseLayer-AI/baselayer-ai-qemu/aarch64-darwin-qemu-boot-busybox-kernel-heartbeat --refresh
ubuntu-26.04:
	nix run github:BaseLayer-AI/baselayer-ai-qemu/x86_64-linux-qemu-boot-busybox-kernel-heartbeat --refresh

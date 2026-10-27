version:nix-version 
nix-version:;nix --version
macos-26:
	nix run github:BaseLayer-AI/baselayer-ai-qemu/aarch64-darwin-qemu-boot-busybox-kernel-heartbeat --refresh

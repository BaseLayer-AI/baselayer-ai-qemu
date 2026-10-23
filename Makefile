all: show version test
show:;nix flake show
version:nix-version qemu-version;
nix-version:;nix --version
qemu-version:;nix develop --command qemu-img --version
test:test_disk.qcow2;
test_disk.qcow2:;nix develop --command qemu-img create -f qcow2 test_disk.qcow2 512M
clean:;rm -f test_disk.qcow2

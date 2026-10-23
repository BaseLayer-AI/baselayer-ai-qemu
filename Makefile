all: version test_disk.qcow2
version:;nix develop --command qemu-img --version
test_disk.qcow2:;nix develop --command qemu-img create -f qcow2 test_disk.qcow2 512M
clean:;rm -f test_disk.qcow2

{
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }: 
    let 
      system = "aarch64-linux";
      pkgs = import nixpkgs { inherit system; }; 
    in {
      packages = {
        ${system}.default = pkgs.writeTextFile {
          name = "qemu-research";
          executable = true;
          destination = "/bin/qemu-research";
          text = ''
            #!${pkgs.stdenv.shell}
            
            BASE_DIR=$(pwd)
            DISK_PATH="$BASE_DIR/test_disk.qcow2"
            LOG_PATH="$BASE_DIR/test.log"
            ERR_LOG="$BASE_DIR/qemu_error.log"

            # --- Cleanup Function ---
            cleanup() {
              echo "-----------------------------------------------------------"
              echo "Cleaning up generated files..."
              rm -f "$DISK_PATH" "$LOG_PATH" "$ERR_LOG"
              echo "Done."
            }

            # Trap signals: Run cleanup on exit, interruption (Ctrl+C), or termination
            trap cleanup EXIT INT TERM

            # 1. Ensure disk exists
            if [ ! -f "$DISK_PATH" ]; then
              echo "Creating disk image..."
              ${pkgs.qemu-utils}/bin/qemu-img create -f qcow2 "$DISK_PATH" 512M
            fi

            # Clear the old log
            > "$LOG_PATH"

            echo "Starting QEMU in background (15s timeout)..."
            
            # 2. Start QEMU in the background
            ${pkgs.qemu}/bin/qemu-system-x86_64 \
              -hda "$DISK_PATH" \
              -nographic \
              -display none \
              -serial file:"$LOG_PATH" \
              2> "$ERR_LOG" &
            
            QEMU_PID=$!

            # 3. Wait 15 seconds
            sleep 15

            # 4. Kill the process
            echo "Killing QEMU (PID: $QEMU_PID)..."
            kill $QEMU_PID 2>/dev/null || true

            # Small pause to let the OS flush the file handle
            sleep 0.5

            echo "-----------------------------------------------------------"
            echo "Serial Log Content:"
            if [ -s "$LOG_PATH" ]; then
              cat "$LOG_PATH"
            else
              echo "Warning: $LOG_PATH is still empty."
              if [ -f "$ERR_LOG" ]; then
                echo "Startup Errors:"
                cat "$ERR_LOG"
              fi
            fi
            echo "-----------------------------------------------------------"

            # The trap handles the final cleanup
            true
          '';
        };
      };
    };
}


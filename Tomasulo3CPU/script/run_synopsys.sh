#!/bin/bash

# 1. Allow the Docker container to display GUIs on the Ubuntu desktop
xhost +local:docker > /dev/null 2>&1

# 2. Start/check the Synopsys license server on the host.
#    FlexNet is much happier running on the host than inside a short-lived
#    container.  The container uses --net=host and checks out from 127.0.0.1.
SCL_HOME=/home/synopsys/scl/2024.06
SYNOPSYS_LICENSE_FILE=$SCL_HOME/admin/license/synopsys.lic
LMUTIL=$SCL_HOME/linux64/bin/lmutil
LMGRD=$SCL_HOME/linux64/bin/lmgrd
LMGRD_LOG=/tmp/synopsys_lmgrd_${USER}.log
LMSTAT_LOG=/tmp/synopsys_lmstat_${USER}.log

license_is_up() {
  "$LMUTIL" lmstat -c "$SYNOPSYS_LICENSE_FILE" >"$LMSTAT_LOG" 2>&1 &&
    grep -q "snpslmd: UP" "$LMSTAT_LOG"
}

if [ ! -x "$LMUTIL" ] || [ ! -x "$LMGRD" ]; then
  echo "ERROR: Synopsys SCL tools not found under $SCL_HOME"
  exit 1
fi

if [ ! -f "$SYNOPSYS_LICENSE_FILE" ]; then
  echo "ERROR: Synopsys license file not found: $SYNOPSYS_LICENSE_FILE"
  exit 1
fi

if ! license_is_up; then
  echo "Starting Synopsys license daemon on host..."
  rm -f "$LMGRD_LOG" "$LMSTAT_LOG"
  "$LMGRD" -c "$SYNOPSYS_LICENSE_FILE" -l "$LMGRD_LOG"
  for _try in 1 2 3 4 5 6 7 8 9 10; do
    sleep 1
    if license_is_up; then
      break
    fi
  done
fi

if ! license_is_up; then
  echo "ERROR: Synopsys license daemon did not come up cleanly."
  echo "See $LMGRD_LOG and $LMSTAT_LOG"
  echo ""
  echo "lmstat:"
  cat "$LMSTAT_LOG" 2>/dev/null || true
  echo ""
  echo "lmgrd log tail:"
  tail -40 "$LMGRD_LOG" 2>/dev/null || true
  exit 1
fi

echo "Synopsys license server is up:"
"$LMUTIL" lmstat -c "$SYNOPSYS_LICENSE_FILE" | grep -E "license server UP|snpslmd: UP" || true

# 3. Get script and project directories
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJ_DIR=$(cd "$SCRIPT_DIR/.." && pwd)

# 4. Build the Docker container (This only takes a few minutes the very first time you run it. After that, it is instant)
echo "Building Synopsys Docker environment (CentOS 7)..."
docker build -t synopsys-env \
  --build-arg USER_ID=$(id -u) \
  --build-arg GROUP_ID=$(id -g) \
  -f "$SCRIPT_DIR/Dockerfile.synopsys" "$SCRIPT_DIR"

echo ""
echo "=================================================="
echo "Launching Synopsys Environment!"
echo "Type 'dc_shell -gui' or 'verdi' to test."
echo "Type 'exit' to leave the environment."
echo "=================================================="
echo ""

# 5. Run the container
# --net=host : Shares Ubuntu's network (so the license server works perfectly)
# --uts=host : Shares Ubuntu's hostname, matching the SERVER line in the license
# -e DISPLAY : Forwards the GUI to your screen
# -v /home/synopsys : Mounts your tools directly into the container
# -v $PROJ_DIR : Mounts your current project directory into the container
docker run -it --rm \
  --net=host \
  --uts=host \
  -e DISPLAY=$DISPLAY \
  -v /tmp/.X11-unix:/tmp/.X11-unix:rw \
  -v /home/synopsys:/home/synopsys:rw \
  -v /data:/data:rw \
  -v /data/synopsys_project/synop.bashrc:/home/synopsys/synop.bashrc:ro \
  -v "$PROJ_DIR":/workspace \
  synopsys-env bash -c "source /home/synopsys/synop.bashrc && lmutil lmstat -c /home/synopsys/scl/2024.06/admin/license/synopsys.lic || true; bash"

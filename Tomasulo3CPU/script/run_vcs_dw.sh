#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)

SYNOP_BASHRC=${SYNOP_BASHRC:-/home/synopsys/synop.bashrc}
DC_HOME=${DC_HOME:-/home/synopsys/syn/V-2023.12-SP3}
DW_HOME=${DW_HOME:-$DC_HOME/dw}
PROJECT=${PROJECT:-IFQ}

if [[ -f "$SYNOP_BASHRC" ]]; then
  # shellcheck disable=SC1090
  source "$SYNOP_BASHRC"
elif [[ -f "$SCRIPT_DIR/synop.bashrc" ]]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/synop.bashrc"
fi

export DC_HOME DW_HOME

cd "$PROJECT_DIR"
exec make sim PROJECT="$PROJECT" USE_DW=1 DC_HOME="$DC_HOME" DW_HOME="$DW_HOME" "$@"

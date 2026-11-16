#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"

# A previously launched copy keeps its old animation code in memory. Replace it
# before starting so removed behaviors cannot survive an update.
pkill -x RabbitDesktopPet 2>/dev/null || true
zsh scripts/build_app_bundle.sh
open -n RabbitDesktopPet.app

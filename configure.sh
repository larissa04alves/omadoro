#!/usr/bin/env bash
# Reconfigura só a posição na waybar e a cor, sem recompilar.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

# Garante os temas instalados (caso rode a partir do repo pela primeira vez).
mkdir -p "$THEMES_DIR"
[ -e "$THEMES_DIR/sage/eww.scss" ] || cp -r "$SCRIPT_DIR/themes/." "$THEMES_DIR/"

echo
echo "  🍅 Reconfigurar pomodoro"
run_config
reload
echo
ok "Feito."

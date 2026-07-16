#!/usr/bin/env bash
# Remove o pomodoro e reverte os patches na waybar/hypr.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

echo
echo "  🍅 Removendo o pomodoro…"

# Fecha o eww
eww --config "$EWW_DIR" kill >/dev/null 2>&1 || true

# Reverte a config da waybar
cfg="$WAYBAR_DIR/config.jsonc"
style="$WAYBAR_DIR/style.css"
if [ -f "$cfg" ]; then
  backup "$cfg"
  remove_module "$cfg"                                            # tira o módulo do array
  sed -i -E "s#\"$WAYBAR_DIR/pomodoro.jsonc\",?[[:space:]]*##g" "$cfg"  # tira o include
  tidy_arrays "$cfg"                                              # sem vírgula órfã no array
fi
if [ -f "$style" ]; then
  backup "$style"
  sed -i '/>>> pomodoro >>>/,/<<< pomodoro <<</d' "$style"       # tira o bloco de cor
fi

# Reverte o autostart (Lua atual e .conf legado)
remove_autostart

# Remove os arquivos instalados
rm -f "$BIN_DIR/pomo" "$WAYBAR_DIR/pomodoro.jsonc"
rm -rf "$EWW_DIR"

reload
echo
ok "Removido."
echo "     Config e estado preservados em $CONFIG_DIR (apague à mão se quiser)."
echo

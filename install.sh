#!/usr/bin/env bash
# Instalador do pomodoro para waybar (Omarchy/Hyprland).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

echo
echo "  🍅 Pomodoro para Waybar — instalação"
echo

# 1. Dependências
info "Verificando dependências…"
command -v cargo >/dev/null || { echo "  cargo (Rust) é necessário: sudo pacman -S rust"; exit 1; }
if ! command -v eww >/dev/null; then
  warn "eww ausente — instalando eww-git (AUR)…"
  yay -S --needed eww-git
fi
command -v notify-send >/dev/null || warn "notify-send ausente — notificações não vão aparecer"
ok "Dependências ok"

# 2. Compilar e instalar o binário
info "Compilando o binário pomo…"
cargo build --release --manifest-path "$SCRIPT_DIR/Cargo.toml"
install -Dm755 "$SCRIPT_DIR/target/release/pomo" "$BIN_DIR/pomo"
ok "pomo → $BIN_DIR/pomo"

# 3. Instalar eww, temas e módulo da waybar
mkdir -p "$EWW_DIR" "$CONFIG_DIR" "$STATE_DIR" "$THEMES_DIR"
cp "$SCRIPT_DIR/eww/eww.yuck" "$SCRIPT_DIR/eww/eww.scss" "$SCRIPT_DIR/eww/_theme.scss" "$EWW_DIR/"
cp -r "$SCRIPT_DIR/themes/." "$THEMES_DIR/"   # temas na config → configure.sh funciona sem o repo
cp "$SCRIPT_DIR/waybar/pomodoro.jsonc" "$WAYBAR_DIR/pomodoro.jsonc"
ok "Arquivos instalados"

# 4. Config padrão (não sobrescreve se já existir)
if [ ! -f "$CONFIG_DIR/config.json" ]; then
  cat > "$CONFIG_DIR/config.json" <<'JSON'
{
  "work": 25,
  "short": 5,
  "long": 15,
  "long_every": 4,
  "auto_start_next": false
}
JSON
fi

# 5. include na waybar + autostart do eww
add_include
if ! grep -q "eww --config $EWW_DIR daemon" "$HYPR_AUTOSTART" 2>/dev/null; then
  echo "exec-once = eww --config $EWW_DIR daemon" >> "$HYPR_AUTOSTART"
  ok "eww daemon adicionado ao autostart"
fi

# 6. Configuração interativa
choose_position
choose_theme

# 7. Subir agora
eww --config "$EWW_DIR" daemon >/dev/null 2>&1 || true
reload

echo
ok "Pronto! Clique no 🍅 na waybar para abrir o popup."
echo "     Reconfigurar cor/posição:  $SCRIPT_DIR/configure.sh"
echo "     Desinstalar:               $SCRIPT_DIR/uninstall.sh"
echo

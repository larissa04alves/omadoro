# Caminhos e funções compartilhadas.
# Fonte comum de install.sh, configure.sh e uninstall.sh (não executar direto).

BIN_DIR="$HOME/.local/bin"
EWW_DIR="$HOME/.config/eww/pomodoro"
WAYBAR_DIR="$HOME/.config/waybar"
HYPR_AUTOSTART="$HOME/.config/hypr/autostart.conf"
CONFIG_DIR="$HOME/.config/pomodoro"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/pomodoro"
THEMES_DIR="$CONFIG_DIR/themes"

info() { printf '  \033[36m→\033[0m %s\n' "$1"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }

# Backup com timestamp antes de editar arquivos da usuária.
backup() { [ -f "$1" ] && cp "$1" "$1.bak.$(date +%s)"; }

# Insere "custom/pomodoro" no array modules-<pos> (left|center|right).
# Remove qualquer inserção anterior antes, então também serve para mudar de posição.
set_position() {
  local pos="$1" cfg="$WAYBAR_DIR/config.jsonc"
  backup "$cfg"
  sed -i 's/"custom\/pomodoro", //g' "$cfg"
  sed -i "/\"modules-$pos\":/ s/\[/[\"custom\/pomodoro\", /" "$cfg"
}

# Adiciona o pomodoro.jsonc ao "include" da config (idempotente).
add_include() {
  local cfg="$WAYBAR_DIR/config.jsonc" inc="$WAYBAR_DIR/pomodoro.jsonc"
  grep -q "pomodoro.jsonc" "$cfg" 2>/dev/null && return 0
  backup "$cfg"
  sed -i "/\"include\":/ s#\[#[\"$inc\", #" "$cfg"
}

# Aplica um tema: paleta do eww + bloco de accent no style.css da waybar.
apply_theme() {
  local name="$1" style="$WAYBAR_DIR/style.css"
  cp "$THEMES_DIR/$name/eww.scss" "$EWW_DIR/_theme.scss"
  backup "$style"
  sed -i '/>>> pomodoro >>>/,/<<< pomodoro <<</d' "$style"
  cat "$THEMES_DIR/$name/waybar.css" >> "$style"
  echo "$name" > "$CONFIG_DIR/theme"
}

choose_position() {
  echo; echo "  Onde colocar o pomodoro na waybar?"
  local opts=("Esquerda" "Centro" "Direita") keys=(left center right)
  select o in "${opts[@]}"; do
    if [ -n "$o" ]; then set_position "${keys[$((REPLY - 1))]}"; ok "Posição: $o"; break; fi
  done
}

choose_theme() {
  echo; echo "  Qual cor?"
  local opts=("Sage (verde-musgo)" "Lavanda (lilás)" "Névoa-mar (teal)") keys=(sage lavanda nevoamar)
  select o in "${opts[@]}"; do
    if [ -n "$o" ]; then apply_theme "${keys[$((REPLY - 1))]}"; ok "Cor: $o"; break; fi
  done
}

# Recarrega eww (config/estilo) e a waybar.
reload() {
  eww --config "$EWW_DIR" reload >/dev/null 2>&1 || true
  pkill -SIGUSR2 waybar 2>/dev/null || true
}

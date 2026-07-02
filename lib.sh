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

# Guarda a âncora do popup conforme a posição (lida pelo open.sh).
write_anchor() {
  mkdir -p "$CONFIG_DIR"
  case "$1" in
    left)  echo "top left" > "$CONFIG_DIR/anchor" ;;
    right) echo "top right" > "$CONFIG_DIR/anchor" ;;
    *)     echo "top center" > "$CONFIG_DIR/anchor" ;;
  esac
}

# Roda a TUI (ratatui) e aplica posição + cor. Fallback p/ o padrão se cancelar.
run_config() {
  local out pos theme
  if out="$("$BIN_DIR/pomo" configure)"; then
    pos="${out%% *}"
    theme="${out##* }"
  else
    warn "Configuração cancelada — usando padrão (centro, Sage)"
    pos="center"
    theme="sage"
  fi
  set_position "$pos"
  apply_theme "$theme"
  write_anchor "$pos"
  ok "Posição: $pos · Cor: $theme"
}

# Recarrega eww (config/estilo) e a waybar.
reload() {
  eww --config "$EWW_DIR" reload >/dev/null 2>&1 || true
  pkill -SIGUSR2 waybar 2>/dev/null || true
}

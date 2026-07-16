# Caminhos e funções compartilhadas.
# Fonte comum de install.sh, configure.sh e uninstall.sh (não executar direto).

BIN_DIR="$HOME/.local/bin"
EWW_DIR="$HOME/.config/eww/pomodoro"
WAYBAR_DIR="$HOME/.config/waybar"
# O Omarchy atual configura o Hyprland em Lua; o .conf é o formato antigo
# (ainda limpo no uninstall, por instalações pré-migração).
HYPR_AUTOSTART_LUA="$HOME/.config/hypr/autostart.lua"
HYPR_AUTOSTART_CONF="$HOME/.config/hypr/autostart.conf"
CONFIG_DIR="$HOME/.config/pomodoro"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/pomodoro"
THEMES_DIR="$CONFIG_DIR/themes"

EWW_DAEMON_CMD="eww --config $EWW_DIR daemon"
# Mesmo padrão do omarchy-install-service-sunshine: linha exata, idempotente.
AUTOSTART_LUA_ENTRY="o.launch_on_start(\"$EWW_DAEMON_CMD\")"

info() { printf '  \033[36m→\033[0m %s\n' "$1"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }

# Backup com timestamp antes de editar arquivos da usuária.
# Mantém só os 3 mais recentes por arquivo — sem isso, cada configure.sh
# acumula um .bak novo para sempre.
backup() {
  [ -f "$1" ] || return 0
  cp "$1" "$1.bak.$(date +%s)"
  ls -t "$1".bak.* 2>/dev/null | tail -n +4 | xargs -r rm -f
}

# Depois de remover um item de array, colapsa a vírgula que pode ter sobrado
# antes do ']' (inclusive com quebra de linha no meio: sed -z trata o arquivo
# inteiro) — uma vírgula trailing derruba o parse do config da waybar INTEIRO.
tidy_arrays() {
  sed -z -i -E 's/,([[:space:]]*\])/\1/g; s/,([[:space:]]*),/\1,/g' "$1"
}

# Remove o módulo do array onde estiver, tolerante a formatação: em linha
# própria (o formato real das configs) ou inline, no início, meio ou fim.
remove_module() {
  local cfg="$1"
  sed -i -E '/^[[:space:]]*"custom\/pomodoro",?[[:space:]]*$/d' "$cfg"
  sed -i -E 's/"custom\/pomodoro",?[[:space:]]*//g' "$cfg"
  tidy_arrays "$cfg"
}

# Insere "custom/pomodoro" no array modules-<pos> (left|center|right).
# Remove qualquer inserção anterior antes, então também serve para mudar de posição.
set_position() {
  local pos="$1" cfg="$WAYBAR_DIR/config.jsonc"
  backup "$cfg"
  remove_module "$cfg"
  sed -i "/\"modules-$pos\":/ s/\[/[\"custom\/pomodoro\", /" "$cfg"
  grep -q '"custom/pomodoro"' "$cfg" ||
    warn "não consegui inserir o módulo em modules-$pos — adicione \"custom/pomodoro\" à mão em $cfg"
}

# Adiciona o pomodoro.jsonc ao "include" da config (idempotente).
add_include() {
  local cfg="$WAYBAR_DIR/config.jsonc" inc="$WAYBAR_DIR/pomodoro.jsonc"
  grep -q "pomodoro.jsonc" "$cfg" 2>/dev/null && return 0
  backup "$cfg"
  sed -i "/\"include\":/ s#\[#[\"$inc\", #" "$cfg"
  grep -q "pomodoro.jsonc" "$cfg" ||
    warn "não consegui adicionar o include — adicione \"$inc\" ao \"include\" de $cfg"
}

# Aplica um tema: paleta do eww + bloco de accent no style.css da waybar.
apply_theme() {
  local name="$1" style="$WAYBAR_DIR/style.css"
  if [ ! -f "$THEMES_DIR/$name/eww.scss" ]; then
    warn "tema '$name' não encontrado em $THEMES_DIR — mantendo o atual"
    return 1
  fi
  cp "$THEMES_DIR/$name/eww.scss" "$EWW_DIR/_theme.scss"
  backup "$style"
  sed -i '/>>> pomodoro >>>/,/<<< pomodoro <<</d' "$style"
  cat "$THEMES_DIR/$name/waybar.css" >> "$style"
  echo "$name" > "$CONFIG_DIR/theme"
}

# Autostart do daemon eww no formato Lua do Omarchy (padrão idêntico ao
# omarchy-install-service-sunshine: linha exata, checagem idempotente);
# limpa a linha do .conf legado, que o Hyprland não lê mais.
add_autostart() {
  # Pré-condição externa: o Hyprland/Omarchy da máquina precisa carregar a
  # config Lua — sem hyprland.lua, o autostart.lua fica órfão.
  [ -f "$HOME/.config/hypr/hyprland.lua" ] ||
    warn "hyprland.lua não encontrado — confirme que seu Hyprland carrega o autostart.lua"
  mkdir -p "$(dirname "$HYPR_AUTOSTART_LUA")"
  touch "$HYPR_AUTOSTART_LUA"
  if ! grep -Fxq "$AUTOSTART_LUA_ENTRY" "$HYPR_AUTOSTART_LUA"; then
    printf '\n%s\n' "$AUTOSTART_LUA_ENTRY" >> "$HYPR_AUTOSTART_LUA"
    ok "eww daemon no autostart ($HYPR_AUTOSTART_LUA)"
  fi
  remove_autostart_conf
}

# grep -Fv em vez de sed: o comando expandido vira parte do padrão e um '#'
# no path quebraria o delimitador do sed.
remove_autostart_conf() {
  local f="$HYPR_AUTOSTART_CONF"
  [ -f "$f" ] || return 0
  grep -Fv "$EWW_DAEMON_CMD" "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  return 0
}

remove_autostart() {
  if [ -f "$HYPR_AUTOSTART_LUA" ] && grep -Fxq "$AUTOSTART_LUA_ENTRY" "$HYPR_AUTOSTART_LUA"; then
    grep -Fxv "$AUTOSTART_LUA_ENTRY" "$HYPR_AUTOSTART_LUA" > "$HYPR_AUTOSTART_LUA.tmp" &&
      mv "$HYPR_AUTOSTART_LUA.tmp" "$HYPR_AUTOSTART_LUA"
  fi
  remove_autostart_conf
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
# Valida o tema ANTES de tocar nos arquivos da usuária: com set -e, uma falha
# no meio deixaria posição trocada sem tema/âncora.
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
  if [ ! -f "$THEMES_DIR/$theme/eww.scss" ]; then
    warn "tema '$theme' indisponível — usando sage"
    theme="sage"
  fi
  apply_theme "$theme"
  write_anchor "$pos"
  set_position "$pos"
  ok "Posição: $pos · Cor: $theme"
}

# Recarrega eww (config/estilo) e a waybar.
reload() {
  eww --config "$EWW_DIR" reload >/dev/null 2>&1 || true
  pkill -SIGUSR2 waybar 2>/dev/null || true
}

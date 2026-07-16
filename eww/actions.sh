#!/usr/bin/env bash
# Ações dos botões do popup: setcfg (slider com debounce), update e uninstall.
# Instalado em ~/.config/eww/pomodoro/ junto do open.sh.

CFG_DIR="$HOME/.config/pomodoro"
EWW_DIR="$HOME/.config/eww/pomodoro"
POMO="$HOME/.local/bin/pomo"

notif() { notify-send -a Pomodoro "Pomodoro" "$1" 2>/dev/null || true; }

# Caminho do repositório clonado (gravado pelo install.sh).
repo_path() {
  local repo
  repo="$(cat "$CFG_DIR/repo" 2>/dev/null || true)"
  if [ -z "$repo" ] || [ ! -d "$repo" ]; then
    notif "Repositório não encontrado. Clone o pomodoro-timer-waybar e rode ./install.sh de novo."
    return 1
  fi
  printf '%s' "$repo"
}

case "${1:-}" in
  # Debounce do slider: guarda o valor mais recente e aplica quando a rajada
  # do arrasto dá uma folga (~150ms) — um write por pausa, não por pixel.
  # O dono do lock reaplica até o valor estabilizar: um evento que chega
  # depois do cat (com o lock ainda preso) não pode ser descartado.
  setcfg)
    key="$2" val="$3"
    run="${XDG_RUNTIME_DIR:-/tmp}"
    echo "$val" >"$run/pomo-set-$key"
    (
      flock -n 9 || exit 0
      sleep 0.15
      last=""
      val="$(cat "$run/pomo-set-$key")"
      while [ "$val" != "$last" ]; do
        "$POMO" config set "$key" "$val"
        last="$val"
        sleep 0.05
        val="$(cat "$run/pomo-set-$key")"
      done
    ) 9>"$run/pomo-set-$key.lock" &
    ;;
  # flock: clique duplo não dispara dois updates concorrentes.
  update)
    repo="$(repo_path)" || exit 1
    run="${XDG_RUNTIME_DIR:-/tmp}"
    (
      flock -n 8 || exit 0
      eww -c "$EWW_DIR" update updating=true 2>/dev/null
      bash "$repo/update.sh" >/dev/null 2>&1
      eww -c "$EWW_DIR" update updating=false 2>/dev/null
    ) 8>"$run/pomo-update.lock"
    ;;
  # A confirmação já aconteceu no popup; daqui é remoção direta. setsid:
  # o uninstall mata o daemon eww (nosso ancestral) no meio do caminho.
  uninstall)
    repo="$(repo_path)" || exit 1
    exec setsid bash "$repo/uninstall.sh"
    ;;
  *)
    echo "uso: actions.sh setcfg <chave> <valor> | update | uninstall" >&2
    exit 2
    ;;
esac

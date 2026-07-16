#!/usr/bin/env sh
# Abre/fecha o popup no monitor onde está o cursor, com a âncora escolhida no
# install. Um "backdrop" invisível atrás fecha o popup ao clicar fora.
CFG="$HOME/.config/eww/pomodoro"
anchor="$(cat "$HOME/.config/pomodoro/anchor" 2>/dev/null || echo 'top center')"

# Offset: gap da borda da tela (x) e da barra (y). A âncora "top" já começa
# abaixo da barra (layer exclusiva), então o y é um gap pequeno.
case "$anchor" in
  *center*) pos="0x6" ;;
  *)        pos="10x6" ;;
esac

# Garante o daemon de pé ANTES de qualquer `open` — senão o primeiro open paga
# o boot do daemon inteiro (o autostart cobre o caso normal; isto é o fallback).
if ! eww -c "$CFG" ping >/dev/null 2>&1; then
  eww -c "$CFG" daemon >/dev/null 2>&1
  i=0
  while [ "$i" -lt 40 ] && ! eww -c "$CFG" ping >/dev/null 2>&1; do
    sleep 0.05
    i=$((i + 1))
  done
fi

if eww -c "$CFG" active-windows 2>/dev/null | grep -q 'pomodoro'; then
  eww -c "$CFG" close pomodoro backdrop 2>/dev/null
  # Para o poll e limpa o estado transitório do popup.
  eww -c "$CFG" update popup_aberto=false confirm_uninstall=false 2>/dev/null
else
  cx="$(hyprctl cursorpos | cut -d',' -f1 | tr -d ' ')"
  mon="$(hyprctl monitors -j | jq -r --arg x "${cx:-0}" \
    '.[] | select((.x <= ($x|tonumber)) and (($x|tonumber) < (.x + .width))) | .id' | head -n1)"
  mon="${mon:-0}"

  # Estado fresco antes de mostrar (evita flash do valor :initial do poll) e
  # sempre reabre na aba Pomodoro.
  eww -c "$CFG" update "estado=$("$HOME/.local/bin/pomo" get)" \
    popup_aberto=true active_tab=0 confirm_uninstall=false updating=false 2>/dev/null
  # Backdrop SEMPRE antes do popup: na mesma camada overlay, a última janela
  # aberta fica por cima — backdrop por último engole todo clique do popup.
  eww -c "$CFG" open backdrop --screen "$mon" 2>/dev/null
  eww -c "$CFG" open pomodoro --screen "$mon" -a "$anchor" -p "$pos"
fi

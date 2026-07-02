#!/usr/bin/env sh
# Abre/fecha o popup no monitor onde está o cursor, com a âncora escolhida no install.
# Um "backdrop" transparente atrás fecha o popup ao clicar fora.
CFG="$HOME/.config/eww/pomodoro"
anchor="$(cat "$HOME/.config/pomodoro/anchor" 2>/dev/null || echo 'top center')"

# Offset: gap da borda da tela (x) e da barra (y). A âncora "top" já começa
# abaixo da barra (layer exclusiva), então o y é um gap pequeno.
case "$anchor" in
  *center*) pos="0x6" ;;
  *)        pos="10x6" ;;
esac

cx="$(hyprctl cursorpos | cut -d',' -f1 | tr -d ' ')"
mon="$(hyprctl monitors -j | jq -r --arg x "${cx:-0}" \
  '.[] | select((.x <= ($x|tonumber)) and (($x|tonumber) < (.x + .width))) | .id' | head -n1)"
mon="${mon:-0}"

if eww -c "$CFG" active-windows 2>/dev/null | grep -q 'pomodoro'; then
  eww -c "$CFG" close pomodoro backdrop 2>/dev/null
else
  eww -c "$CFG" open backdrop --screen "$mon" 2>/dev/null
  eww -c "$CFG" open pomodoro --screen "$mon" -a "$anchor" -p "$pos"
fi

#!/usr/bin/env sh
# Abre/fecha o popup no monitor onde está o cursor, com a âncora escolhida no install.
CFG="$HOME/.config/eww/pomodoro"
anchor="$(cat "$HOME/.config/pomodoro/anchor" 2>/dev/null || echo 'top center')"
cx="$(hyprctl cursorpos | cut -d',' -f1 | tr -d ' ')"
mon="$(hyprctl monitors -j | jq -r --arg x "${cx:-0}" \
  '.[] | select((.x <= ($x|tonumber)) and (($x|tonumber) < (.x + .width))) | .id' | head -n1)"
exec eww -c "$CFG" open --toggle pomodoro --screen "${mon:-0}" -a "$anchor"

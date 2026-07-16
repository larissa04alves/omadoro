#!/usr/bin/env bash
# Atualiza o pomodoro: git pull + recompila + reinstala os artefatos,
# preservando a posição e a cor escolhidas. Chamado pelo botão "Atualizar"
# do popup (via actions.sh) ou à mão.
#
# `./update.sh --force` reinstala mesmo sem commit novo — é o caminho de
# migração para uma máquina que está numa versão antiga (que não tinha este
# script): `git pull && ./update.sh --force`.
#
# Todo o corpo vive em main() e a última linha só a invoca: o git pull troca
# este arquivo no meio da execução, e o bash não pode continuar lendo um
# script que mudou sob seus pés.

main() {
  # -e: um cp/chmod falhando no meio não pode terminar em "Atualizado" — os
  # pontos com tratamento próprio (git/cargo) já usam `if !`.
  set -euo pipefail
  # Quando chamado pelo botão do popup, o processo desce do daemon eww
  # (autostart do Hyprland), que não tem o PATH do shell interativo.
  export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
  local repo before after theme force=0
  [ "${1:-}" = "--force" ] && force=1
  repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  source "$repo/lib.sh"

  notif() { notify-send -a Pomodoro "Pomodoro" "$1" 2>/dev/null || true; }

  before="$(git -C "$repo" rev-parse --short HEAD 2>/dev/null)" || {
    notif "Falha ao atualizar: $repo não é um repositório git."
    exit 1
  }
  # Working tree sujo: compilar mistura de commit novo + edição local passaria
  # por "versão oficial" — melhor parar e avisar.
  if [ -n "$(git -C "$repo" status --porcelain)" ]; then
    notif "O repositório tem mudanças locais não commitadas — resolva antes de atualizar."
    exit 1
  fi
  if ! git -C "$repo" pull --ff-only >/dev/null 2>&1; then
    notif "Falha no git pull — atualize o repositório manualmente."
    exit 1
  fi
  after="$(git -C "$repo" rev-parse --short HEAD)"
  if [ "$before" = "$after" ] && [ "$force" -eq 0 ]; then
    notif "Já está na última versão ($after)."
    exit 0
  fi

  if ! cargo build --release --manifest-path "$repo/Cargo.toml" >/dev/null 2>&1; then
    notif "Atualização baixada, mas a compilação falhou — rode ./install.sh no repo."
    exit 1
  fi
  install -Dm755 "$repo/target/release/pomo" "$BIN_DIR/pomo"

  cp "$repo/eww/eww.yuck" "$repo/eww/eww.scss" "$repo/eww/open.sh" "$repo/eww/actions.sh" "$EWW_DIR/"
  chmod +x "$EWW_DIR/open.sh" "$EWW_DIR/actions.sh"
  cp -r "$repo/themes/." "$THEMES_DIR/"
  cp "$repo/waybar/pomodoro.jsonc" "$WAYBAR_DIR/pomodoro.jsonc"

  # Migração de instalações antigas: o pointer do repo (que os botões do popup
  # usam) e o autostart em Lua não existiam — ambos idempotentes.
  mkdir -p "$CONFIG_DIR"
  echo "$repo" > "$CONFIG_DIR/repo"
  add_autostart

  # Reaplica o tema salvo (cobre eww e o bloco de cor da waybar) — nunca o
  # _theme.scss default do repo, que apagaria a cor escolhida.
  theme="$(cat "$CONFIG_DIR/theme" 2>/dev/null || echo sage)"
  apply_theme "$theme"

  # O reload do eww reseta os defvars mas NÃO fecha janelas — um popup aberto
  # ficaria congelado (poll parado). Fechar antes deixa tudo consistente.
  eww --config "$EWW_DIR" close pomodoro backdrop >/dev/null 2>&1 || true
  reload
  # Migração: se o daemon nem estava de pé (autostart antigo nunca funcionou),
  # o reload acima foi um no-op engolido — sobe o daemon com a config nova já.
  if ! eww --config "$EWW_DIR" ping >/dev/null 2>&1; then
    eww --config "$EWW_DIR" daemon >/dev/null 2>&1 || true
  fi

  if [ "$before" = "$after" ]; then
    notif "Reinstalado na versão $after."
  else
    notif "Atualizado: $before → $after"
  fi
}

main "$@"

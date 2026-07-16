# PRODUCT.md

## O que é

Timer pomodoro para a waybar do Omarchy (Hyprland). Um módulo na barra mostra o
anel de progresso + contagem regressiva; o clique abre um popup eww com duas
abas: **Pomodoro** (anel, pausar/pular/reiniciar) e **Config** (durações,
auto-início). O cérebro é um binário Rust (`pomo`) sem daemon; o estado guarda o
timestamp de fim da fase.

## Quem usa

Uma pessoa: o dono da máquina, dev em Linux/Hyprland, o dia todo, em desktop com
tema escuro. O popup aparece por segundos (ajustar/conferir o timer) e some.

## Registro

`product` — a UI serve a tarefa (controlar o timer) e deve desaparecer nela.
Nada de decoração: microinterações só para transmitir estado (rodando/pausado,
foco/pausa, hover/press), 150–250 ms, sem blur/sombra pesada (é layer-shell GTK3
via eww, custo de composição importa).

## Identidade visual (existente, preservar)

- 3 temas em `themes/*/eww.scss` + `_theme.scss` ativo: **Sage** (verde-musgo),
  **Lavanda** (lilás), **Névoa-mar** (teal, instalado hoje). Tokens: `$bg`,
  `$card-edge`, `$ink`, `$ink-dim`, `$track`, `$accent`, `$accent-break`,
  `$accent-ink`.
- Fonte única: JetBrainsMono Nerd Font (a fonte do Omarchy).
- Card escuro 24px de raio, anel `circular-progress` de 14px de espessura,
  botões circulares (play/pause em `$accent`).

## Restrições técnicas de UI

- GTK3 CSS via eww: subconjunto de CSS (sem `box-shadow` custom em layer-shell
  barato, sem `transform`); `transition` de cor/margin funciona.
- O popup abre/fecha via `open.sh` (waybar on-click) com uma janela `backdrop`
  invisível que fecha ao clicar fora — sem escurecer a tela (decisão de
  produto, 2026-07-16).
- Atualização de dados: `defpoll` de 500 ms **somente com o popup aberto**.

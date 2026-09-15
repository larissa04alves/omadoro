# PRODUCT.md

## O que é

Timer pomodoro para a barra do Omarchy (Hyprland). Um widget na barra mostra o
anel de progresso e a contagem regressiva. O clique abre um popup com duas
abas: **Pomodoro** (anel, pausar, pular, reiniciar) e **Config** (durações,
auto-início). O plugin roda dentro da omarchy-shell, sem binário próprio. O
estado guarda o instante em que a fase termina, não um contador.

## Quem usa

Uma pessoa: o dono da máquina, dev em Linux/Hyprland, o dia todo, em desktop com
tema escuro. O popup aparece por segundos (ajustar/conferir o timer) e some.

## Registro

`product`: a UI serve a tarefa (controlar o timer) e deve desaparecer nela.
Nada de decoração. Microinterações só para transmitir estado (rodando ou
pausado, foco ou pausa, hover e press), 150 a 250 ms, sem blur nem sombra
pesada. O widget vive dentro do processo da shell, então custo de composição
importa.

## Identidade visual

- Sem paleta própria. As cores vêm do tema do Omarchy, por `Color.accent` e
  `Color.foreground`. Trocar de tema troca a cor do timer junto.
- Uma cor em três intensidades: `Color.accent` cheio no foco, `Color.accent` a
  55 % na pausa, `Color.foreground` a 55 % quando o timer está pausado.
- Anel de progresso desenhado com `QtQuick.Shapes`. No popup a espessura é
  14 px. Na barra o mesmo componente assume o tamanho do slot de ícone.
- Fonte e escala vêm da shell (`bar.fontFamily`, `Style.space`). Nada de
  tamanho fixo em pixel fora do anel.

## Restrições técnicas de UI

- QML dentro da omarchy-shell, via Quickshell. A view usa os componentes de
  `Ui/` da shell (`Panel`, `KeyboardPanel`, `PanelKeyCatcher`, `PanelSlider`,
  `WidgetButton`, `ButtonGroup`), não controles próprios.
- O popup é um `KeyboardPanel` e não um `PopupCard`, porque a aba Config tem
  sliders e um interruptor que precisam de foco de teclado, e porque `Esc` só
  chega pelo `PanelKeyCatcher`, que precisa de foco.
- Não existe backdrop próprio. Clique fora e `Esc` vêm da shell.
- O popup congela o próprio relógio enquanto está fechado, para não reavaliar
  bindings atrás de uma janela que ninguém vê.
- O anel e o MM:SS da barra continuam atualizando com o popup fechado: a
  notificação de fim de fase é o produto e tem de disparar sem a janela aberta.

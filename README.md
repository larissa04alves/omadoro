# 🍅 Pomodoro para Waybar

Timer pomodoro para a waybar do Omarchy (Hyprland). Um anel de progresso com a
contagem regressiva fica na barra; ao clicar, abre um popup com duas abas —
**Pomodoro** (anel + pausar/pular/voltar) e **Config** (durações).

O cérebro é um binário em Rust (`pomo`); o popup é feito em [eww](https://github.com/elkowar/eww).

## Como funciona

Não há daemon contando segundos. O estado guarda o *timestamp* de fim da fase,
então "quanto falta" é só `fim − agora`. Quem dá o tique é a própria waybar,
que chama `pomo tick` a cada segundo:

- **`pomo tick`** (waybar) — avança o tempo, dispara notificação + som ao virar a
  fase e imprime o JSON da barra.
- **`pomo get`** (eww) — só leitura; alimenta o anel e o tempo do popup.
- **`pomo toggle | skip | restart | reset`** — os botões do popup e o clique na barra.

Config em `~/.config/pomodoro/config.json`, estado em `~/.local/state/pomodoro/state.json`.

## Requisitos

- **Rust** (`cargo`) — para compilar. `sudo pacman -S rust`
- **eww** — instalado automaticamente via `yay -S eww-git` se faltar
- `notify-send` (libnotify) e um player de som (`paplay`/`canberra`) — normalmente já vêm no Omarchy

## Instalação

```bash
git clone <repo> pomodoro-timer-waybar
cd pomodoro-timer-waybar
./install.sh
```

O instalador compila o binário, instala o popup e, no fim, pergunta:

1. **Onde** colocar o timer na waybar — esquerda, centro ou direita;
2. **Qual cor** — Sage (verde-musgo), Lavanda (lilás) ou Névoa-mar (teal).

Tudo que ele edita (`config.jsonc`, `style.css`, `autostart.conf`) recebe um
backup `.bak.<timestamp>` antes.

## Uso

- **Clique** no módulo da barra → abre/fecha o popup.
- **Clique direito** no módulo → pausa/retoma sem abrir o popup.
- No popup: **↺** reinicia a fase atual, **⏸/▶** pausa/retoma, **⏭** pula para a próxima.
- Aba **Config**: sliders para os tempos e o toggle de "iniciar a próxima fase
  automaticamente". As mudanças valem no próximo ciclo.

## Reconfigurar / desinstalar

```bash
./configure.sh   # troca posição e cor, sem recompilar
./uninstall.sh   # reverte os patches e remove os arquivos
```

## Comandos

Mudar **cor ou posição** (TUI com setas + Enter):

```bash
cd ~/Projects/pomodoro-timer-waybar && ./configure.sh
```

Mudar **durações** pelo terminal (valem no próximo ciclo, ou já no ato se o timer
estiver pausado no início):

```bash
pomo config set work 25              # foco (min)
pomo config set short 5              # pausa curta
pomo config set long 15             # pausa longa
pomo config set long_every 4        # ciclos até a pausa longa
pomo config set auto_start_next true # inicia a próxima fase sozinho
```

Controlar o timer (o mesmo que os botões do popup):

```bash
pomo toggle    # pausar / retomar
pomo skip      # pular fase
pomo restart   # reiniciar a fase atual
pomo reset     # zerar o ciclo
```

Internos, usados pela waybar/eww (não precisa rodar à mão): `pomo tick`, `pomo get`, `pomo configure`.

## Desenvolvimento

```bash
cargo test     # testes unitários (fases, tempo, formatação)
cargo clippy   # lint
cargo build --release
```

Estrutura: `src/` (Rust: `config`, `state`, `phase`, `render`), `eww/` (popup),
`themes/` (as 3 paletas), `waybar/` (módulo), scripts na raiz.

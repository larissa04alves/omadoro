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
- **`pomo get`** (eww) — só leitura; alimenta o anel e o tempo do popup
  (o poll só roda enquanto o popup está aberto).
- **`pomo toggle | skip | restart`** — os botões do popup e o clique direito na
  barra (`reset` existe só como comando de terminal).

Se o PC desligar (ou suspender por mais de ~2 min) com o timer rodando, ao voltar
a fase reaparece **pausada no tempo cheio** — o tempo não corre com o PC desligado.
Um foco **pulado** não conta para a cadência da pausa longa.

Config em `~/.config/pomodoro/config.json`, estado em `~/.local/state/pomodoro/state.json`.

## Requisitos

- **Rust** (`cargo`) — para compilar. `sudo pacman -S rust`
- **eww** — instalado automaticamente via `yay -S eww-git` se faltar
- `jq` — usado para abrir o popup no monitor onde está o cursor
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

Tudo que ele edita (`config.jsonc` e `style.css` da waybar) recebe um backup
`.bak.<timestamp>` antes (só os 3 mais recentes são mantidos). O autostart do
daemon eww entra em `~/.config/hypr/autostart.lua`, o formato Lua do Omarchy
atual — o `autostart.conf` antigo não é mais lido pelo Hyprland.

## Uso

- **Clique** no módulo da barra → abre/fecha o popup.
- **Clique direito** no módulo → pausa/retoma sem abrir o popup.
- No popup: **↺** reinicia a fase atual, **⏸/▶** pausa/retoma, **⏭** pula para a próxima.
- Aba **Config**: sliders para os tempos, o toggle de "iniciar a próxima fase
  automaticamente" (mudanças valem no próximo ciclo) e os botões
  **Atualizar** (git pull + recompila + reinstala, preservando posição/cor;
  o resultado chega por notificação) e **Remover** (com confirmação inline;
  a config em `~/.config/pomodoro` e o estado em `~/.local/state/pomodoro`
  são preservados).

## Reconfigurar / atualizar / desinstalar

```bash
./configure.sh        # troca posição e cor, sem recompilar
./update.sh           # o mesmo que o botão Atualizar do popup
./update.sh --force   # reinstala tudo mesmo sem commit novo
./uninstall.sh        # reverte os patches e remove os arquivos
```

Os botões do popup encontram o repositório pelo caminho gravado em
`~/.config/pomodoro/repo` no install — se você mover o clone, rode `./install.sh`
de novo.

## Migrar uma máquina que está numa versão antiga

Numa instalação feita antes dos botões Atualizar/Remover existirem, basta
puxar a versão nova e forçar a reinstalação — posição, cor, durações e o
estado do timer são preservados:

```bash
cd <pasta-do-clone> && git pull && ./update.sh --force
```

O `--force` também migra o que a versão antiga não tinha: o autostart do
daemon eww no formato Lua (a versão antiga escrevia num `.conf` que o
Hyprland não lê mais — era a causa da travada no primeiro clique) e o
caminho do repositório usado pelos botões do popup.

Pré-condição: o Omarchy da máquina já deve usar a config Lua do Hyprland
(`~/.config/hypr/hyprland.lua`) — o script avisa se não encontrar.

## Comandos

Mudar **cor ou posição** (TUI com setas + Enter):

```bash
cd ~/Projects/pomodoro-timer-waybar && ./configure.sh
```

Mudar **durações** pelo terminal (valem no próximo ciclo, ou já no ato se o timer
estiver pausado no início):

```bash
pomo config set work 25              # foco (min, 1 a 1440)
pomo config set short 5              # pausa curta
pomo config set long 15              # pausa longa
pomo config set long_every 4         # focos até a pausa longa
pomo config set auto_start_next true # inicia a próxima fase sozinho
```

Controlar o timer (o mesmo que os botões do popup):

```bash
pomo toggle    # pausar / retomar
pomo skip      # pular fase
pomo restart   # reiniciar a fase atual
pomo reset     # zerar o ciclo
```

Internos (não precisa rodar à mão): `pomo tick` e `pomo get` são usados pela
waybar/eww; `pomo configure` é a TUI chamada por `install.sh`/`configure.sh`.

## Desenvolvimento

```bash
cargo test     # testes unitários (fases, tempo, formatação)
cargo clippy   # lint
cargo build --release
```

Estrutura: `src/` (Rust: `config`, `state`, `phase`, `render`, `configure`),
`eww/` (popup: `eww.yuck`, `eww.scss`, `open.sh`, `actions.sh`), `themes/`
(as 3 paletas), `waybar/` (módulo), scripts na raiz (`install.sh`,
`configure.sh`, `update.sh`, `uninstall.sh`, `lib.sh` compartilhado).
Gotchas já cometidos e regras do projeto: `CLAUDE.md` e `PRODUCT.md`.

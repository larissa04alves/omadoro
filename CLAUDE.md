# CLAUDE.md — erros já cometidos aqui (não repetir)

- **SCSS: acento só em comentário `//`.** O grass (compilador do eww) emite
  `@charset "UTF-8"` no CSS se algo não-ASCII vazar pela saída (comentários
  `/* */` vazam) e o GTK rejeita a regra — o daemon sobe mas não renderiza nada.
- **Autostart do Hyprland é `autostart.lua`** (`o.launch_on_start(...)`, padrão
  do omarchy-install-service-sunshine). O `autostart.conf` existe mas está morto
  desde a migração do Omarchy para Lua — escrever `exec-once` nele falha em
  silêncio (foi a causa da travada do primeiro clique).
- **`circular-progress` do eww espera `:value` 0–100**, não a fração 0.0–1.0 de
  `State::progress` — por isso o `×100` em `render.rs`.
- **`update.sh` roda inteiro dentro de `main()`** chamada na última linha: o
  `git pull` troca o próprio arquivo em execução e o bash não pode continuar
  lendo um script que mudou sob seus pés.
- **Botões do popup descem do daemon eww** (autostart do Hyprland), não do shell
  interativo: PATH mínimo (sem mise/rustup) — `update.sh` exporta
  `~/.cargo/bin:~/.local/bin` por isso.
- **Os seds da waybar precisam tolerar o formato real** do `config.jsonc`
  (módulo em linha própria, vírgula sem espaço) — o padrão antigo
  `"custom/pomodoro", ` com espaço nunca casava na desinstalação.
- **Backdrop SEMPRE antes do popup no open.sh.** Na mesma camada overlay a
  última janela aberta fica por cima: popup→backdrop deixou o backdrop
  invisível interceptando TODOS os cliques do popup (cada clique fechava tudo).
- **`stack :same-size true` estica todas as abas para a maior** — a zona de
  botões da aba Config esticou a janela de 430 para 535px de espaço morto.
- **A janela eww cresce até o width request natural dos filhos**: label com
  `:wrap` mas sem `:width` e padding lateral gordo nos botões alargavam a aba
  Config de 290 para 326px (o card "engordava" ao trocar de aba). Segurar com
  `:width` no label e padding lateral mínimo em botão `space-evenly`.
- **`:height` da geometry é um PISO, não um alvo**: a janela nunca encolhe
  abaixo dele — com `:height "430px"`, a aba Config (~383px naturais) ficava
  com ~50px de vazio abaixo dos botões. Sem `:height`, cada aba assenta na
  altura natural. Corolário: medir 430 nas duas abas NÃO prova ausência de
  espaço morto — olhar onde o conteúdo termina, não só o xywh da janela.

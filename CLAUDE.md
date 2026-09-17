# CLAUDE.md — erros já cometidos aqui (não repetir)

- **`schemaVersion` é o número `1`, não a string `"1"`.** A string reprova nos
  dois validadores (o do host e o do `omarchy-plugin-validate`) e o plugin nem
  chega a instalar.
- **Symlink dentro do diretório do plugin é recusado pelo validador**
  (`omarchy-plugin-validate:121`, exceto sob `.git`). O laço de desenvolvimento
  é `rsync` via `scripts/dev.sh`, nunca um link do repo para
  `~/.config/omarchy/plugins`.
- **`keepLoaded: true` congela o hot-reload do `Service.qml`.**
  `unloadPluginServices()` pula de propósito os serviços com `keepLoaded`, então
  depois do reload o serviço continua rodando o código antigo. `BarWidget.qml` e
  `Panel.qml` recarregam ao salvar; `Service.qml` só com `omarchy restart shell`.
- **Um `Loader` não preenche propriedade `required`.** `KeyboardPanel` declara
  `anchorItem` e `bar` como `required`, e um objeto que não constrói vira um
  clique sem efeito e sem erro. Por isso a raiz de `Panel.qml` é um `Ui/Panel`
  (zero `required`) com o `KeyboardPanel` aninhado dentro, e o `BarWidget`
  injeta as propriedades à mão depois do `onLoaded`, testando `"nome" in alvo`.
- **`MouseArea` própria nunca recebe clique.** O `MouseArea` externo do
  `ModuleSlot` engole o press. O alvo tem de ser um `Ui/WidgetButton` (ou um
  item passado a `bar.registerClickTarget`); esquerdo, direito e meio chegam no
  mesmo `onPressed(button)`.
- **Um só `IpcHandler`, e ele mora no `Service`.** `Panel.qml` leva
  `manageIpc: false`: o painel é um por monitor, e o brinde do `Ui/Panel`
  registraria o mesmo alvo IPC duas vezes em duas telas. Os verbos de janela
  voltam pelo `shell.summon`, `shell.hide` e `shell.toggle`.
- **`updateEntryInline` só remenda a entrada in place com
  `allowMultiple: false`.** Com entradas duplicadas o host reconstrói os widgets
  e o popup fecha no meio do arrasto. Gravar configuração em `released`, nunca
  em `moved`.
- **`seenAt` não avança a cada tick, só no heartbeat e quando a fase troca.**
  Empurrar `seenAt` em todo tick faz `now - seenAt` nunca alcançar os 30 s: o
  heartbeat não dispara, o último instante visto não vai a disco e o buraco de
  120 s depois de um suspend deixa de ser detectado.
- **O host devolve `barConfig` uma escrita atrasado.** `syncPluginApis` roda
  no `onShellConfigChanged` e lê `shell.barConfig` antes da binding reavaliar;
  a `FileView` não reemite a própria gravação. Medido: três cliques seguidos, o
  serviço sempre com o valor anterior. Por isso o `Service` guarda
  `pendingEntry` (a entrada que acabou de gravar) e `setConfig` parte dela, não
  do host: senão o segundo slider reverte o primeiro. Efeito colateral: edição
  à mão do `shell.json` só aparece na próxima gravação ou no restart.
- **Depois de `scripts/dev.sh` sem `--restart`, o popup desenha a build
  anterior e o input vai para a nova.** Screenshot e clique não batem; teste de
  ponteiro só depois de `--restart`. Não há `ydotool`; o ponteiro virtual wlr
  (`zwlr_virtual_pointer_v1`, ~60 linhas de C) move e clica sem root, e
  `hyprctl dispatch movecursor` está quebrado (parser Lua).
- **`qmllint` e `qmltestrunner` só existem em `/usr/lib/qt6/bin`.** Não há nada
  no PATH desta máquina, nem stub, nem versão Qt5. Nunca `command -v qmllint`.
- **Ruído esperado do `qmllint`.** `Unqualified access` e `missing-property` em
  `bar`, `shell` e `settings` são propriedades injetadas pelo host: filtrar a
  saída, não tentar consertar o código. Os dois plugins de terceiros que servem
  de precedente fazem o mesmo.

## Agent skills

### Issue tracker

Issues vivem nas GitHub Issues deste repo, via `gh`. Veja
`docs/agents/issue-tracker.md`.

### Domain docs

Contexto único: `CONTEXT.md` na raiz e `docs/adr/`. Veja
`docs/agents/domain.md`.

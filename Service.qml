pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

// O único dono de estado do plugin: a shell monta UM Service por processo,
// e cada BarWidget (um por monitor) o encontra por `bar.shell.serviceFor`.
// Tudo que o redutor (Model.step) decide que deve acontecer no mundo real
// —persistir, notificar, tocar som— passa por `runEffect`, que é o único
// código com efeito colateral do repositório: é isso que torna as
// notificações afirmáveis sob node, em test/model.test.js, sem Qt.
Item {
  id: root

  // ---- Injetados pelo host (duck-typed: nome tem de bater exatamente).
  property string omarchyPath: ""
  property var shell: null
  property var manifest: null

  // O id vive só no manifest.json; este fallback existe apenas para o caso
  // (testes, injeção incompleta) em que `manifest` ainda não chegou.
  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "larissa04alves.omadoro"

  // ---- Configuração: lida de shell.json através da fachada do host, nunca
  //      escrita daqui a não ser por `setConfig`. Duas entradas do mesmo id
  //      (dois monitores) mesclam por chave — a primeira vence, a mesma
  //      regra que o chime usa para `settingsMerged`.
  function mergedSettings(barConfig) {
    var out = {}
    var layout = barConfig && Util.isPlainObject(barConfig.layout) ? barConfig.layout : null
    if (!layout) return out
    var regions = ["left", "center", "right"]
    for (var r = 0; r < regions.length; r++) {
      var entries = Array.isArray(layout[regions[r]]) ? layout[regions[r]] : []
      for (var i = 0; i < entries.length; i++) {
        var entry = entries[i]
        if (!Util.isPlainObject(entry) || Util.canonicalWidgetId(entry.id) !== root.pluginId) continue
        for (var key in entry) {
          if (key !== "id" && out[key] === undefined) out[key] = entry[key]
        }
      }
    }
    return out
  }

  readonly property var config: Model.normalizeConfig(mergedSettings(root.shell ? root.shell.barConfig : null))
  // Snapshot da config anterior, só para o resync de `stepConfig` (que
  // precisa comparar a duração VELHA contra a nova). Não é uma binding viva:
  // é reatribuída à mão logo abaixo, uma vez por mudança real de `config`.
  property var previousConfig: Model.normalizeConfig({})

  onConfigChanged: {
    var prev = root.previousConfig
    root.previousConfig = root.config
    if (prev.sound !== root.config.sound) {
      root.soundBroken = false
      root.soundFailures = 0
    }
    if (!root.ready) return
    root.adopt(Model.step(root.timer, { kind: "config", next: root.config }, prev, root.nowMs))
  }

  // ---- A superfície pública: timer é opaco para a UI, view é o que ela lê.
  property var timer: Model.initialTimer(root.config)
  // Bool plano, escrito em adopt: `timer` troca de referência a cada tick e
  // uma binding de precision sobre ele (ou sobre view) fecha um laço que a
  // shell loga como "Binding loop detected" (medido ao vivo nas duas formas).
  property bool running: false
  property bool ready: false
  readonly property var view: Model.view(root.timer, root.config, root.nowMs)

  property double nowMs: Date.now()

  // Segundos enquanto conta, minutos quando parado: segue o relógio de
  // parede, então se autocorrige depois de um suspend — um Timer contando
  // intervalos não faria isso.
  SystemClock {
    id: clock
    precision: root.running ? SystemClock.Seconds : SystemClock.Minutes
    onDateChanged: {
      root.nowMs = date.getTime()
      root.dispatch("tick")
    }
  }

  // ---- O redutor. UMA porta para toda transição do sistema; `dispatch` é
  //      tipado por string em vez de cinco métodos idênticos (a red flag de
  //      pass-through), e a fronteira valida contra Model.EVENTS.
  function dispatch(kind) {
    if (Model.EVENTS.indexOf(kind) === -1) {
      console.warn("omadoro: unknown event '" + kind + "'")
      return false
    }
    // Parado, o SystemClock só bate por minuto: um toggle/skip com o nowMs
    // desse último tick encurtaria a fase nova em até 59 s.
    root.nowMs = Date.now()
    root.adopt(Model.step(root.timer, { kind: kind }, root.config, root.nowMs))
    return true
  }

  // One-liners sobre dispatch(), só para o QML ler nomes em vez de strings.
  function toggle() { return root.dispatch("toggle") }
  function start() { return root.dispatch("start") }
  function skip() { return root.dispatch("skip") }
  function restart() { return root.dispatch("restart") }
  function reset() { return root.dispatch("reset") }

  // A ÚNICA porta de escrita de configuração no repositório inteiro. A
  // entrada é reconstruída a partir do valor vivo, nunca de uma cópia local:
  // um painel de outro monitor não pode ficar com um retrato velho.
  function setConfig(key, value) {
    if (!root.shell || typeof root.shell.updateEntryInline !== "function") return false
    // updateEntryInline substitui a entrada inteira: partir da entrada viva
    // preserva chaves que não são nossas (o host descarta o `id` sozinho).
    var entry = root.mergedSettings(root.shell.barConfig)
    entry[key] = value
    return root.shell.updateEntryInline(root.pluginId, entry)
  }

  function adopt(stepResult) {
    root.timer = stepResult.timer
    root.running = stepResult.timer.clock.state === "running"
    var effects = stepResult.effects
    // A ordem importa: o redutor sempre devolve persist antes de notify/sound
    // (se a shell morrer entre os dois, perde-se um aviso, nunca duplica-se).
    for (var i = 0; i < effects.length; i++) root.runEffect(effects[i])
  }

  function runEffect(effect) {
    if (effect.kind === "persist") {
      root.saveWanted = true
      if (!root.dirReady) return
      // Troca de fase e reparo gravam já: o debounce existe para o heartbeat
      // e para rajadas de clique, não para a janela entre gravar e avisar.
      if (effect.reason === "phase" || effect.reason === "repair") { saveTimer.stop(); saveTimer.triggered() }
      else saveTimer.restart()
    } else if (effect.kind === "notify") {
      root.sendNotification(effect)
    } else if (effect.kind === "sound") {
      root.playSound(effect.file)
    }
  }

  // ---------------------------------------------------------- notificação
  //
  // `--exec` consome o resto do argv como o clique-ação: com autoStartNext
  // desligado (o padrão), hoje o usuário termina o foco e fica olhando uma
  // pausa parada — a notificação vira o botão "começar". `start` é
  // idempotente, então clicar duas vezes não reinicia nada.
  function sendNotification(effect) {
    var exec = (root.omarchyPath || "/usr/share/omarchy") + "/bin/omarchy-shell"
    Quickshell.execDetached([
      "omarchy-notification-send",
      "--app-name", "Omadoro",
      "-g", effect.glyph,
      "-u", effect.urgency,
      "-t", "8000",
      Model.plainLabel(effect.title, 80),
      Model.plainLabel(effect.body, 200),
      "--exec", exec, "pomodoro", "start"
    ])
  }

  // ---------------------------------------------------------------- som
  //
  // Cadeia portátil (chime): pw-play -> paplay -> mpv -> ffplay. exitCode 3
  // (ou três falhas rápidas seguidas) trava `soundBroken` em vez de girar em
  // disco sem áudio.
  readonly property string soundScript: 'f="$1"; [[ -f "$f" && -r "$f" ]] || { sleep 2; exit 3; }; '
    + 'if command -v pw-play >/dev/null 2>&1; then exec pw-play -- "$f"; fi; '
    + 'if command -v paplay >/dev/null 2>&1; then exec paplay -- "$f"; fi; '
    + 'if command -v mpv >/dev/null 2>&1; then exec mpv --no-video --no-terminal --really-quiet -- "$f"; fi; '
    + 'if command -v ffplay >/dev/null 2>&1; then exec ffplay -nodisp -autoexit -loglevel quiet "$f"; fi; '
    + 'sleep 2; exit 3'

  property bool soundBroken: false
  property int soundFailures: 0

  function playSound(file) {
    if (root.soundBroken || soundProc.running) return
    soundProc.command = ["bash", "-c", root.soundScript, "pomodoro-sound", file]
    soundProc.running = true
  }

  Process {
    id: soundProc
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.soundFailures = 0
        return
      }
      root.soundFailures = root.soundFailures + 1
      if (exitCode === 3 || root.soundFailures >= 3) {
        root.soundBroken = true
        console.warn("omadoro: could not play sound (missing pw-play/paplay/mpv/ffplay, or file unreadable); silencing")
      }
    }
  }

  // ---------------------------------------------------------- persistência
  readonly property string stateHome: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state"))
  readonly property string stateDir: root.stateHome + "/" + root.pluginId
  readonly property string statePath: root.stateDir + "/state.json"

  property bool dirReady: false
  property bool saveWanted: false

  // FileView não cria diretório: saves ficam represados em `saveWanted` até
  // este Process sair (mesmo padrão do chime).
  Process {
    id: mkdirProc
    command: ["mkdir", "-p", root.stateDir]
    onExited: function(exitCode) {
      root.dirReady = true
      if (root.saveWanted) saveTimer.restart()
    }
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    // Restaurar é literalmente um tick com um buraco grande: a mesma regra
    // que trata o suspend trata o restart da shell — um caminho de código,
    // dois cenários.
    onLoaded: {
      root.ready = true
      root.adopt(Model.restore(text(), root.config, Date.now()))
    }
    onLoadFailed: {
      root.ready = true
      root.adopt(Model.restore("", root.config, Date.now()))
    }
    onSaveFailed: function(error) {
      console.warn("omadoro: could not write " + root.statePath + ": " + String(error))
    }
  }

  Timer {
    id: saveTimer
    interval: 250
    repeat: false
    onTriggered: {
      root.saveWanted = false
      stateFile.setText(Model.serialize(root.timer))
    }
  }

  Component.onCompleted: mkdirProc.running = true

  // -------------------------------------------------------------------- IPC
  //
  // UM handler, aqui, no serviço único. O painel leva `manageIpc: false`:
  // ele é por monitor, e registrar o mesmo alvo duas vezes (dois monitores)
  // seria o bug que o chime evita da mesma forma.
  IpcHandler {
    target: "omadoro"

    function open(): void { if (root.shell) root.shell.summon(root.pluginId, "{}") }
    function close(): void { if (root.shell) root.shell.hide(root.pluginId) }
    function toggle(): void { if (root.shell) root.shell.toggle(root.pluginId, "{}") }

    // `pause` só pausa e `start` só inicia: um bind chamado "pause" que
    // começasse a contar seria uma armadilha. `toggleRunning` alterna.
    function pause(): void { if (root.timer.clock.state === "running") root.dispatch("toggle") }
    function toggleRunning(): void { root.dispatch("toggle") }
    function start(): void { root.dispatch("start") }
    function skip(): void { root.dispatch("skip") }
    function restart(): void { root.dispatch("restart") }
    function reset(): void { root.dispatch("reset") }

    // Prova que o plugin está vivo sem precisar ler state.json.
    function health(): string {
      return JSON.stringify({
        phase: root.timer.phase,
        running: root.timer.clock.state === "running",
        remainingMs: Model.remainingMs(root.timer, root.nowMs),
        completedWork: root.timer.completedWork
      })
    }
  }
}

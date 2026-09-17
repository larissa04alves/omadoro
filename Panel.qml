pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// O popup: duas abas, Pomodoro e Config. A raiz TEM de ser qs.Ui.Panel (zero
// propriedades `required`) porque BarWidget.qml carrega isto por um Loader,
// que não consegue preencher propriedades required — o KeyboardPanel real
// (que TEM required anchorItem/bar) fica aninhado por dentro, com as
// propriedades preenchidas à mão por `injectPanel()` no host.
//
// `manageIpc: false`: o alvo IPC "pomodoro" vive no Service (singleton),
// nunca aqui — este painel existe uma vez por monitor, e registrar o mesmo
// alvo duas vezes seria o bug que o chime evita da mesma forma.
Panel {
  id: root
  manageIpc: false

  // moduleName é herdado de qs.Ui.Panel (não redeclarado — qmllint recusa
  // sombrear uma propriedade da base): amarrado ao widget que nos carregou,
  // que por sua vez recebe o id do host. O id do plugin só existe, como
  // texto, no manifest.json.
  moduleName: hostWidget ? hostWidget.moduleName : ""

  property var anchorItem: null // PLAIN, não `required` — injetado à mão
  property var hostWidget: null
  property var service: null

  // O host identifica um painel pelo widget montado no slot, não por este
  // objeto aninhado: requestPopout e switchPanelFrom usam o widget.
  readonly property var barIdentity: hostWidget || root

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color dim: Util.alpha(fg, 0.6)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var cfg: service ? service.config : Model.normalizeConfig({})

  // Congelado com o popup fechado: senão cada linha reavalia a cada segundo
  // atrás de uma janela que ninguém vê.
  // service.view já é recalculada a cada segundo para a barra; congelar uma
  // cópia aqui só criaria uma segunda verdade (e um anel que re-anima ao abrir).
  readonly property var vm: service ? service.view : Model.view(Model.initialTimer(root.cfg), root.cfg, Date.now())

  property string tab: "pomodoro" // não existe TabBar; ButtonGroup + visible

  readonly property real sliderHeight: Style.space(36) // área de clique, não visual

  // Ui/Panel.switchPanel passa `root` (este objeto aninhado) ao host, que só
  // reconhece o widget montado no slot: sem este override, Tab dentro do
  // popup é um no-op silencioso.
  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function commitSetting(name, value) {
    if (root.service) root.service.setConfig(name, value)
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    bar: root.bar
    owner: root.barIdentity
    open: root.opened
    focusTarget: keys
    contentWidth: panel.fittedContentWidth(Style.space(300))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    // KeyboardPanel e não PopupCard: Escape só chega pelo PanelKeyCatcher, que
    // precisa de foco, e PopupCard não tem foco nenhum. O catcher consome as
    // setas e Enter mesmo sem handler, então eles ganham um uso: setas trocam
    // a aba, Enter/Espaço pausa ou retoma.
    PanelKeyCatcher {
      id: keys
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) { if (dx !== 0) root.tab = dx > 0 ? "config" : "pomodoro" }
      onActivateRequested: if (root.service) root.service.toggle()
      onReturnRequested: if (root.service) root.service.toggle()

      Column {
        id: column
        anchors.fill: parent
        spacing: Style.space(12)

        ButtonGroup {
          width: parent.width
          options: ["Pomodoro", "Config"]
          value: root.tab === "pomodoro" ? "Pomodoro" : "Config"
          foreground: root.fg
          fontFamily: root.fontFamily
          onChanged: function(value) { root.tab = value === "Pomodoro" ? "pomodoro" : "config" }
        }

        PanelSeparator { foreground: root.fg }

        // -------------------------------------------------------- Pomodoro

        Column {
          visible: root.tab === "pomodoro"
          width: parent.width
          spacing: Style.space(16)

          Ring {
            id: ring
            anchors.horizontalCenter: parent.horizontalCenter
            size: 172
            thickness: 14
            progress: root.vm.progress
            phase: root.vm.phase
            paused: !root.vm.running

            Column {
              anchors.centerIn: parent
              spacing: Style.space(2)

              Text {
                textFormat: Text.PlainText
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.vm.mmss
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.displayLarge
                font.bold: true
              }

              Text {
                textFormat: Text.PlainText
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.vm.phaseLabel
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
            }
          }

          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(12)

            // Três ícones da mesma família (Nerd Font, via iconText do Button)
            // no mesmo corpo: emoji no lugar de ícone sai da fonte da shell e
            // vem colorido de outra fonte.
            // O Button dimensiona pelo glifo; o de reiniciar dá a medida.
            Button {
              id: restartButton
              iconText: "󰜉"
              tooltipText: "Reiniciar a fase"
              bordered: true
              foreground: root.fg
              fontFamily: root.fontFamily
              onClicked: if (root.service) root.service.restart()
            }

            Button {
              width: restartButton.implicitWidth
              height: restartButton.implicitHeight
              iconText: root.vm.running ? "󰏤" : "󰐊"
              tooltipText: root.vm.running ? "Pausar" : "Retomar"
              bordered: true
              selected: true
              foreground: root.fg
              fontFamily: root.fontFamily
              onClicked: if (root.service) root.service.toggle()
            }

            Button {
              width: restartButton.implicitWidth
              height: restartButton.implicitHeight
              iconText: "󰒭"
              tooltipText: "Pular a fase"
              bordered: true
              foreground: root.fg
              fontFamily: root.fontFamily
              onClicked: if (root.service) root.service.skip()
            }
          }
        }

        // ---------------------------------------------------------- Config

        Column {
          visible: root.tab === "config"
          width: parent.width
          spacing: Style.space(8)

          ConfigSlider { label: "Tempo de foco"; configKey: "work"; minimum: 5; maximum: 60 }
          ConfigSlider { label: "Pausa curta"; configKey: "short"; minimum: 1; maximum: 20 }
          ConfigSlider { label: "Pausa longa"; configKey: "long"; minimum: 10; maximum: 45 }

          Column {
            width: parent.width
            spacing: Style.space(4)

            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: "Ciclos até a pausa longa: " + Math.round(longEverySlider.dragging ? longEverySlider.liveValue : longEverySlider.value)
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            PanelSlider {
              id: longEverySlider
              width: parent.width
              height: root.sliderHeight
              bar: root.bar
              minimum: 2
              maximum: 8
              step: 1
              integer: false
              tickCount: 7
              value: root.cfg.longEvery
              onReleased: function(v) { root.commitSetting("longEvery", Math.round(v)) }
            }
          }

          Toggle {
            width: parent.width
            label: "Auto-iniciar a próxima fase"
            checked: root.cfg.autoStartNext
            foreground: root.fg
            fontFamily: root.fontFamily
            onClicked: root.commitSetting("autoStartNext", !checked)
          }
        }
      }
    }
  }

  // Inline components só podem ser filhos diretos da raiz do documento QML
  // (não podem ficar aninhados dentro de Column/PanelKeyCatcher), por isso
  // moram aqui, irmãos do KeyboardPanel, mesmo referenciados lá dentro.
  component ConfigSlider: Column {
    id: field
    required property string label
    required property string configKey
    required property int minimum
    required property int maximum
    width: parent.width
    spacing: Style.space(4)

    readonly property real shownValue: slider.dragging ? slider.liveValue : slider.value

    Text {
      textFormat: Text.PlainText
      width: parent.width
      text: field.label + ": " + Math.round(field.shownValue) + " min"
      color: root.fg
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    PanelSlider {
      id: slider
      width: parent.width
      height: root.sliderHeight
      bar: root.bar
      minimum: field.minimum
      maximum: field.maximum
      step: 1
      // Contínuo: com integer o knob salta em degraus em vez de seguir o mouse.
      integer: false
      value: root.cfg[field.configKey]
      // `released` grava uma vez, no mouse-up: uma escrita de shell.json por
      // pixel arrastado seria desperdício, e com `allowMultiple: false` uma
      // tempestade de rebuild de widget.
      onReleased: function(v) { root.commitSetting(field.configKey, Math.round(v)) }
    }
  }
}

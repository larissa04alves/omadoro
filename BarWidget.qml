pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui

// Uma instância por monitor. O id do plugin vive só no manifest.json: nunca
// se atribui `moduleName` aqui — o host injeta (via ModuleSlot.injectProps),
// e `service` é procurado por esse valor. O popup mora em Panel.qml, carregado
// por um Loader porque a raiz dele carrega propriedades `required`
// (KeyboardPanel/anchorItem) que um Loader não consegue preencher — ver o
// contrato em how-synthesis.md.
BarWidget {
  id: root

  readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor(moduleName) : null

  // Sem serviço (um frame no boot, ou o Service.qml falhou ao montar) o chip
  // mostra "--:--" e diz por quê no tooltip, em vez de fingir um timer pausado.
  readonly property var view: service ? service.view : ({
    mmss: "--:--", progress: 0, phase: "work", running: false,
    tooltip: "Omadoro: serviço não carregou (veja o log da omarchy-shell)"
  })

  // Style.bar.iconCanvas é o mesmo 16px que o protótipo do anel (ring.qml)
  // provou nítido com CurveRenderer — o "slot de ícone" natural da barra.
  readonly property real ringSize: Style.bar.iconCanvas

  implicitWidth: vertical ? barSize : content.implicitWidth + Style.space(16)
  implicitHeight: vertical ? content.implicitHeight + Style.space(6) : barSize

  // ---- Contrato de Bar.findPanelWidget: testado na RAIZ do bar-widget, não
  //      no popup. Satisfazer isto dá, de graça: roteamento de
  //      summon/hide/toggle pelo monitor certo, Tab entre painéis da barra e
  //      o ponto indicador desenhado pelo host.
  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  Loader {
    id: panelLoader
    active: true
    visible: false
    source: Qt.resolvedUrl("Panel.qml")
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }
  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  onServiceChanged: injectPanel()

  // Duck-typing à mão: a raiz do Panel.qml é um qs.Ui.Panel comum (zero
  // propriedades `required`), preenchida depois de carregada porque um
  // Loader não consegue entregar propriedades required no createObject.
  function injectPanel() {
    var t = panelLoader.item
    if (!t) return
    if ("bar" in t) t.bar = root.bar
    if ("settings" in t) t.settings = root.settings
    if ("service" in t) t.service = root.service
    if ("anchorItem" in t) t.anchorItem = button
    if ("hostWidget" in t) t.hostWidget = root
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // O anel + MM:SS são desenhados por nós, não pelo label embutido do
    // botão — sem isto ele fica com opacidade 0 (hasVisualContent olha para
    // `text`, que deixamos vazio).
    labelVisible: false
    hasVisualContent: true
    tooltipText: root.view.tooltip

    // Um handler para os três botões: WidgetButton entrega o código.
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) {
        if (root.service) root.service.toggle()
      } else if (buttonCode === Qt.MiddleButton) {
        if (root.service) root.service.restart()
      } else {
        root.toggle() // esquerdo: popup
      }
    }

    Row {
      id: content
      anchors.centerIn: parent
      spacing: Style.space(4)

      Ring {
        anchors.verticalCenter: parent.verticalCenter
        size: root.ringSize
        thickness: Math.max(2, root.ringSize * 0.16)
        progress: root.view.progress
        phase: root.view.phase
        paused: !root.view.running
        baseColor: button.foreground
      }

      Text {
        // Barra vertical: só o anel: o eixo cruzado já é forçado a barSize,
        // sem espaço sobrando para o texto MM:SS.
        visible: !root.vertical
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.view.mmss
        // button.foreground segue bar.barForeground, que muda com a barra
        // transparente; bar.foreground não.
        color: button.foreground
        font.family: button.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }
  }
}

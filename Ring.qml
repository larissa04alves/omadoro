import QtQuick
import QtQuick.Shapes
import qs.Commons

// Anel de progresso: um componente, dois tamanhos (16px na barra, 172px no
// popup). É o que substitui os 8 glifos RING_GLYPHS do render.rs do Rust —
// aqueles existiam porque a Waybar só sabe renderizar texto, uma restrição
// do host antigo, não do produto.
Item {
  id: root

  property real progress: 1.0 // 1 cheio -> 0 vazio, como o disco do Rust
  property real thickness: 14
  property real size: 172
  property string phase: "work"
  property bool paused: false

  implicitWidth: size
  implicitHeight: size
  width: size
  height: size

  // Uma cor de tema, três intensidades: sem paleta própria. O foco é o
  // accent cheio, a pausa é o mesmo accent a 55%, e pausado desbota para o
  // foreground — o que continua legível em qualquer tema do Omarchy.
  readonly property color fill: root.paused
    ? Util.alpha(Color.foreground, 0.55)
    : (root.phase === "work" ? Color.accent : Util.alpha(Color.accent, 0.55))

  // O tween anima a contagem segundo a segundo; ele é desligado num salto
  // grande (troca de fase, reinício, restauração) para o anel não dar meia
  // volta na tela.
  property real animatedProgress: root.progress
  Behavior on animatedProgress {
    enabled: Math.abs(root.progress - root.animatedProgress) <= 0.5
    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
  }

  Shape {
    id: shape
    anchors.fill: parent
    // CurveRenderer é o que fica nítido tanto a 16px quanto a 172px
    // (protótipo em scratchpad/proto/ring.qml + DECISION.md); o renderer
    // padrão do Shape serrilha visivelmente o arco fino da barra.
    preferredRendererType: Shape.CurveRenderer
    layer.enabled: true
    layer.samples: 8

    ShapePath {
      strokeWidth: root.thickness
      strokeColor: Util.alpha(Color.foreground, 0.12)
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      PathAngleArc {
        centerX: root.size / 2
        centerY: root.size / 2
        radiusX: root.size / 2 - root.thickness / 2
        radiusY: radiusX
        startAngle: -90
        sweepAngle: 360
      }
    }

    ShapePath {
      strokeWidth: root.thickness
      strokeColor: root.fill
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      PathAngleArc {
        centerX: root.size / 2
        centerY: root.size / 2
        radiusX: root.size / 2 - root.thickness / 2
        radiusY: radiusX
        startAngle: -90
        sweepAngle: 360 * root.animatedProgress
      }
    }
  }
}

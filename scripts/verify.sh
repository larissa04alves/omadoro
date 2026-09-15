#!/bin/bash
# A alavanca: valida o manifest, linta o QML contra os imports reais da
# shell instalada, roda o redutor sob node e prova que o anel renderiza.
# Falha fechado: qualquer etapa que não consiga rodar é erro, não "pulado"
# — exceto a prova ao vivo, que só roda com --live (ver final do arquivo).
#
#   scripts/verify.sh            # estático: validate, qmllint, node, anel
#   scripts/verify.sh --live     # ...e prova o plugin instalado, vivo
#
# Nada aqui toca em ~/.config/omarchy: a prova ao vivo pressupõe que o
# plugin já foi instalado por fora (scripts/dev.sh, ou omarchy plugin add).
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
shell_dir="${OMARCHY_PATH:-/usr/share/omarchy}/shell"
qmllint=/usr/lib/qt6/bin/qmllint
quickshell=/usr/bin/quickshell

fail() {
  echo "verify: $*" >&2
  exit 1
}

echo "== manifest =="
omarchy plugin validate "$here"

echo "== qmllint =="
[[ -x $qmllint ]] || fail "qmllint not found at $qmllint (qt6-declarative); never rely on PATH here"
[[ -f $shell_dir/Ui/qmldir && -f $shell_dir/Commons/qmldir ]] \
  || fail "no Omarchy shell checkout at $shell_dir (set OMARCHY_PATH)"

# O `qs.*` que Service/BarWidget/Panel/Ring importam resolve a partir de um
# import root que tem um diretório `qs` dentro — o checkout da shell É esse
# diretório, então um symlink o apelida (mesmo truque do chime).
imports=$(mktemp -d)
trap 'rm -rf "$imports"' EXIT
ln -s "$shell_dir" "$imports/qs"

qml_files=("$here/Service.qml" "$here/BarWidget.qml" "$here/Panel.qml" "$here/Ring.qml")
output=$("$qmllint" -I "$imports" "${qml_files[@]}" 2>&1) || {
  printf '%s\n' "$output"
  fail "qmllint reported errors"
}
if grep -qE "Failed to import|Warnings occurred while importing|not found\. Did you add all imports" <<<"$output"; then
  printf '%s\n' "$output"
  fail "qmllint could not resolve the shell imports; type checks did not run"
fi
# Unqualified-access/missing-property são as propriedades dinâmicas injetadas
# pelo host (bar, shell, settings, service) mostrando através — os plugins
# de primeira parte lintam igual. QProcess::ExitStatus é qmllint não
# conhecendo o segundo parâmetro de Process.onExited; "PanelWindow is not
# creatable" é qmllint lendo mal o KeyboardPanel da própria shell.
# missing-property é filtrado por SÍMBOLO (os injetados pelo host e os
# membros dinâmicos de Style/Loader.item), não por categoria: um nome de
# propriedade digitado errado num componente Ui tem de reprovar aqui.
known_members='shell|iconCanvas|bodySmall|body|displayLarge|iconLarge|family|fontFamily|foreground|open|close|toggle|opened|closeForPopoutSwitch|popoutSwitchClosing|moduleName|switchPanelFrom'
filtered=$(grep -vE "Unqualified access|Member \"($known_members)\" not found|QProcess::ExitStatus|Type PanelWindow is not creatable|^\s|^$|^import |^pragma " <<<"$output" || true)
total_lines=$(printf '%s\n' "$output" | grep -c . || true)
kept_lines=$(printf '%s\n' "$filtered" | grep -c . || true)
echo "qmllint: $total_lines linha(s) de saída, $((total_lines - kept_lines)) filtrada(s) como ruído conhecido, $kept_lines real(is)"
[[ -z $filtered ]] || {
  printf '%s\n' "$filtered"
  fail "qmllint found issues outside the known noise"
}

echo "== node test/model.test.js =="
command -v node >/dev/null || fail "node not found; the model tests did not run"
node "$here/test/model.test.js"

echo "== ring render (offscreen) =="
# Ring.qml importa qs.Commons (Color.accent, Util.alpha), e Commons/*.qml por
# sua vez importa Quickshell/Quickshell.Io — módulos C++ que só o binário
# `quickshell` registra. O runtime genérico `qml6` não os tem (falha muda,
# "Did not load any objects", sem pista) — por isso o harness roda sob
# `quickshell -p`, não sob qml6. `-p` só aceita import de caminho absoluto
# com esquema file://, nunca um caminho cru.
[[ -x $quickshell ]] || fail "quickshell not found at $quickshell"
ring_png="$imports/ring.png"
harness="$imports/tst_ring.qml"
cat >"$harness" <<EOF
import QtQuick
import QtQuick.Window
import "file://$here" as Plugin

// Instancia o Ring nos dois tamanhos reais do produto: 16px (Style.bar.iconCanvas,
// o slot da barra) e 172px (o popup). Falha fechado: se o Shape não compilar ou
// o CurveRenderer não estiver disponível, grabToImage nunca dispara e o script
// que chama isto nota a ausência do PNG.
Window {
  id: win
  width: 220
  height: 200
  visible: true
  color: "#1a1a1a"

  Plugin.Ring { x: 12; y: 12; size: 16; thickness: 2.5; progress: 0.62 }
  Plugin.Ring { x: 40; y: 12; size: 172; thickness: 14; progress: 0.62; phase: "short_break" }

  Timer {
    interval: 500
    running: true
    onTriggered: win.contentItem.grabToImage(function(result) {
      result.saveToFile("$ring_png")
      Qt.quit()
    })
  }
}
EOF
QML_IMPORT_PATH="$imports" QML2_IMPORT_PATH="$imports" QT_QPA_PLATFORM=offscreen \
  "$quickshell" -p "$harness" || fail "ring harness did not run cleanly"
[[ -f $ring_png ]] || fail "ring harness did not produce $ring_png"
# Fora do repo de propósito: o script não deve sujar `git status` a cada
# rodada.
verify_out="${XDG_CACHE_HOME:-$HOME/.cache}/pomodoro-timer-verify"
mkdir -p "$verify_out"
cp "$ring_png" "$verify_out/ring.png"
echo "ring png: $verify_out/ring.png"

echo "== live =="
if [[ "${1:-}" == "--live" ]] && command -v omarchy-shell >/dev/null 2>&1 \
  && [[ "$(omarchy-shell shell ping 2>/dev/null)" == "ok" ]]; then
  command -v jq >/dev/null || fail "jq not found; cannot parse manifest.json / health"
  id=$(jq -r '.id' "$here/manifest.json")
  out_dir=${OUT:-$imports}

  health_before=$(omarchy-shell pomodoro health)
  jq -e . >/dev/null 2>&1 <<<"$health_before" || fail "pomodoro health did not return parseable JSON: $health_before"

  omarchy-shell shell summon "$id" '{}' >/dev/null

  if command -v grim >/dev/null 2>&1; then
    focused=$(hyprctl -j monitors 2>/dev/null | jq -r '.[] | select(.focused) | .name' 2>/dev/null || true)
    if [[ -n $focused ]]; then grim -o "$focused" "$out_dir/popup.png"; else grim "$out_dir/popup.png"; fi
    echo "popup screenshot: $out_dir/popup.png"
  else
    echo "verify: grim not found, skipping popup screenshot" >&2
  fi

  omarchy-shell pomodoro skip >/dev/null
  health_after=$(omarchy-shell pomodoro health)
  [[ "$health_before" != "$health_after" ]] || fail "health did not change after skip (IPC -> service -> reducer -> disk not wired)"
  echo "live: ok"
  echo "  before: $health_before"
  echo "  after:  $health_after"
else
  echo "live: pulado"
fi

echo "verify: ok"

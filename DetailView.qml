import QtQuick
import qs.Ui
import qs.Commons

// Stat/type/ability/weakness content for whichever Pokemon is currently
// expanded. Reads dex.detail/detailPhase directly rather than taking them as
// separate bound properties, since it only ever renders the one Pokemon Dex
// currently has expanded.
Item {
  id: view

  property var dex: null
  property QtObject bar: null

  readonly property var detail: dex ? dex.detail : null
  readonly property string phase: dex ? dex.detailPhase : "idle"

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string family: bar ? bar.fontFamily : Style.font.family
  readonly property color dim: Qt.darker(fg, 1.4)

  // Base stats rarely exceed this in practice; used only to size the bars,
  // not clamped tightly — a handful of legendary stats slightly overflow
  // 255 and that's fine, the bar just reads as "basically full".
  readonly property real statMax: 255

  function capitalize(word) {
    var text = String(word || "")
    return text.length ? text.charAt(0).toUpperCase() + text.slice(1) : ""
  }

  // Presentation-only formatting, not core domain logic — the underlying
  // buckets themselves come from TypeMatchups.weaknesses and are covered by
  // tests/test_type_matchups.js; this just turns them into label lines.
  function weaknessLines(weaknesses) {
    if (!weaknesses) return []
    var lines = []
    function push(label, list) {
      if (list && list.length) {
        var names = []
        for (var i = 0; i < list.length; i++) names.push(view.capitalize(list[i]))
        lines.push(label + ": " + names.join(", "))
      }
    }
    push("Weak ×4", weaknesses.x4)
    push("Weak ×2", weaknesses.x2)
    push("Resists ×0.5", weaknesses.x0_5)
    push("Resists ×0.25", weaknesses.x0_25)
    push("Immune", weaknesses.immune)
    return lines
  }

  width: parent ? parent.width : implicitWidth
  implicitHeight: content.implicitHeight

  Column {
    id: content
    width: parent.width
    spacing: Style.spacing.lg

    Text {
      textFormat: Text.PlainText
      width: parent.width
      visible: view.phase === "loading"
      text: "Loading…"
      color: view.dim
      font.family: view.family
      font.pixelSize: Style.font.bodySmall
    }

    Text {
      textFormat: Text.PlainText
      width: parent.width
      visible: view.phase === "error"
      text: "Couldn't reach PokeAPI. Check your connection."
      wrapMode: Text.WordWrap
      color: view.dim
      font.family: view.family
      font.pixelSize: Style.font.bodySmall
    }

    // Each section below is a single child of this outer Column, so
    // Style.spacing.lg only ever separates whole sections from each other —
    // every section manages its own, much tighter, internal spacing.
    Column {
      width: parent.width
      visible: view.phase === "ready" && view.detail !== null
      spacing: Style.spacing.lg

      // ---------- header: big artwork + name/types/size ----------
      Row {
        width: parent.width
        spacing: Style.spacing.xl

        Image {
          id: artwork
          width: Style.space(132)
          height: Style.space(132)
          fillMode: Image.PreserveAspectFit
          asynchronous: true

          readonly property string localSource: view.dex && view.dex.artworkPath
            ? ("file://" + view.dex.artworkPath) : ""
          // Local cache first (instant, no network, survives a shell
          // restart). On a first-ever lookup the local file doesn't exist
          // yet, so this falls back to the remote URL — as a live binding,
          // not a one-shot check, since detail (and its spriteUrl) usually
          // only arrives *after* the local load has already failed; a
          // one-shot check made at the moment of failure would see detail
          // still null and never recover once it did arrive.
          property bool localFailed: false
          source: localFailed ? (view.detail ? view.detail.spriteUrl : "") : localSource
          // `source` reads back as a QUrl, not the plain JS string it was
          // assigned from — comparing it to localSource with === silently
          // fails (different types, even though they stringify the same),
          // so this must coerce both sides to String first.
          onStatusChanged: {
            if (status === Image.Error && String(source) === localSource) localFailed = true
          }
        }

        Column {
          anchors.verticalCenter: artwork.verticalCenter
          width: parent.width - artwork.width - Style.spacing.xl
          spacing: Style.spacing.xs

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: view.detail ? view.detail.label : ""
            color: view.fg
            font.family: view.family
            font.pixelSize: Style.font.heading
            font.bold: true
            elide: Text.ElideRight
          }

          Text {
            textFormat: Text.PlainText
            text: view.detail ? view.detail.dexNumberPadded : ""
            color: view.dim
            font.family: view.family
            font.pixelSize: Style.font.caption
          }

          Row {
            spacing: Style.spacing.xs

            Repeater {
              model: view.detail ? view.detail.types : []
              delegate: Rectangle {
                required property string modelData
                radius: Style.cornerRadius
                color: "transparent"
                border.color: view.dim
                border.width: 1
                width: typeLabel.implicitWidth + Style.spacing.md * 2
                height: typeLabel.implicitHeight + Style.spacing.xxs * 2

                Text {
                  id: typeLabel
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: view.capitalize(modelData)
                  color: view.fg
                  font.family: view.family
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            text: view.detail
              ? view.detail.heightM.toFixed(1) + " m · " + view.detail.weightKg.toFixed(1) + " kg"
              : ""
            color: view.dim
            font.family: view.family
            font.pixelSize: Style.font.caption
          }
        }
      }

      // ---------- stats: label + value + proportional bar ----------
      Column {
        width: parent.width
        spacing: Style.spacing.sm

        PanelSectionHeader {
          width: parent.width
          text: "STATS"
          foreground: view.fg
          fontFamily: view.family
        }

        Repeater {
          model: view.detail ? view.detail.stats : []
          delegate: Item {
            required property var modelData
            width: parent.width
            height: Style.space(16)

            Text {
              id: statLabel
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(56)
              text: modelData.label
              color: view.dim
              font.family: view.family
              font.pixelSize: Style.font.caption
            }

            Text {
              id: statValue
              textFormat: Text.PlainText
              anchors.left: statLabel.right
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(30)
              text: String(modelData.value)
              color: view.fg
              font.family: view.family
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignRight
            }

            Rectangle {
              anchors.left: statValue.right
              anchors.leftMargin: Style.spacing.md
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              height: Style.space(6)
              radius: height / 2
              color: Qt.darker(view.fg, 2.2)

              Rectangle {
                width: parent.width * Math.min(1, modelData.value / view.statMax)
                height: parent.height
                radius: height / 2
                color: Color.accent
              }
            }
          }
        }
      }

      // ---------- abilities ----------
      Column {
        width: parent.width
        spacing: Style.spacing.xs

        PanelSectionHeader {
          width: parent.width
          text: "ABILITIES"
          foreground: view.fg
          fontFamily: view.family
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          wrapMode: Text.WordWrap
          text: view.detail
            ? view.detail.abilities.map(function(a) {
                return a.label + (a.hidden ? " (hidden)" : "")
              }).join(", ")
            : ""
          color: view.fg
          font.family: view.family
          font.pixelSize: Style.font.caption
        }
      }

      // ---------- weaknesses ----------
      Column {
        width: parent.width
        spacing: Style.spacing.xs

        PanelSectionHeader {
          width: parent.width
          text: "WEAKNESSES"
          foreground: view.fg
          fontFamily: view.family
        }

        Column {
          width: parent.width
          spacing: Style.spacing.xxs

          Repeater {
            model: view.detail ? view.weaknessLines(view.detail.weaknesses) : []
            delegate: Text {
              required property string modelData
              textFormat: Text.PlainText
              width: parent.width
              wrapMode: Text.WordWrap
              text: modelData
              color: view.fg
              font.family: view.family
              font.pixelSize: Style.font.caption
            }
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            visible: view.detail && view.weaknessLines(view.detail.weaknesses).length === 0
            text: "No notable weaknesses or resistances."
            color: view.dim
            font.family: view.family
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}

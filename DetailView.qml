import QtQuick
import qs.Ui
import qs.Commons
import "TypeColors.js" as TypeColors

// Stat/type/ability/weakness content for whichever Pokemon is currently
// expanded. Reads dex.detail/detailPhase directly, since this only ever
// renders the one Pokemon Dex currently has expanded.
Item {
  id: view

  property var dex: null
  property QtObject bar: null

  signal evolutionJumpRequested(string name, string label)

  readonly property var detail: dex ? dex.detail : null
  readonly property string phase: dex ? dex.detailPhase : "idle"

  readonly property string evolutionPhase: dex ? dex.evolutionPhase : "idle"
  readonly property var evolutionChain: dex ? dex.evolutionChain : null
  readonly property bool hasEvolutionContent: !!(evolutionChain && (evolutionChain.linear
    ? evolutionChain.path.length > 1
    : (evolutionChain.from || evolutionChain.to.length)))

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string family: bar ? bar.fontFamily : Style.font.family
  readonly property color dim: Qt.darker(fg, 1.4)

  // Base stats rarely exceed this in practice; used only to size the bars,
  // not clamped tightly — a handful of legendary stats slightly overflow
  // 255 and that's fine, the bar just reads as "basically full".
  readonly property real statMax: 255

  readonly property color primaryTypeColor: (view.detail && view.detail.types.length)
    ? TypeColors.colorFor(view.detail.types[0]) : Color.accent

  function capitalize(word) {
    var text = String(word || "")
    return text.length ? text.charAt(0).toUpperCase() + text.slice(1) : ""
  }

  // Presentation-only: attaches a label and severity color to each
  // non-empty bucket from TypeMatchups.weaknesses, most dangerous first.
  function weaknessGroups(weaknesses) {
    if (!weaknesses) return []
    var groups = []
    function push(label, list, tint) {
      if (list && list.length) groups.push({ label: label, types: list, tint: tint })
    }
    push("WEAK ×4", weaknesses.x4, "#ff5c5c")
    push("WEAK ×2", weaknesses.x2, "#ffa15c")
    push("RESISTS ×0.5", weaknesses.x0_5, "#7fd9a8")
    push("RESISTS ×0.25", weaknesses.x0_25, "#4fd18a")
    push("IMMUNE", weaknesses.immune, "#b294ff")
    return groups
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

    // Each section is a single child here, so Style.spacing.lg only
    // separates whole sections; each manages its own tighter spacing.
    Column {
      width: parent.width
      visible: view.phase === "ready" && view.detail !== null
      spacing: Style.spacing.lg

      // ---------- header: big artwork + name/types/size ----------
      Row {
        width: parent.width
        spacing: Style.spacing.xl

        // Soft type-tinted frame behind the artwork.
        Rectangle {
          id: artworkFrame
          width: Style.space(140)
          height: Style.space(140)
          radius: Style.cornerRadius
          color: Qt.rgba(view.primaryTypeColor.r, view.primaryTypeColor.g,
                          view.primaryTypeColor.b, 0.16)

          Image {
            id: artwork
            anchors.centerIn: parent
            width: parent.width - Style.spacing.md * 2
            height: parent.height - Style.spacing.md * 2
            fillMode: Image.PreserveAspectFit
            asynchronous: true

            readonly property bool shiny: view.dex ? view.dex.isShiny : false
            readonly property string localPath: shiny
              ? (view.dex ? view.dex.shinyArtworkPath : "")
              : (view.dex ? view.dex.artworkPath : "")
            readonly property string remoteUrl: view.detail
              ? (shiny ? view.detail.shinySpriteUrl : view.detail.spriteUrl) : ""
            readonly property string localSource: localPath ? ("file://" + localPath) : ""
            // Falls back to the remote URL if the local file doesn't exist
            // yet (first-ever lookup, or a shiny roll that hasn't finished
            // downloading). A live binding, not a one-shot check, since
            // detail usually only arrives after the local load fails.
            property bool localFailed: false
            source: localFailed ? remoteUrl : localSource
            // source reads back as a QUrl, not the plain string it was
            // assigned, so this must coerce both sides to String to compare.
            onStatusChanged: {
              if (status === Image.Error && String(source) === localSource) localFailed = true
            }
          }

          // Quiet marker, not a banner: shiny colors are sometimes close
          // enough to normal that the swap alone can go unnoticed.
          Text {
            textFormat: Text.PlainText
            visible: view.dex && view.dex.isShiny
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Style.spacing.xxs
            text: "✨"
            font.family: view.family
            font.pixelSize: Style.font.body
          }
        }

        Column {
          anchors.verticalCenter: artworkFrame.verticalCenter
          width: parent.width - artworkFrame.width - Style.spacing.xl
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
              delegate: TypeBadge {
                required property string modelData
                typeName: modelData
                family: view.family
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

      // ---------- evolution: full chain when linear, immediate neighbors
      // (plus a wrapping grid) when it branches ----------
      Column {
        width: parent.width
        spacing: Style.spacing.xs
        visible: view.evolutionPhase !== "idle"
          && (view.evolutionPhase !== "ready" || view.hasEvolutionContent)

        PanelSectionHeader {
          width: parent.width
          text: "EVOLUTION"
          foreground: view.fg
          fontFamily: view.family
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          visible: view.evolutionPhase === "loading"
          text: "Loading…"
          color: view.dim
          font.family: view.family
          font.pixelSize: Style.font.caption
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          wrapMode: Text.WordWrap
          visible: view.evolutionPhase === "error"
          text: "Couldn't load evolution data."
          color: view.dim
          font.family: view.family
          font.pixelSize: Style.font.caption
        }

        // Linear chains: every stage in one strip, arrow-and-accent driven
        // purely by index vs currentIndex — no from/current/to special
        // casing needed since the whole family is always shown.
        Row {
          width: parent.width
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.spacing.xs
          visible: view.evolutionPhase === "ready" && view.evolutionChain
            && view.evolutionChain.linear

          Repeater {
            model: (view.evolutionPhase === "ready" && view.evolutionChain
              && view.evolutionChain.linear) ? view.evolutionChain.path : []
            delegate: EvolutionNode {
              required property var modelData
              required property int index
              name: modelData.name
              label: modelData.label
              spriteId: modelData.spriteId
              condition: modelData.condition
              accent: index === view.evolutionChain.currentIndex
              accentColor: view.primaryTypeColor
              clickable: index !== view.evolutionChain.currentIndex
              showArrow: index > 0
              fg: view.fg
              family: view.family
              onActivated: view.evolutionJumpRequested(name, label)
            }
          }
        }

        // Branching chains: current (plus from, plus a single inline to)
        // stays a fixed top strip; more than one to wraps below instead of
        // trying to flatten the whole tree onto one line.
        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.spacing.xs
          visible: view.evolutionPhase === "ready" && view.evolutionChain
            && !view.evolutionChain.linear

          EvolutionNode {
            visible: !!(view.evolutionChain && !view.evolutionChain.linear
              && view.evolutionChain.from)
            name: (view.evolutionChain && view.evolutionChain.from)
              ? view.evolutionChain.from.name : ""
            label: (view.evolutionChain && view.evolutionChain.from)
              ? view.evolutionChain.from.label : ""
            spriteId: (view.evolutionChain && view.evolutionChain.from)
              ? view.evolutionChain.from.spriteId : 0
            condition: (view.evolutionChain && view.evolutionChain.from)
              ? view.evolutionChain.from.condition : ""
            clickable: true
            showArrow: false
            fg: view.fg
            family: view.family
            onActivated: view.evolutionJumpRequested(name, label)
          }

          EvolutionNode {
            label: view.detail ? view.detail.label : ""
            // detail.id is the raw per-form id from /pokemon/{id-or-name},
            // the same numeric id IndexSearch.js's spriteId field is derived
            // from — no extra index lookup needed for the current Pokemon.
            spriteId: view.detail ? view.detail.id : 0
            accent: true
            accentColor: view.primaryTypeColor
            clickable: false
            showArrow: !!(view.evolutionChain && !view.evolutionChain.linear
              && view.evolutionChain.from)
            fg: view.fg
            family: view.family
          }

          EvolutionNode {
            visible: !!(view.evolutionChain && !view.evolutionChain.linear
              && view.evolutionChain.to.length === 1)
            name: (view.evolutionChain && !view.evolutionChain.linear
              && view.evolutionChain.to.length === 1) ? view.evolutionChain.to[0].name : ""
            label: (view.evolutionChain && !view.evolutionChain.linear
              && view.evolutionChain.to.length === 1) ? view.evolutionChain.to[0].label : ""
            spriteId: (view.evolutionChain && !view.evolutionChain.linear
              && view.evolutionChain.to.length === 1) ? view.evolutionChain.to[0].spriteId : 0
            condition: (view.evolutionChain && !view.evolutionChain.linear
              && view.evolutionChain.to.length === 1) ? view.evolutionChain.to[0].condition : ""
            clickable: true
            showArrow: true
            fg: view.fg
            family: view.family
            onActivated: view.evolutionJumpRequested(name, label)
          }
        }

        // Branching chains with more than one "to" wrap below the top
        // strip instead of squeezing into one line, same pattern the
        // weakness chips already use for their own overflow.
        Flow {
          width: parent.width
          spacing: Style.spacing.md
          visible: !!(view.evolutionChain && !view.evolutionChain.linear
            && view.evolutionChain.to.length > 1)

          Repeater {
            model: (view.evolutionPhase === "ready" && view.evolutionChain
              && !view.evolutionChain.linear && view.evolutionChain.to.length > 1)
              ? view.evolutionChain.to : []
            delegate: EvolutionNode {
              required property var modelData
              name: modelData.name
              label: modelData.label
              spriteId: modelData.spriteId
              condition: modelData.condition
              clickable: true
              showArrow: true
              fg: view.fg
              family: view.family
              onActivated: view.evolutionJumpRequested(name, label)
            }
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
          spacing: Style.spacing.sm

          // Label and chips share one wrapping Flow so a group with just
          // one or two types stays a single line instead of two.
          Repeater {
            model: view.detail ? view.weaknessGroups(view.detail.weaknesses) : []
            delegate: Flow {
              required property var modelData
              width: parent.width
              spacing: Style.spacing.xs

              Rectangle {
                radius: Style.cornerRadius
                color: "transparent"
                border.color: modelData.tint
                border.width: 1
                width: severityLabel.implicitWidth + Style.spacing.md * 2
                height: severityLabel.implicitHeight + Style.spacing.xxs * 2

                Text {
                  id: severityLabel
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: modelData.label
                  color: modelData.tint
                  font.family: view.family
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }

              Repeater {
                model: modelData.types
                delegate: TypeBadge {
                  required property string modelData
                  typeName: modelData
                  family: view.family
                }
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            visible: view.detail && view.weaknessGroups(view.detail.weaknesses).length === 0
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

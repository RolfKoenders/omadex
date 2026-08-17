import QtQuick
import qs.Ui
import qs.Commons
import "PokemonDetail.js" as PokemonDetail
import "PokeApi.js" as PokeApi

// One search-result row plus its inline expansion. Quickdex has exactly
// one expansion kind, so there's no domain-switch needed here.
CursorSurface {
  id: row

  required property string entryName
  required property string entryLabel
  required property int entryNumber
  required property int entrySpriteId

  property var dex: null
  property QtObject bar: null
  property bool expanded: false

  signal cursorRequested()
  signal expandToggled()

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string family: bar ? bar.fontFamily : Style.font.family
  readonly property color dim: Qt.darker(fg, 1.4)

  foreground: fg
  current: expanded
  radius: Style.cornerRadius
  implicitHeight: layout.implicitHeight + Style.spacing.rowPaddingX

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onContainsMouseChanged: if (containsMouse) row.cursorRequested()
    onClicked: row.expandToggled()
  }

  Column {
    id: layout
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.spacing.xl
    anchors.rightMargin: Style.spacing.xl
    spacing: Style.spacing.lg

    Item {
      width: parent.width
      implicitHeight: Math.max(sprite.height, labels.implicitHeight)

      // Remote per-form thumbnail, not locally cached like the detail
      // artwork — small, numerous, and only seen while online anyway.
      Image {
        id: sprite
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Style.font.display
        height: Style.font.display
        asynchronous: true
        fillMode: Image.PreserveAspectFit
        source: PokeApi.spriteUrlFor(row.entrySpriteId)
      }

      Column {
        id: labels
        anchors.left: sprite.right
        anchors.leftMargin: Style.spacing.xl
        anchors.right: numberText.left
        anchors.rightMargin: Style.spacing.lg
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.xxs

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: row.entryLabel
          color: row.fg
          font.family: row.family
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
      }

      Text {
        id: numberText
        textFormat: Text.PlainText
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: PokemonDetail.padNumber(row.entryNumber)
        color: row.dim
        font.family: row.family
        font.pixelSize: Style.font.caption
      }
    }

    PanelSeparator {
      width: parent.width
      visible: expansion.active
      foreground: row.fg
    }

    Loader {
      id: expansion
      width: parent.width
      // Unloaded on collapse so nothing keeps polling/holding state offscreen.
      active: row.expanded && row.dex !== null
      visible: active

      sourceComponent: DetailView {
        dex: row.dex
        bar: row.bar
      }
    }
  }
}

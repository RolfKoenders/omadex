import QtQuick
import qs.Ui
import qs.Commons
import "PokeApi.js" as PokeApi

// One node in an evolution chain strip: sprite, name, and an optional
// condition label, with an optional leading arrow baked in (not a sibling
// item) so a wrapping Flow can never split an arrow from the node it points
// to onto separate lines. The current Pokemon uses accent/non-clickable;
// from/to neighbors are clickable and unaccented.
Item {
  id: node

  required property string label
  property string name: ""
  property int spriteId: 0
  property string condition: ""
  property bool accent: false
  property color accentColor: Color.accent
  property bool clickable: false
  property bool showArrow: false

  property color fg: Color.foreground
  property string family: Style.font.family
  readonly property color dim: Qt.darker(fg, 1.4)

  signal activated()

  readonly property int spriteSize: Style.space(44)

  implicitWidth: layout.implicitWidth
  implicitHeight: layout.implicitHeight

  Row {
    id: layout
    spacing: Style.spacing.xs

    Text {
      textFormat: Text.PlainText
      visible: node.showArrow
      anchors.verticalCenter: parent.verticalCenter
      text: "→"
      color: node.dim
      font.family: node.family
      font.pixelSize: Style.font.body
    }

    Column {
      spacing: Style.spacing.xxs
      width: Math.max(node.spriteSize, nameText.implicitWidth, conditionText.implicitWidth)

      Rectangle {
        width: node.spriteSize
        height: node.spriteSize
        radius: Style.cornerRadius
        anchors.horizontalCenter: parent.horizontalCenter
        color: node.accent
          ? Qt.rgba(node.accentColor.r, node.accentColor.g, node.accentColor.b, 0.16)
          : "transparent"
        border.color: node.accent ? node.accentColor : "transparent"
        border.width: node.accent ? 1 : 0

        Image {
          anchors.centerIn: parent
          width: parent.width - Style.spacing.xxs * 2
          height: width
          asynchronous: true
          fillMode: Image.PreserveAspectFit
          source: node.spriteId ? PokeApi.spriteUrlFor(node.spriteId) : ""
        }

        MouseArea {
          anchors.fill: parent
          enabled: node.clickable
          hoverEnabled: node.clickable
          cursorShape: node.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: node.activated()
        }
      }

      Text {
        id: nameText
        textFormat: Text.PlainText
        anchors.horizontalCenter: parent.horizontalCenter
        text: node.label
        color: node.fg
        font.family: node.family
        font.pixelSize: Style.font.caption
      }

      Text {
        id: conditionText
        textFormat: Text.PlainText
        visible: node.condition.length > 0
        anchors.horizontalCenter: parent.horizontalCenter
        text: node.condition
        color: node.dim
        font.family: node.family
        font.pixelSize: Style.font.caption
      }
    }
  }
}

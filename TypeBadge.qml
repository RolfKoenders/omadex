import QtQuick
import qs.Commons
import "TypeColors.js" as TypeColors

// A colored chip for a single Pokemon type name. Used for the type row in
// the detail header and for every type chip in the weaknesses section.
Rectangle {
  id: badge

  required property string typeName
  property string family: Style.font.family
  property real fontSize: Style.font.caption

  radius: Style.cornerRadius
  color: TypeColors.colorFor(typeName)
  width: label.implicitWidth + Style.spacing.md * 2
  height: label.implicitHeight + Style.spacing.xxs * 2

  Text {
    id: label
    anchors.centerIn: parent
    textFormat: Text.PlainText
    // Fixed dark text reads reliably across the whole mid-to-light palette.
    color: "#1b1b26"
    text: badge.typeName.length
      ? badge.typeName.charAt(0).toUpperCase() + badge.typeName.slice(1) : ""
    font.family: badge.family
    font.pixelSize: badge.fontSize
    font.bold: true
  }
}

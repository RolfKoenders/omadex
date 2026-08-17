import QtQuick
import QtQuick.Controls
import qs.Ui
import qs.Commons

// Bar button plus popup panel. Owns the keyboard cursor and search field;
// Dex owns the index, cache, and fetch state.
Panel {
  id: root
  moduleName: "omadex"
  ipcTarget: "omadex"

  property Dex dex: Dex {}

  // One cursor for keyboard and mouse, per the CursorSurface contract.
  property int cursorIndex: 0
  property bool cursorActive: false

  readonly property int rowCount: dex.results.length

  onOpenedChanged: if (!opened) {
    cursorActive = false
    cursorIndex = 0
    dex.query = ""
    dex.collapse()
  }

  // First press just wakes the cursor at index 0; only the next one moves it.
  function moveCursor(delta) {
    if (rowCount === 0) return
    if (!cursorActive) { cursorActive = true; return }
    cursorIndex = Math.max(0, Math.min(rowCount - 1, cursorIndex + delta))
  }

  function currentResult() {
    if (cursorIndex < 0 || cursorIndex >= dex.results.length) return null
    return dex.results[cursorIndex]
  }

  // While a row is expanded, Up/Down scroll the popup instead of moving the
  // cursor, since the expanded content can be taller than the scroll area.
  function scrollDetail(direction) {
    var flick = listScroller.contentItem
    if (!flick) return
    var step = Style.space(72)
    var maxY = Math.max(0, flick.contentHeight - flick.height)
    flick.contentY = Math.max(0, Math.min(maxY, flick.contentY + direction * step))
  }

  function expandCursor() {
    var result = currentResult()
    if (result) dex.selectPokemon(result.name)
  }

  // First Escape clears the filter, second Escape closes the popup.
  function handleEscape() {
    if (dex.query.length) dex.query = ""
    else root.close()
  }

  readonly property string icon: String.fromCodePoint(0xF041D) // md-pokeball

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string family: bar ? bar.fontFamily : Style.font.family
  readonly property color dim: Qt.darker(fg, 1.4)

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // Scrolls a newly expanded row to the top of the popup instead of leaving
  // it wherever it sits in a long list. Retried on a short timer rather than
  // done inline, since the row's Loader hasn't measured its content yet at
  // the moment expandedSlug changes, and re-run again once detailPhase goes
  // "ready" to cover a Pokemon that needed a fresh network fetch.
  function scrollExpandedIntoView() {
    scrollToRowTimer.restart()
  }

  Timer {
    id: scrollToRowTimer
    interval: 60
    onTriggered: {
      var flick = listScroller.contentItem
      var slug = root.dex.expandedSlug
      if (!flick || !slug) return
      var idx = -1
      for (var i = 0; i < root.dex.results.length; i++) {
        if (root.dex.results[i].name === slug) { idx = i; break }
      }
      var item = idx >= 0 ? resultRepeater.itemAt(idx) : null
      if (!item) return
      var maxY = Math.max(0, flick.contentHeight - flick.height)
      flick.contentY = Math.max(0, Math.min(maxY, item.y))
    }
  }

  Connections {
    target: root.dex
    function onExpandedSlugChanged() {
      if (root.dex.expandedSlug) root.scrollExpandedIntoView()
      else if (listScroller.contentItem) listScroller.contentItem.contentY = 0
    }
    function onDetailPhaseChanged() {
      if (root.dex.expandedSlug && root.dex.detailPhase === "ready") root.scrollExpandedIntoView()
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    foreground: root.fg
    onPressed: root.toggle()
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    // KeyboardPanel force-focuses this on every open with its own timing —
    // don't also focus it from Panel's onOpenedChanged, that races it.
    focusTarget: searchField
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // Redundant with searchField's own Keys handlers below; whichever one
      // Qt routes the event to fires, both call the same functions.
      onCloseRequested: root.handleEscape()
      onMoveRequested: function(dx, dy) {
        if (dy === 0) return
        if (root.dex.expandedSlug) root.scrollDetail(dy)
        else root.moveCursor(dy)
      }
      onActivateRequested: root.expandCursor()

      Column {
        id: column
        anchors.fill: parent
        spacing: Style.spacing.panelGap

        PanelHero {
          width: parent.width
          title: "Omadex"
          foreground: root.fg
          fontFamily: root.family

          iconComponent: Text {
            textFormat: Text.PlainText
            text: root.icon
            color: root.fg
            font.family: root.family
            font.pixelSize: Style.font.display
          }
        }

        PanelSeparator { width: parent.width; foreground: root.fg }

        TextField {
          id: searchField
          width: parent.width
          placeholderText: "Search a Pokémon…"
          foreground: root.fg
          text: root.dex.query
          onTextChanged: {
            root.dex.query = text
            root.cursorIndex = 0
            root.cursorActive = false
          }
          Keys.onDownPressed: function(event) {
            if (root.dex.expandedSlug) root.scrollDetail(1)
            else root.moveCursor(1)
            event.accepted = true
          }
          Keys.onUpPressed: function(event) {
            if (root.dex.expandedSlug) root.scrollDetail(-1)
            else root.moveCursor(-1)
            event.accepted = true
          }
          Keys.onEscapePressed: function(event) { root.handleEscape(); event.accepted = true }
          // A custom Keys.onReturnPressed here stops QQC2's own accepted()
          // signal from firing, so both call expandCursor() directly.
          Keys.onReturnPressed: function(event) { root.expandCursor(); event.accepted = true }
          Keys.onEnterPressed: function(event) { root.expandCursor(); event.accepted = true }
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          visible: root.dex.indexPhase === "loading"
          text: "Loading index…"
          wrapMode: Text.WordWrap
          color: root.dim
          font.family: root.family
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          visible: root.dex.indexPhase === "ready"
            && root.dex.query.length > 0 && root.dex.results.length === 0
          text: "No matches."
          wrapMode: Text.WordWrap
          color: root.dim
          font.family: root.family
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          visible: root.dex.indexPhase === "error"
          text: "Couldn't reach PokeAPI. Check your connection."
          wrapMode: Text.WordWrap
          color: root.dim
          font.family: root.family
          font.pixelSize: Style.font.bodySmall
        }

        ScrollView {
          id: listScroller
          visible: root.dex.results.length > 0
          width: parent.width
          implicitHeight: Math.min(rowsColumn.implicitHeight, Style.space(420))
          clip: true
          ScrollBar.vertical.policy: ScrollBar.AsNeeded

          Column {
            id: rowsColumn
            width: listScroller.availableWidth
            spacing: Style.spacing.hairline

            Repeater {
              id: resultRepeater
              model: root.dex.results
              delegate: ResultRow {
                // Required properties put this delegate in required-mode,
                // so index must be declared here or Qt stops injecting it.
                required property int index
                required property var modelData

                width: rowsColumn.width
                dex: root.dex
                bar: root.bar
                entryName: modelData.name
                entryLabel: modelData.label
                entryNumber: modelData.number
                entrySpriteId: modelData.spriteId
                hasCursor: root.cursorActive && root.cursorIndex === index
                expanded: root.dex.expandedSlug === modelData.name
                onCursorRequested: {
                  root.cursorActive = true
                  root.cursorIndex = index
                }
                onExpandToggled: root.dex.selectPokemon(modelData.name)
              }
            }
          }
        }
      }
    }
  }
}

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

  // The first arrow press only wakes the cursor at its current index (0) —
  // it does not also move it. Without this split, the very first Down press
  // both activates *and* applies delta=1 in the same call, landing on index
  // 1 (the second result) instead of highlighting index 0 first.
  function moveCursor(delta) {
    if (rowCount === 0) return
    if (!cursorActive) { cursorActive = true; return }
    cursorIndex = Math.max(0, Math.min(rowCount - 1, cursorIndex + delta))
  }

  function currentResult() {
    if (cursorIndex < 0 || cursorIndex >= dex.results.length) return null
    return dex.results[cursorIndex]
  }

  // While a detail panel is expanded, the popup's own content can be taller
  // than the fixed-height scroll area, so Up/Down switch from moving the
  // list cursor to scrolling the popup instead — otherwise there is no
  // keyboard-only way to reach a weakness bucket below the fold. ScrollView
  // wraps non-Flickable content (this Column) in an internal Flickable
  // automatically, which is what exposes contentY/contentHeight here.
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

  // First Escape clears an active filter; second Escape (or Escape on an
  // empty field) closes the popup — matches the shell's built-in emojis and
  // clipboard pickers.
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

  // A newly expanded (or collapsed) row starts scrolled to the top of the
  // popup rather than wherever the previous row's scroll happened to land.
  Connections {
    target: root.dex
    function onExpandedSlugChanged() {
      if (listScroller.contentItem) listScroller.contentItem.contentY = 0
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
    // KeyboardPanel force-focuses this target itself on every open, with
    // its own correctly-timed Exclusive->OnDemand priming sequence — do not
    // also try to focus the field independently from Panel's onOpenedChanged,
    // that raced this and lost, leaving focus on keyCatcher (which has no
    // handler for plain text keys) instead of the field.
    focusTarget: searchField
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // Belt-and-suspenders with the search field's own Keys handlers below:
      // whichever one Qt actually routes the event to will accept it first,
      // so only one of the two paths ever fires for a given keypress — both
      // call the same root functions, so behavior is identical either way.
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
          // See the belt-and-suspenders note on keyCatcher above — these
          // fire as the focused item regardless of any ancestor's key
          // priority, so navigation works whether or not PanelKeyCatcher's
          // own handling reaches a focused text field first.
          // When a row is expanded, arrows scroll the popup to reveal
          // content below the fold instead of moving between list items —
          // list navigation resumes automatically once the row collapses.
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
          // Confirmed live: wiring a custom Keys.onReturnPressed on this
          // control intercepts Return before QQC2's own accepted() signal
          // fires, so onAccepted never runs once a handler is here — call
          // expandCursor() directly from both instead of relying on it.
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
                // See hass/Panel.qml's identical comment: required properties
                // put the delegate in required-properties mode, which stops
                // Qt from injecting `index` as a context property unless it
                // is asked for by name here.
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

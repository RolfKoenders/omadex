import QtQuick
import QtQuick.Controls
import qs.Ui
import qs.Commons

// Bar button plus popup panel. Owns the keyboard cursor and search field;
// Dex owns the index, cache, and fetch state.
Panel {
  id: root
  moduleName: "quickdex"
  ipcTarget: "quickdex"

  property Dex dex: Dex {}

  // One cursor for keyboard and mouse, per the CursorSurface contract.
  property int cursorIndex: 0
  property bool cursorActive: false

  // Tab peeks at Recents without losing whatever's typed; typing again (see
  // searchField.onTextChanged) drops back out. Not a multi-stop cycle, just
  // a toggle, so Tab and Shift+Tab both flip it the same way.
  property bool recentsForced: false
  readonly property bool showRecents: recentsForced || dex.query.length === 0
  readonly property var activeResults: showRecents ? dex.recentResults : dex.results

  readonly property int rowCount: activeResults.length

  onOpenedChanged: if (!opened) {
    cursorActive = false
    cursorIndex = 0
    recentsForced = false
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
    if (cursorIndex < 0 || cursorIndex >= activeResults.length) return null
    return activeResults[cursorIndex]
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

  // Sets dex.query directly, not searchField.text — the field's text is a
  // live binding to dex.query (`text: root.dex.query` below), and assigning
  // straight to searchField.text would permanently sever that binding, so
  // the field would stop clearing on close after the first jump. Setting
  // dex.query lets the existing binding update the field as a side effect,
  // which still fires onTextChanged and resets cursor/recentsForced exactly
  // as manual typing already does. Selection itself happens directly by
  // slug, not by relying on the new query matching exactly one result and
  // waiting for Enter.
  function jumpTo(name, label) {
    dex.query = label
    dex.selectPokemon(name)
  }

  // Left/Right navigate the evolution chain only while something's
  // expanded (mirrors Up/Down's scroll-vs-navigate split). Left always has
  // at most one target (a species has exactly one parent); Right does
  // nothing when there's more than one "to" — no unambiguous next step to
  // pick, that requires clicking a specific branch.
  function navigateEvolution(direction) {
    var chain = dex.evolutionChain
    if (!chain) return
    var target = null
    if (chain.linear) {
      var idx = chain.currentIndex + direction
      if (idx >= 0 && idx < chain.path.length) target = chain.path[idx]
    } else if (direction < 0) {
      target = chain.from
    } else if (chain.to.length === 1) {
      target = chain.to[0]
    }
    if (target) root.jumpTo(target.name, target.label)
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
      for (var i = 0; i < root.activeResults.length; i++) {
        if (root.activeResults[i].name === slug) { idx = i; break }
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
        if (dy !== 0) {
          if (root.dex.expandedSlug) root.scrollDetail(dy)
          else root.moveCursor(dy)
        }
        if (dx !== 0 && root.dex.expandedSlug) root.navigateEvolution(dx)
      }
      onActivateRequested: root.expandCursor()
      onTabRequested: function(direction) {
        root.recentsForced = !root.recentsForced
        root.cursorActive = false
        root.cursorIndex = 0
      }

      Column {
        id: column
        anchors.fill: parent
        spacing: Style.spacing.panelGap

        PanelHero {
          width: parent.width
          title: "Quickdex"
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
            root.recentsForced = false
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
          // Unlike Up/Down, Left/Right have a real native meaning here
          // (moving the text cursor), so only take over once something's
          // expanded. Keys.onXxxPressed defaults event.accepted to true the
          // moment a handler exists at all, even one that never touches it —
          // simply not setting it here still silently blocks the field's
          // own cursor movement, confirmed live. Must explicitly set it to
          // false to actually let the event fall through to native handling.
          Keys.onLeftPressed: function(event) {
            if (root.dex.expandedSlug) { root.navigateEvolution(-1); event.accepted = true }
            else event.accepted = false
          }
          Keys.onRightPressed: function(event) {
            if (root.dex.expandedSlug) { root.navigateEvolution(1); event.accepted = true }
            else event.accepted = false
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
          visible: !root.showRecents && root.dex.indexPhase === "ready"
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

        PanelSectionHeader {
          width: parent.width
          visible: root.showRecents && root.activeResults.length > 0
          text: "RECENT"
          foreground: root.fg
          fontFamily: root.family
        }

        ScrollView {
          id: listScroller
          visible: root.activeResults.length > 0
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
              model: root.activeResults
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
                onEvolutionJumpRequested: function(name, label) { root.jumpTo(name, label) }
              }
            }
          }
        }
      }
    }
  }
}

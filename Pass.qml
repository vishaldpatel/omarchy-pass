import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "PassSearch.js" as PassSearch

Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property string filterText: ""
  property int selectedIndex: 0
  property var entries: []
  property var recent: []
  property bool loading: false
  property bool storeMissing: false

  property string home: Quickshell.env("HOME")
  property string storeDir: Quickshell.env("PASSWORD_STORE_DIR") || (home + "/.password-store")
  property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")) + "/pass-widget"
  property string helper: decodeURIComponent(Qt.resolvedUrl("pass-copy.sh").toString().replace(/^file:\/\//, ""))

  // Shares the [menu] surface tokens, like the built-in emoji and clipboard
  // pickers, so every theme styles this overlay too.
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color accent: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int cardWidth: Math.min(Style.space(620), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(470), panel.height - Style.gapsOut * 2)
  property int headerHeight: Math.max(Style.space(40), Style.font.heading + Style.spacing.controlPaddingY * 2)
  property int footerHeight: Math.max(Style.space(26), Style.font.caption + Style.space(12))
  property int rowHeight: Math.max(Style.space(46), Style.font.title + Style.space(24))

  function open(payloadJson) {
    root.filterText = ""
    root.selectedIndex = 0
    root.opened = true
    root.refreshEntries()
    recentFile.reload()
    root.rebuildDisplay()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "vishal.pass")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function refreshEntries() {
    if (listProc.running) return
    root.loading = root.entries.length === 0
    listProc.running = true
  }

  function rebuildDisplay() {
    var rows = PassSearch.rank(root.entries, root.recent, root.filterText, 200)
    var accentHex = root.accent.toString()

    displayModel.clear()
    for (var i = 0; i < rows.length; i++) {
      var name = rows[i].name
      var slash = name.lastIndexOf("/")
      var leaf = slash >= 0 ? name.slice(slash + 1) : name
      var folder = slash >= 0 ? name.slice(0, slash) : ""
      var initial = (leaf.match(/[A-Za-z0-9]/) || ["?"])[0].toUpperCase()
      displayModel.append({
        name: name,
        leafMarkup: PassSearch.highlight(leaf, rows[i].positions, slash + 1, accentHex),
        folder: folder,
        initial: initial,
        recent: rows[i].recent
      })
    }

    if (selectedIndex >= displayModel.count) selectedIndex = Math.max(0, displayModel.count - 1)
    Qt.callLater(function() {
      if (displayModel.count > 0) resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  function setFilter(next) {
    root.filterText = next
    root.selectedIndex = 0
    root.rebuildDisplay()
  }

  function select(delta) {
    if (displayModel.count === 0) return
    root.selectedIndex = (root.selectedIndex + delta + displayModel.count) % displayModel.count
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function selectClamped(delta) {
    if (displayModel.count === 0) return
    root.selectedIndex = Math.max(0, Math.min(displayModel.count - 1, root.selectedIndex + delta))
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function copy(index, field) {
    if (index < 0 || index >= displayModel.count) return
    var name = displayModel.get(index).name
    // Close first so a pinentry prompt can take keyboard focus.
    root.dismiss()
    Quickshell.execDetached(["bash", root.helper, field, name])
  }

  ListModel { id: displayModel }

  Process {
    id: listProc
    command: ["find", "-L", root.storeDir, "-path", "*/.git", "-prune", "-o", "-type", "f", "-name", "*.gpg", "-printf", "%P\\n"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.entries = PassSearch.parseEntries(text)
        root.loading = false
        if (root.opened) root.rebuildDisplay()
      }
    }
    onExited: function(code) {
      root.storeMissing = code !== 0 && root.entries.length === 0
      root.loading = false
    }
  }

  FileView {
    id: recentFile
    path: root.stateDir + "/recent"
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.recent = PassSearch.parseRecent(text())
      if (root.opened) root.rebuildDisplay()
    }
    onLoadFailed: root.recent = []
    onFileChanged: reload()
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "vishal-pass"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
      opacity: root.opened ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 140 } }
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      opacity: root.opened ? 1 : 0
      scale: root.opened ? 1 : 0.96
      Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
      Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
          var shift = (event.modifiers & Qt.ShiftModifier) !== 0

          if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else root.dismiss()
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
          } else if (event.key === Qt.Key_Up || (ctrl && (event.key === Qt.Key_P || event.key === Qt.Key_K))
                     || (event.key === Qt.Key_Backtab)) {
            root.select(-1)
          } else if (event.key === Qt.Key_Down || (ctrl && (event.key === Qt.Key_N || event.key === Qt.Key_J))
                     || (event.key === Qt.Key_Tab && !shift)) {
            root.select(1)
          } else if (event.key === Qt.Key_PageUp) {
            root.selectClamped(-6)
          } else if (event.key === Qt.Key_PageDown) {
            root.selectClamped(6)
          } else if (event.key === Qt.Key_Home && ctrl) {
            root.selectClamped(-displayModel.count)
          } else if (event.key === Qt.Key_End && ctrl) {
            root.selectClamped(displayModel.count)
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.copy(root.selectedIndex, shift ? "username" : "password")
          } else if (!ctrl && event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setFilter(root.filterText + event.text)
          } else {
            return
          }
          event.accepted = true
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.spacing.md

        // ── Search field ─────────────────────────────────────────────
        Rectangle {
          id: searchField
          width: parent.width
          height: root.headerHeight
          radius: root.cornerRadius
          color: Util.alpha(root.foreground, 0.05)
          border.width: Style.normalBorderWidth
          border.color: Util.alpha(root.accent, root.filterText ? 0.55 : 0.18)
          Behavior on border.color { ColorAnimation { duration: 140 } }

          Text {
            id: lockGlyph
            anchors.left: parent.left
            anchors.leftMargin: Style.space(14)
            anchors.verticalCenter: parent.verticalCenter
            text: "󰌾"
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
          }

          Item {
            anchors.left: lockGlyph.right
            anchors.leftMargin: Style.space(12)
            anchors.right: countLabel.left
            anchors.rightMargin: Style.space(10)
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            clip: true

            Text {
              id: queryText
              textFormat: Text.PlainText
              anchors.verticalCenter: parent.verticalCenter
              x: root.filterText ? 0 : caret.width + Style.space(4)
              width: Math.min(implicitWidth, parent.width - caret.width - Style.space(4))
              text: root.filterText || "Search passwords…"
              color: root.foreground
              opacity: root.filterText ? 1 : 0.45
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              elide: Text.ElideLeft
            }

            Rectangle {
              id: caret
              x: root.filterText ? queryText.width + Style.space(1) : 0
              anchors.verticalCenter: parent.verticalCenter
              width: Math.max(2, Style.space(2))
              height: Style.font.heading + Style.space(4)
              radius: width / 2
              color: root.accent

              SequentialAnimation on opacity {
                running: root.opened
                loops: Animation.Infinite
                NumberAnimation { to: 1; duration: 0 }
                PauseAnimation { duration: 530 }
                NumberAnimation { to: 0; duration: 120 }
                PauseAnimation { duration: 400 }
                NumberAnimation { to: 1; duration: 120 }
              }
            }
          }

          Text {
            id: countLabel
            anchors.right: parent.right
            anchors.rightMargin: Style.space(14)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.filterText ? (displayModel.count + " / " + root.entries.length) : (root.entries.length + " entries")
            color: root.foreground
            opacity: 0.45
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        // ── Results ──────────────────────────────────────────────────
        Item {
          width: parent.width
          height: parent.height - root.headerHeight - root.footerHeight - Style.spacing.md * 2

          ListView {
            id: resultList
            anchors.fill: parent
            model: displayModel
            clip: true
            spacing: Style.space(2)
            boundsBehavior: Flickable.StopAtBounds
            highlightFollowsCurrentItem: false
            currentIndex: root.selectedIndex

            section.property: root.filterText ? "" : "recent"
            section.criteria: ViewSection.FullString
            section.delegate: Item {
              required property string section
              width: ListView.view.width
              height: Style.space(26)
              Text {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Style.space(4)
                textFormat: Text.PlainText
                text: parent.section === "true" ? "RECENT" : "ALL ENTRIES"
                color: root.foreground
                opacity: 0.4
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1.2
                font.weight: Font.DemiBold
              }
            }

            delegate: Rectangle {
              id: row
              required property int index
              required property string name
              required property string leafMarkup
              required property string folder
              required property string initial
              required property bool recent

              readonly property bool hasCursor: index === root.selectedIndex

              width: ListView.view.width
              height: root.rowHeight
              radius: root.cornerRadius
              color: hasCursor ? root.selectedBackground : (rowMouse.containsMouse ? Util.alpha(root.foreground, 0.03) : "transparent")
              Behavior on color { ColorAnimation { duration: 90 } }

              // Accent rail on the selected row.
              Rectangle {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(2, Style.space(3))
                height: row.hasCursor ? parent.height * 0.5 : 0
                radius: width / 2
                color: root.accent
                Behavior on height { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
              }

              // Monogram badge.
              Rectangle {
                id: badge
                anchors.left: parent.left
                anchors.leftMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                width: root.rowHeight - Style.space(16)
                height: width
                radius: Math.min(root.cornerRadius, width / 2)
                color: Util.alpha(root.accent, row.hasCursor ? 0.24 : 0.12)

                Text {
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: row.initial
                  color: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  font.weight: Font.Bold
                }
              }

              Column {
                anchors.left: badge.right
                anchors.leftMargin: Style.space(12)
                anchors.right: trailing.left
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(1)

                Text {
                  width: parent.width
                  textFormat: Text.StyledText
                  text: row.leafMarkup
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  elide: Text.ElideRight
                }

                Text {
                  visible: row.folder.length > 0
                  width: parent.width
                  textFormat: Text.PlainText
                  text: "󰉋  " + row.folder
                  color: root.foreground
                  opacity: 0.45
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideMiddle
                }
              }

              Item {
                id: trailing
                anchors.right: parent.right
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                width: row.hasCursor ? copyHint.width : recentGlyph.width
                height: parent.height

                Text {
                  id: recentGlyph
                  visible: row.recent && !row.hasCursor
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  text: "󰋚"
                  color: root.foreground
                  opacity: 0.35
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }

                Rectangle {
                  id: copyHint
                  visible: row.hasCursor
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  width: hintText.implicitWidth + Style.space(16)
                  height: hintText.implicitHeight + Style.space(8)
                  radius: root.cornerRadius
                  color: Util.alpha(root.accent, 0.16)

                  Text {
                    id: hintText
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: "󰆏  Copy"
                    color: root.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.weight: Font.DemiBold
                  }
                }
              }

              MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: function(mouse) {
                  root.selectedIndex = row.index
                  root.copy(row.index, mouse.button === Qt.RightButton ? "username" : "password")
                }
              }
            }
          }

          // ── Empty / loading states ─────────────────────────────────
          Column {
            anchors.centerIn: parent
            width: parent.width
            spacing: Style.space(8)
            visible: displayModel.count === 0 && !root.loading

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: root.storeMissing || root.entries.length === 0 ? "󰟵" : "󰈉"
              color: root.accent
              opacity: 0.8
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
            }

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              textFormat: Text.PlainText
              text: root.storeMissing || root.entries.length === 0
                ? "No password store at " + root.storeDir
                : "No entries match “" + root.filterText + "”"
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              elide: Text.ElideMiddle
            }
          }
        }

        // ── Footer key hints ─────────────────────────────────────────
        Item {
          width: parent.width
          height: root.footerHeight

          Rectangle {
            anchors.top: parent.top
            width: parent.width
            height: Style.normalBorderWidth
            color: Util.alpha(root.foreground, 0.08)
          }

          Row {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(4)
            anchors.bottom: parent.bottom
            spacing: Style.space(16)

            Repeater {
              model: [
                { keys: "↵", label: "Password" },
                { keys: "⇧ ↵", label: "Username" },
                { keys: "↑ ↓", label: "Navigate" },
                { keys: "Esc", label: "Close" }
              ]

              delegate: Row {
                required property var modelData
                spacing: Style.space(6)

                Rectangle {
                  anchors.verticalCenter: parent.verticalCenter
                  width: keyLabel.implicitWidth + Style.space(10)
                  height: keyLabel.implicitHeight + Style.space(4)
                  radius: Math.max(3, root.cornerRadius / 2)
                  color: Util.alpha(root.foreground, 0.08)
                  border.width: Style.normalBorderWidth
                  border.color: Util.alpha(root.foreground, 0.12)

                  Text {
                    id: keyLabel
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: modelData.keys
                    color: root.foreground
                    opacity: 0.8
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: modelData.label
                  color: root.foreground
                  opacity: 0.5
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }
        }
      }
    }
  }
}

import QtQuick
import qs.Ui

BarWidget {
  id: root
  moduleName: "vishal.pass"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰌾"
    tooltipText: "Passwords"
    onPressed: function(button) {
      if (!root.bar) return
      root.bar.run("omarchy-shell shell toggle vishal.pass '{}'")
    }
  }
}

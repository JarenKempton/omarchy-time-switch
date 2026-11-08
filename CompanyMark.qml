import QtQuick
import "Model.js" as Model

// A company's logo, or its initial on its color when it has no logo.
Item {
  id: root

  property var company: null
  property string logo: ""          // data: URL from Service.logoFor()
  property real size: 18
  property string fontFamily: "Inter"

  readonly property color tint: company && company.color !== "" ? company.color : "#7aa2f7"

  implicitWidth: size
  implicitHeight: size
  width: size
  height: size

  Image {
    id: image
    anchors.fill: parent
    visible: root.logo !== "" && status === Image.Ready
    source: root.logo
    sourceSize: Qt.size(Math.ceil(root.size * 2), Math.ceil(root.size * 2))
    fillMode: Image.PreserveAspectFit
    smooth: true
    asynchronous: true
  }

  Rectangle {
    anchors.fill: parent
    visible: !image.visible
    radius: Math.round(root.size * 0.28)
    color: root.tint

    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: Model.initial(root.company ? root.company.name : "")
      color: "#13141c"
      font.family: root.fontFamily
      font.pixelSize: Math.round(root.size * 0.55)
      font.weight: Font.Bold
    }
  }
}

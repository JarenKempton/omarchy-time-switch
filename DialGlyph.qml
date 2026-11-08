import QtQuick
import QtQuick.Shapes

// An open clock dial: a ring with a gap at the top right, and two hands.
// Drawn on a 24-unit grid and scaled to `size`.
Item {
  id: root

  property real size: 16
  property color color: "white"
  property real strokeWidth: 1.9

  implicitWidth: size
  implicitHeight: size
  width: size
  height: size

  Shape {
    width: 24
    height: 24
    scale: root.size / 24
    transformOrigin: Item.TopLeft
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      fillColor: "transparent"
      strokeColor: root.color
      strokeWidth: root.strokeWidth
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathSvg { path: "M12 3.5a8.5 8.5 0 1 0 8.5 8.5" }
    }
    ShapePath {
      fillColor: "transparent"
      strokeColor: root.color
      strokeWidth: root.strokeWidth
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathSvg { path: "M12 7.5V12l3 2" }
    }
  }
}

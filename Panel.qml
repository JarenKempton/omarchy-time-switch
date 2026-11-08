import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// Time Switch bar widget: a pill showing the running session, and a panel to
// start or stop one. Keyboard: j/k move, Enter starts the selected company,
// 1–9 start by position, s stops, o opens the dashboard, r refreshes, Esc
// closes.
Panel {
  id: root
  moduleName: "jaren.timeswitch"
  ipcTarget: "jaren.timeswitch"
  manageIpc: false

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  Service {
    id: svc
    settings: root.settings
    panelOpen: root.opened
  }

  // ---- look ----------------------------------------------------------------
  readonly property string uiFont: "Inter"
  readonly property color fg: Commons.Color.foreground
  readonly property color bright: Qt.lighter(fg, 1.12)
  readonly property color muted: Qt.rgba(fg.r, fg.g, fg.b, 0.6)
  readonly property color faint: Qt.rgba(fg.r, fg.g, fg.b, 0.32)
  readonly property color line: Qt.rgba(1, 1, 1, 0.07)
  readonly property color danger: Commons.Color.urgent
  readonly property color accent: Commons.Color.accent
  readonly property color selectedFill: Style.selectedFillFor(fg, accent)
  readonly property color companyTint: svc.activeCompany && svc.activeCompany.color !== "" ? svc.activeCompany.color : accent

  function clockTime(ms) {
    if (!isFinite(ms)) return ""
    return new Date(ms).toLocaleTimeString(Qt.locale(Commons.I18n.formatLocale), Locale.ShortFormat)
  }
  function hours(sec) { return Model.formatHours(sec) }

  // ---- panel state ---------------------------------------------------------
  property int cursor: 0
  readonly property string view: {
    if (svc.phase === "setup" || svc.phase === "denied") return "connect"
    if (svc.tracking) return "tracking"
    if (svc.phase === "ready") return "idle"
    return "waiting"
  }

  function clampCursor() {
    cursor = Math.max(0, Math.min(cursor, svc.companies.length - 1))
  }
  function startAt(index) {
    if (index < 0 || index >= svc.companies.length) return
    svc.start(svc.companies[index].id)
  }
  function openDashboard() {
    if (svc.server !== "" && bar) bar.run("xdg-open " + Util.shellQuote(svc.server))
  }
  function toggleSession() {
    if (svc.tracking) svc.stop()
    else if (svc.companies.length === 1) svc.start(svc.companies[0].id)
    else root.open()
  }

  onOpenedChanged: if (opened) {
    cursor = 0
    Qt.callLater(function() { if (panel.loadedContent) panel.loadedContent.forceActiveFocus() })
  }

  Connections {
    target: svc
    function onCompaniesChanged() { root.clampCursor() }
  }

  ShellIpc {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { svc.refresh(); return "ok" }
    function toggleSession(): string { root.toggleSession(); return "ok" }
    function status(): string {
      if (!svc.configured) return "setup"
      return svc.tracking ? "tracking " + Model.formatClock(svc.elapsed) : "idle"
    }
  }

  // ---- bar pill ------------------------------------------------------------
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Item {
    id: button
    anchors.fill: parent
    implicitWidth: pill.width + Style.space(6)
    implicitHeight: root.bar ? root.bar.barSize : Style.bar.sizeHorizontal

    readonly property bool live: svc.tracking
    readonly property bool trouble: svc.phase === "offline" || svc.phase === "denied" || svc.phase === "forbidden" || svc.phase === "setup"

    Rectangle {
      id: pill
      anchors.centerIn: parent
      height: Math.round(Style.bar.iconSlot * 0.82)
      width: pillRow.implicitWidth + pillRow.leftPad + pillRow.rightPad
      radius: height / 2
      color: button.live ? Qt.rgba(root.companyTint.r, root.companyTint.g, root.companyTint.b, 0.22)
                         : Qt.rgba(1, 1, 1, mouse.containsMouse || root.opened ? 0.11 : 0.075)
      border.width: button.live ? 1 : 0
      border.color: Qt.rgba(root.companyTint.r, root.companyTint.g, root.companyTint.b, 0.35)
      scale: mouse.pressed ? 0.96 : 1
      Behavior on scale { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }

      Row {
        id: pillRow
        readonly property real leftPad: button.live ? Style.space(4) : Style.space(6)
        readonly property real rightPad: button.live || button.trouble && svc.phase === "offline" ? Style.space(8) : Style.space(6)
        x: leftPad
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(5)

        CompanyMark {
          visible: button.live
          anchors.verticalCenter: parent.verticalCenter
          size: Style.space(16)
          company: svc.activeCompany
          logo: svc.logoFor(svc.activeCompany)
          fontFamily: root.uiFont
        }
        DialGlyph {
          visible: !button.live
          anchors.verticalCenter: parent.verticalCenter
          size: Style.space(15)
          color: root.bright
          opacity: button.trouble ? 0.45 : 1
        }
        Text {
          visible: button.live
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: Model.formatPill(svc.elapsed)
          color: root.bright
          font.family: root.uiFont
          font.pixelSize: Style.space(12)
          font.weight: Font.DemiBold
          font.features: { "tnum": 1 }
        }
        Text {
          visible: !button.live && svc.phase === "offline"
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: strings.t("offline")
          color: root.muted
          font.family: root.uiFont
          font.pixelSize: Style.space(11)
        }
      }
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      onClicked: function(event) {
        if (event.button === Qt.RightButton) root.toggleSession()
        else if (event.button === Qt.MiddleButton) svc.refresh()
        else root.toggle()
      }
      onContainsMouseChanged: {
        if (!root.bar) return
        if (!containsMouse || root.opened) { root.bar.hideTooltip(button); return }
        var text = svc.tracking ? strings.t("tooltipSince").arg(root.clockTime(svc.session.startedAt))
                 : svc.phase === "ready" ? strings.t("tooltipIdle") : ""
        if (text !== "") root.bar.showTooltip(button, text)
      }
    }
  }

  // ---- panel ---------------------------------------------------------------
  AttachedPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(296))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(480))

    content: PanelKeyCatcher {
      id: keys
      anchors.fill: parent
      implicitHeight: body.implicitHeight
      blocked: connectForm.editing

      onMoveRequested: function(dx, dy) {
        if (root.view !== "idle" || svc.companies.length === 0) return
        root.cursor = Math.max(0, Math.min(svc.companies.length - 1, root.cursor + dy))
      }
      onActivateRequested: {
        if (root.view === "idle") root.startAt(root.cursor)
        else if (root.view === "connect") connectForm.submit()
      }
      onCloseRequested: root.close()
      onTabRequested: function(direction) {
        if (root.view === "connect") connectForm.focusFirst()
        else root.switchPanel(direction)
      }
      onTextKey: function(t) {
        if (t === "s" || t === "S") svc.stop()
        else if (t === "o" || t === "O") root.openDashboard()
        else if (t === "r" || t === "R") svc.refresh()
        else if (root.view === "idle" && t >= "1" && t <= "9") root.startAt(Number(t) - 1)
      }

      Column {
        id: body
        width: parent.width
        spacing: 0

        // Header: mark tile + two lines of state.
        Row {
          width: parent.width
          spacing: Style.space(10)

          Rectangle {
            width: Style.space(30)
            height: Style.space(30)
            radius: Style.space(9)
            color: Qt.rgba(0, 0, 0, 0.25)
            border.width: 1
            border.color: root.line

            CompanyMark {
              visible: root.view === "tracking"
              anchors.centerIn: parent
              size: Style.space(20)
              company: svc.activeCompany
              logo: svc.logoFor(svc.activeCompany)
              fontFamily: root.uiFont
            }
            DialGlyph {
              visible: root.view !== "tracking"
              anchors.centerIn: parent
              size: Style.space(18)
              color: root.bright
              opacity: root.view === "connect" || svc.phase === "offline" ? 0.55 : 1
            }
          }

          Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - Style.space(40)
            spacing: Style.space(1)

            Text {
              width: parent.width
              textFormat: Text.PlainText
              elide: Text.ElideRight
              color: root.bright
              font.family: root.uiFont
              font.pixelSize: Style.space(13)
              font.weight: Font.DemiBold
              text: root.view === "tracking" ? strings.t("tracking")
                  : root.view === "idle" ? strings.t("offTheClock")
                  : root.view === "connect" ? strings.t("connectTitle")
                  : svc.phase === "offline" ? strings.t("unreachable")
                  : svc.phase === "forbidden" ? strings.t("forbidden")
                  : strings.t("connecting")
            }
            Text {
              width: parent.width
              textFormat: Text.PlainText
              wrapMode: Text.Wrap
              maximumLineCount: 2
              elide: Text.ElideRight
              color: root.muted
              font.family: root.uiFont
              font.pixelSize: Style.space(12)
              text: root.view === "tracking" ? strings.t("since").arg(root.clockTime(svc.session.startedAt))
                  : root.view === "idle" ? (isFinite(svc.lastEnded) ? strings.t("lastEnded").arg(root.clockTime(svc.lastEnded)) : strings.t("noSessions"))
                  : root.view === "connect" ? (svc.phase === "denied" ? strings.t("denied") : strings.t("connectHint"))
                  : svc.phase === "forbidden" ? strings.t("forbiddenHint")
                  : svc.server
            }
          }
        }

        // Inline error, e.g. a failed start.
        Text {
          visible: svc.lastError !== "" && root.view !== "connect" && svc.phase !== "forbidden"
          width: parent.width
          topPadding: Style.space(8)
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          color: root.danger
          font.family: root.uiFont
          font.pixelSize: Style.space(11)
          text: svc.lastError
        }

        // ---- tracking: big timer + stop ----
        Item {
          visible: root.view === "tracking"
          width: parent.width
          height: visible ? Style.space(60) : 0

          Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: Style.space(4)
            Text {
              textFormat: Text.PlainText
              text: Model.formatShort(svc.elapsed)
              color: root.bright
              font.family: root.uiFont
              font.pixelSize: Style.space(42)
              font.weight: Font.Medium
              font.letterSpacing: -Style.space(1)
              font.features: { "tnum": 1 }
            }
            Text {
              textFormat: Text.PlainText
              text: ":" + Model.formatClock(svc.elapsed).slice(-2)
              color: root.muted
              font.family: root.uiFont
              font.pixelSize: Style.space(42)
              font.weight: Font.Medium
              font.letterSpacing: -Style.space(1)
              font.features: { "tnum": 1 }
            }
          }

          Rectangle {
            id: stopButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: Style.space(4)
            width: Style.space(44)
            height: Style.space(44)
            radius: Style.space(14)
            color: Qt.rgba(root.danger.r, root.danger.g, root.danger.b, stopMouse.containsMouse ? 0.22 : 0.14)
            border.width: 1
            border.color: Qt.rgba(root.danger.r, root.danger.g, root.danger.b, 0.25)
            opacity: svc.busy ? 0.5 : 1
            scale: stopMouse.pressed ? 0.95 : 1
            Behavior on scale { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }

            Rectangle {
              anchors.centerIn: parent
              width: Style.space(12)
              height: Style.space(12)
              radius: Style.space(3)
              color: root.danger
            }
            MouseArea {
              id: stopMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: svc.stop()
            }
          }
        }

        // ---- idle: one start card per company ----
        Column {
          visible: root.view === "idle"
          width: parent.width
          topPadding: Style.space(16)
          spacing: Style.space(8)

          Text {
            textFormat: Text.PlainText
            text: svc.companies.length > 0 ? strings.t("startSession") : strings.t("noCompanies")
            color: root.muted
            font.family: root.uiFont
            font.pixelSize: Style.space(11)
            wrapMode: Text.Wrap
            width: parent.width
          }

          Repeater {
            model: svc.companies
            delegate: Rectangle {
              id: card
              required property var modelData
              required property int index
              readonly property bool selected: index === root.cursor
              readonly property color tint: modelData.color !== "" ? modelData.color : root.accent
              width: parent.width
              height: Style.space(52)
              radius: Style.space(12)
              color: selected ? Qt.rgba(tint.r, tint.g, tint.b, 0.12) : Qt.rgba(1, 1, 1, cardMouse.containsMouse ? 0.07 : 0.045)
              border.width: 1
              border.color: selected ? Qt.rgba(tint.r, tint.g, tint.b, 0.45) : Qt.rgba(1, 1, 1, 0.06)
              opacity: svc.busy ? 0.6 : 1

              Row {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(10)

                CompanyMark {
                  anchors.verticalCenter: parent.verticalCenter
                  size: Style.space(26)
                  company: card.modelData
                  logo: svc.logoFor(card.modelData)
                  fontFamily: root.uiFont
                }
                Column {
                  anchors.verticalCenter: parent.verticalCenter
                  Text {
                    textFormat: Text.PlainText
                    text: isFinite(svc.periodSeconds(card.modelData.id)) ? root.hours(svc.periodSeconds(card.modelData.id)) + strings.t("hoursSuffix") : "–"
                    color: root.bright
                    font.family: root.uiFont
                    font.pixelSize: Style.space(13)
                    font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                  }
                  Text {
                    textFormat: Text.PlainText
                    text: strings.t("thisPayPeriod")
                    color: root.muted
                    font.family: root.uiFont
                    font.pixelSize: Style.space(11)
                  }
                }
              }

              Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(28)
                height: Style.space(28)
                radius: Style.space(9)
                color: card.selected ? card.tint : Qt.rgba(1, 1, 1, 0.06)

                // Play triangle.
                Canvas {
                  anchors.centerIn: parent
                  anchors.horizontalCenterOffset: Style.space(1)
                  width: Style.space(10)
                  height: Style.space(11)
                  property color ink: card.selected ? "white" : root.bright
                  onInkChanged: requestPaint()
                  onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    ctx.fillStyle = ink
                    ctx.beginPath()
                    ctx.moveTo(0, 0)
                    ctx.lineTo(width, height / 2)
                    ctx.lineTo(0, height)
                    ctx.closePath()
                    ctx.fill()
                  }
                }
              }

              MouseArea {
                id: cardMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.cursor = card.index
                onClicked: root.startAt(card.index)
              }
            }
          }
        }

        // ---- totals ----
        Item {
          visible: root.view === "tracking" || root.view === "idle"
          width: parent.width
          height: visible ? stats.implicitHeight + Style.space(28) : 0

          Rectangle {
            y: Style.space(16)
            width: parent.width
            height: 1
            color: root.line
          }

          Row {
            id: stats
            y: Style.space(28)
            width: parent.width
            readonly property bool withPeriod: root.view === "tracking"
            readonly property real cell: withPeriod ? width / 3 : width / 2

            Repeater {
              model: stats.withPeriod
                ? [{ k: "today", v: svc.todaySeconds }, { k: "week", v: svc.weekSeconds }, { k: "payPeriod", v: svc.tracking ? svc.periodSeconds(svc.session.companyId) : NaN }]
                : [{ k: "today", v: svc.todaySeconds }, { k: "week", v: svc.weekSeconds }]
              delegate: Column {
                required property var modelData
                width: stats.cell
                spacing: Style.space(2)
                Text {
                  textFormat: Text.PlainText
                  text: strings.t(modelData.k)
                  color: root.muted
                  font.family: root.uiFont
                  font.pixelSize: Style.space(11)
                }
                Row {
                  spacing: Style.space(2)
                  Text {
                    textFormat: Text.PlainText
                    text: isFinite(modelData.v) ? root.hours(modelData.v) : "–"
                    color: root.bright
                    font.family: root.uiFont
                    font.pixelSize: Style.space(15)
                    font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                  }
                  Text {
                    anchors.baseline: parent.children[0].baseline
                    visible: isFinite(modelData.v)
                    textFormat: Text.PlainText
                    text: strings.t("hoursSuffix")
                    color: root.muted
                    font.family: root.uiFont
                    font.pixelSize: Style.space(12)
                  }
                }
              }
            }
          }
        }

        // ---- connect form ----
        Column {
          id: connectForm
          visible: root.view === "connect"
          width: parent.width
          topPadding: Style.space(14)
          spacing: Style.space(8)

          readonly property bool editing: visible && (serverField.activeFocus || idField.activeFocus || secretField.activeFocus)
          property string message: ""
          property bool saving: false

          function focusFirst() { serverField.forceActiveFocus() }
          function submit() {
            if (saving) return
            message = ""
            if (Model.normalizeServer(serverField.text) === "" || !Model.validClientId(idField.text) || !Model.validClientSecret(secretField.text)) {
              message = strings.t("invalid")
              return
            }
            saving = true
            svc.saveCredentials(serverField.text, idField.text, secretField.text)
          }

          function prefill() {
            serverField.text = svc.server
            idField.text = svc.clientId
            secretField.text = ""
            message = ""
          }
          Component.onCompleted: prefill()
          onVisibleChanged: if (visible) prefill()
          // The saved files load after the form is built; fill in what
          // arrives unless the user is already typing there.
          Connections {
            target: svc
            function onServerChanged() { if (!serverField.activeFocus) serverField.text = svc.server }
            function onClientIdChanged() { if (!idField.activeFocus) idField.text = svc.clientId }
          }

          Connections {
            target: svc
            function onSaved(ok) {
              connectForm.saving = false
              if (ok) secretField.text = ""
              else connectForm.message = strings.t("saveFailed")
            }
          }

          Text { textFormat: Text.PlainText; text: strings.t("server"); color: root.muted; font.family: root.uiFont; font.pixelSize: Style.space(11) }
          TextField {
            id: serverField
            width: parent.width
            placeholderText: "https://time.example.com"
            KeyNavigation.tab: idField
            Keys.onReturnPressed: idField.forceActiveFocus()
            Keys.onEscapePressed: keys.forceActiveFocus()
          }
          Text { textFormat: Text.PlainText; text: strings.t("clientId"); color: root.muted; font.family: root.uiFont; font.pixelSize: Style.space(11) }
          TextField {
            id: idField
            width: parent.width
            placeholderText: "…….access"
            KeyNavigation.tab: secretField
            Keys.onReturnPressed: secretField.forceActiveFocus()
            Keys.onEscapePressed: keys.forceActiveFocus()
          }
          Text { textFormat: Text.PlainText; text: strings.t("clientSecret"); color: root.muted; font.family: root.uiFont; font.pixelSize: Style.space(11) }
          TextField {
            id: secretField
            width: parent.width
            password: true
            KeyNavigation.tab: serverField
            Keys.onReturnPressed: connectForm.submit()
            Keys.onEscapePressed: keys.forceActiveFocus()
          }

          Text {
            visible: connectForm.message !== ""
            width: parent.width
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            text: connectForm.message
            color: root.danger
            font.family: root.uiFont
            font.pixelSize: Style.space(11)
          }

          Rectangle {
            width: parent.width
            height: Style.space(36)
            radius: Style.space(9)
            color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, connectMouse.containsMouse ? 0.26 : 0.18)
            Text {
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: connectForm.saving ? strings.t("saving") : strings.t("connect")
              color: root.accent
              font.family: root.uiFont
              font.pixelSize: Style.space(13)
              font.weight: Font.DemiBold
            }
            MouseArea {
              id: connectMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: connectForm.submit()
            }
          }
        }

        // ---- key hints ----
        Row {
          visible: root.view !== "connect"
          anchors.right: parent.right
          topPadding: Style.space(12)
          spacing: Style.space(14)

          Repeater {
            model: root.view === "tracking" ? [["s", "keyStop"], ["o", "keyDashboard"]]
                 : root.view === "idle" ? (svc.companies.length > 1 ? [["↵", "keyStart"], ["1–9", "keyPick"], ["o", "keyDashboard"]] : [["↵", "keyStart"], ["o", "keyDashboard"]])
                 : [["r", "keyRetry"]]
            delegate: Row {
              required property var modelData
              spacing: Style.space(4)
              Text { textFormat: Text.PlainText; text: modelData[0]; color: root.bright; font.family: root.uiFont; font.pixelSize: Style.space(11); font.weight: Font.DemiBold }
              Text { textFormat: Text.PlainText; text: strings.t(modelData[1]); color: root.muted; font.family: root.uiFont; font.pixelSize: Style.space(11) }
            }
          }
        }
      }
    }
  }
}

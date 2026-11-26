import QtQuick
import QtQuick.Window
import QtQuick.Effects
import QtMultimedia

Window {
    id: win
    width: 1600; height: 900
    visible: true
    title: "Tide"
    color: "#000"
    visibility: backend.windowed ? Window.Windowed : Window.FullScreen

    // ───────────────────────── общие свойства ─────────────────────────
    readonly property real s: Math.min(width / 1920, height / 1080)
    property var cfg: backend.settings()
    property var users: backend.users()
    property int curUser: 0
    readonly property var me: users[Math.min(curUser, users.length - 1)] || ({ name: "Игрок", color: 0 })
    property var st: backend.stats()
    property var sysSt: ({ volume: 50, muted: false, sinks: [], sink: "", net: "—", netType: "", ip: "—", battery: -1, disks: [], pads: [] })
    property var sysInfo: []
    property var activity: []
    property string netResult: ""
    property date now: new Date()
    property real pulse: 0.6

    // stage: boot | press | users | welcome | home | library | settings
    property string stage: "boot"
    property var media: backend.mediaInfo()
    function refreshMedia() { media = backend.mediaInfo() }
    property bool musicDone: false     // мелодия играет один раз — после заставки
    MediaPlayer {
        id: usersMusic
        source: win.media.music
        audioOutput: AudioOutput { id: musicOut; volume: 0.8 }
    }
    NumberAnimation { id: musicFade; target: musicOut; property: "volume"; to: 0; duration: 1200
                      onFinished: usersMusic.stop() }
    onStageChanged: {
        if (stage === "users" && !musicDone && cfg.usersMusic && media.music) {
            musicDone = true
            musicFade.stop(); musicOut.volume = 0.8; usersMusic.play()
        } else if (stage !== "users" && stage !== "boot" && usersMusic.playbackState === MediaPlayer.PlayingState && !musicFade.running) {
            musicFade.start()
        }
    }
    // overlay: "" | menu | profile | trophies | notify | info | kb | launch
    property string overlay: ""

    readonly property var themes: ({
        blue:   { name: "Синий океан",   top: "#3f6fe2", bottom: "#1c3aa6", wave: "#b4d2ff" },
        night:  { name: "Ночь",          top: "#262b35", bottom: "#050608", wave: "#a8b8d0" },
        purple: { name: "Аметист",       top: "#4b2a8f", bottom: "#120726", wave: "#d5a8ff" },
        red:    { name: "Рубин",         top: "#8f1d2a", bottom: "#22050a", wave: "#ffb0a8" },
        green:  { name: "Изумруд",       top: "#126b4a", bottom: "#03190f", wave: "#a8ffd8" },
        gold:   { name: "Золото",        top: "#8a6416", bottom: "#1f1503", wave: "#ffe2a0" }
    })
    readonly property var themeKeys: ["blue", "night", "purple", "red", "green", "gold"]
    readonly property var theme: themes[cfg.theme] || themes.blue
    readonly property var avColors: ["#2f7fe0", "#e0504a", "#38b36a", "#e0a030", "#9b59d0", "#20b0b8", "#e06aa8", "#7a8a99"]
    readonly property var avNames: ["Синий", "Красный", "Зелёный", "Оранжевый", "Фиолетовый", "Бирюзовый", "Розовый", "Серый"]
    readonly property color txt2: "#c4d3ea"

    function rgba(c, a) { var q = Qt.color(c); return Qt.rgba(q.r, q.g, q.b, a) }
    function icon(n) { return "image://icon/" + encodeURIComponent(n || "application-x-executable") }
    function sym(n) { return "image://sym/" + encodeURIComponent(n) }
    property var accCache: ({})
    function accentOf(it) {
        if (!it) return "#123"
        if (it.special) return it.id === "__lib" ? "#3f74d8" : it.id === "__store" ? "#2b5fc4" : "#5b8ef0"
        if (accCache[it.icon] === undefined) accCache[it.icon] = backend.accent(it.icon)
        return accCache[it.icon]
    }
    function two(n) { return n < 10 ? "0" + n : "" + n }
    function clockText() {
        var h = now.getHours(), m = two(now.getMinutes())
        if (cfg.clock24) return h + ":" + m
        return ((h + 11) % 12 + 1) + ":" + m + (h < 12 ? " AM" : " PM")
    }
    function dateText() {
        var d = ["воскресенье", "понедельник", "вторник", "среда", "четверг", "пятница", "суббота"]
        var mo = ["января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября", "ноября", "декабря"]
        return d[now.getDay()] + ", " + now.getDate() + " " + mo[now.getMonth()]
    }
    property var ps4: backend.ps4Info()
    function refreshPs4() { ps4 = backend.ps4Info() }
    function setCfg(k, v) { backend.setSetting(k, v); cfg = backend.settings() }
    function refreshSys() { sysSt = backend.sysState() }

    // ───────────────────────── звуки ─────────────────────────
    // только свои звуки (media/select.*, scroll.*, login.*); без файла — тишина
    SoundEffect { id: sMove;   source: { win.media; return backend.sound("move") } volume: 0.4 }
    SoundEffect { id: sAccept; source: { win.media; return backend.sound("accept") } volume: 0.55 }
    SoundEffect { id: sLogin;  source: { win.media; return backend.sound("login") } volume: 0.6 }
    function play(n) {
        if (!cfg.sounds) return
        var m = { move: sMove, accept: sAccept, open: sAccept, back: sAccept, launch: sAccept, login: sLogin }
        if (m[n] && m[n].source.toString()) m[n].play()
    }

    Timer { interval: 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: win.now = new Date() }
    Timer { interval: 30000; running: win.visibility !== Window.Minimized; repeat: true; onTriggered: win.refreshSys() }
    // на экране выбора пользователя — чаще, чтобы только что включённый геймпад сразу появился
    Timer { interval: 3000; running: win.stage === "users"; repeat: true; onTriggered: win.refreshSys() }
    SequentialAnimation on pulse {
        loops: Animation.Infinite
        NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutSine }
        NumberAnimation { to: 0.45; duration: 900; easing.type: Easing.InOutSine }
    }

    // ───────────────────────── фон: волны ─────────────────────────
    Item {
        id: bg
        anchors.fill: parent
        opacity: win.stage === "boot" ? win.ramp(win.bootSec, 7.8, 9.4) : 1
        Behavior on opacity { enabled: win.stage !== "boot"; NumberAnimation { duration: 1400; easing.type: Easing.InOutQuad } }

        ShaderEffect {
            id: waves
            anchors.fill: parent
            property real time: 0
            property real aspect: width / Math.max(1, height)
            property color colTop: win.theme.top
            property color colBottom: win.theme.bottom
            property color colWave: win.theme.wave
            Behavior on colTop { ColorAnimation { duration: 800 } }
            Behavior on colBottom { ColorAnimation { duration: 800 } }
            Behavior on colWave { ColorAnimation { duration: 800 } }
            fragmentShader: "shaders/waves.frag.qsb"
            NumberAnimation on time {
                from: 0; to: 1000; duration: 1000000; loops: Animation.Infinite
                running: win.visibility !== Window.Minimized && win.visibility !== Window.Hidden
            }
        }
        // мерцающие частицы
        Repeater {
            model: 34
            Rectangle {
                id: dot
                property real sx: Math.random()
                property real sy: 0.35 + Math.random() * 0.6
                property real drift: 0.05 + Math.random() * 0.12
                property real ph: 0
                width: (2 + Math.random() * 5) * win.s; height: width; radius: width / 2
                color: win.theme.wave
                x: sx * win.width + Math.sin(ph * 6.28) * 30 * win.s
                y: (sy - ph * drift) * win.height
                opacity: Math.sin(ph * 3.14159) * (0.25 + Math.random() * 0.4)
                NumberAnimation on ph {
                    from: 0; to: 1; loops: Animation.Infinite
                    duration: 9000 + Math.random() * 12000
                    running: win.visibility !== Window.Minimized
                }
            }
        }
        // подсветка выбранной плитки (как фоновая обложка)
        Rectangle {
            anchors.fill: parent
            visible: win.stage === "home"
            opacity: 0.15
            gradient: Gradient {
                GradientStop { position: 0; color: win.rgba(win.homeAccent, 0.9) }
                GradientStop { position: 0.6; color: win.rgba(win.homeAccent, 0.0) }
            }
        }
        // фон выбранной игры PS4 (pic1.png), как на консоли
        Image {
            id: gameBg
            anchors.fill: parent
            property string want: win.stage === "home" && win.homeModel[win.homeIdx] && win.homeModel[win.homeIdx].bg
                                  ? "file://" + win.homeModel[win.homeIdx].bg : ""
            source: want
            fillMode: Image.PreserveAspectCrop
            asynchronous: true; cache: true
            sourceSize.width: 1920
            opacity: want !== "" && status === Image.Ready ? 0.55 : 0
            Behavior on opacity { NumberAnimation { duration: 600 } }
            visible: opacity > 0
        }
        Rectangle {
            anchors.fill: parent
            opacity: gameBg.opacity
            visible: opacity > 0
            gradient: Gradient {
                GradientStop { position: 0; color: "#a0000814" }
                GradientStop { position: 0.45; color: "#30000814" }
                GradientStop { position: 1; color: "#c0000814" }
            }
        }
    }
    property color homeAccent: accentOf(homeModel[homeIdx])
    Behavior on homeAccent { ColorAnimation { duration: 500 } }

    // ───────────────────────── компоненты ─────────────────────────
    component Avatar: Rectangle {
        property int ci: 0
        property string nm: ""
        property bool add: false
        radius: width / 2
        gradient: Gradient {
            GradientStop { position: 0; color: add ? "#4a5a78" : Qt.lighter(win.avColors[ci % 8], 1.3) }
            GradientStop { position: 1; color: add ? "#1a2233" : Qt.darker(win.avColors[ci % 8], 1.5) }
        }
        Text {
            anchors.centerIn: parent
            text: add ? "+" : (nm.length ? nm.charAt(0).toUpperCase() : "?")
            color: "white"
            font.pixelSize: parent.width * 0.46
            font.weight: Font.Light
        }
    }

    component Tile: Item {
        id: tl
        property var it
        property bool sel: false
        readonly property color acc: win.accentOf(it)
        Rectangle {
            id: tileBg
            anchors.fill: parent
            radius: 3 * win.s
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.lighter(tl.acc, 1.45) }
                GradientStop { position: 1; color: Qt.darker(tl.acc, 1.25) }
            }
            layer.enabled: tl.sel
            layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "#b0000000"; shadowBlur: 1.0; shadowVerticalOffset: 12 * win.s; blurMax: 48 }
        }
        Rectangle {  // блик
            anchors.fill: parent; radius: 3 * win.s
            gradient: Gradient {
                GradientStop { position: 0; color: "#30ffffff" }
                GradientStop { position: 0.5; color: "#00ffffff" }
            }
        }
        Ico {
            anchors.centerIn: parent
            visible: !!(tl.it && tl.it.special)
            width: parent.width * 0.4; height: width
            name: tl.it && tl.it.special ? tl.it.sym : ""
            stroke: 1.2
        }
        Image {  // обложка игры PS4 (icon0.png) на всю плитку
            anchors.fill: parent
            visible: !!(tl.it && tl.it.cover)
            source: tl.it && tl.it.cover ? "file://" + tl.it.cover : ""
            sourceSize: Qt.size(512, 512)
            fillMode: Image.PreserveAspectCrop
            smooth: true; mipmap: true; asynchronous: true
        }
        Image {
            anchors.centerIn: parent
            visible: !(tl.it && (tl.it.special || tl.it.cover))
            width: parent.width * 0.58; height: width
            sourceSize: Qt.size(256, 256)
            source: tl.it && !tl.it.special ? win.icon(tl.it.icon) : ""
            smooth: true; mipmap: true; asynchronous: true
        }
        Text {
            visible: !!(tl.it && tl.it.special)
            anchors { bottom: parent.bottom; bottomMargin: parent.height * 0.08; horizontalCenter: parent.horizontalCenter }
            text: tl.it ? tl.it.name : ""
            color: "white"; font.pixelSize: parent.height * 0.085
        }
        SelGlow {  // рамка выделения
            visible: tl.sel
            anchors.fill: parent; anchors.margins: -4 * win.s
            rad: 5 * win.s; fill: false
        }
    }

    // ── линейные иконки (рисуются в сетке 24×24) ──
    readonly property var icoMap: ({
        "notifications": "bell", "user-identity": "user", "games-achievements": "trophy", "view-grid": "grid",
        "configure": "toolbox", "system-shutdown": "power", "audio-volume-high": "sound",
        "preferences-desktop-color": "palette", "applications-games": "gamepad", "network-wireless": "wifi",
        "drive-harddisk": "storage", "system-suspend": "moon", "system-reboot": "restart", "view-refresh": "restart",
        "system-switch-user": "users", "system-log-out": "logout", "view-list-icons": "apps",
        "dialog-information": "info", "dialog-error": "info", "edit-delete": "trash", "media-playback-start": "play",
        "list-add": "plus", "edit-rename": "pencil", "edit-undo": "undo", "go-home": "home", "window-close": "close",
        "store": "bag", "download": "download", "folder": "folder", "folder-new": "folder", "input-gaming": "gamepad"
    })
    function drawIco(c, k) {
        var P = Math.PI
        c.beginPath()
        switch (k) {
        case "bell":
            c.moveTo(5.5, 17); c.lineTo(7, 15); c.lineTo(7, 10.5)
            c.bezierCurveTo(7, 7.3, 9.2, 5, 12, 5); c.bezierCurveTo(14.8, 5, 17, 7.3, 17, 10.5)
            c.lineTo(17, 15); c.lineTo(18.5, 17); c.closePath()
            c.moveTo(10, 19); c.bezierCurveTo(10.5, 20.6, 13.5, 20.6, 14, 19); break
        case "user":
            c.arc(12, 8.5, 3.6, 0, 2 * P)
            c.moveTo(4.5, 20.5); c.bezierCurveTo(4.5, 15.5, 8, 13.6, 12, 13.6); c.bezierCurveTo(16, 13.6, 19.5, 15.5, 19.5, 20.5); break
        case "users":
            c.arc(9, 8.5, 3.1, 0, 2 * P)
            c.moveTo(2.8, 19.5); c.bezierCurveTo(2.8, 15.2, 5.6, 13.4, 9, 13.4); c.bezierCurveTo(12.4, 13.4, 15.2, 15.2, 15.2, 19.5)
            c.moveTo(18.4, 8.2); c.arc(16, 8.2, 2.4, 0, 2 * P)
            c.moveTo(16.8, 12.6); c.bezierCurveTo(19.5, 13, 21.4, 14.8, 21.4, 18.2); break
        case "trophy":
            c.moveTo(7.5, 4); c.lineTo(16.5, 4); c.lineTo(16.5, 8.5)
            c.bezierCurveTo(16.5, 11.8, 14.5, 13.8, 12, 13.8); c.bezierCurveTo(9.5, 13.8, 7.5, 11.8, 7.5, 8.5); c.closePath()
            c.moveTo(7.5, 5.8); c.bezierCurveTo(3.6, 5.8, 3.8, 10.8, 8, 10.8)
            c.moveTo(16.5, 5.8); c.bezierCurveTo(20.4, 5.8, 20.2, 10.8, 16, 10.8)
            c.moveTo(12, 13.8); c.lineTo(12, 17.2)
            c.rect(8, 17.2, 8, 2.8); break
        case "grid":
            for (var i = 0; i < 3; i++) for (var j = 0; j < 3; j++) c.rect(3.8 + i * 6, 3.8 + j * 6, 4.4, 4.4)
            break
        case "apps":
            c.rect(4, 4, 6.5, 6.5); c.rect(13.5, 4, 6.5, 6.5); c.rect(4, 13.5, 6.5, 6.5); c.rect(13.5, 13.5, 6.5, 6.5); break
        case "toolbox":
            c.rect(3.5, 8.5, 17, 11)
            c.moveTo(9, 8.5); c.lineTo(9, 5.5); c.lineTo(15, 5.5); c.lineTo(15, 8.5)
            c.moveTo(3.5, 13); c.lineTo(10.5, 13); c.moveTo(13.5, 13); c.lineTo(20.5, 13)
            c.rect(10.5, 11.5, 3, 3.5); break
        case "power":
            c.arc(12, 13, 7, -P / 2 + 0.65, 3 * P / 2 - 0.65)
            c.moveTo(12, 3.5); c.lineTo(12, 11.5); break
        case "sound":
            c.moveTo(3.5, 9.5); c.lineTo(7, 9.5); c.lineTo(11, 5.8); c.lineTo(11, 18.2); c.lineTo(7, 14.5); c.lineTo(3.5, 14.5); c.closePath()
            c.moveTo(14.2, 9); c.arc(11.5, 12, 4, -0.75, 0.75)
            c.moveTo(16.4, 6.5); c.arc(11.5, 12, 7.3, -0.8, 0.8); break
        case "palette":
            c.moveTo(12, 3.8); c.bezierCurveTo(6.8, 3.8, 3.8, 7.6, 3.8, 12); c.bezierCurveTo(3.8, 16.6, 7.4, 20.2, 12, 20.2)
            c.bezierCurveTo(13.6, 20.2, 13.8, 18.6, 13, 17.6); c.bezierCurveTo(12.2, 16.4, 13, 15, 14.6, 15)
            c.lineTo(16.6, 15); c.bezierCurveTo(18.8, 15, 20.2, 13.6, 20.2, 11.4); c.bezierCurveTo(20.2, 7, 16.6, 3.8, 12, 3.8)
            c.moveTo(8.9, 11); c.arc(8, 11, 0.9, 0, 2 * P); c.moveTo(11.4, 7.8); c.arc(10.5, 7.8, 0.9, 0, 2 * P)
            c.moveTo(15.4, 8.2); c.arc(14.5, 8.2, 0.9, 0, 2 * P); break
        case "gamepad":
            c.moveTo(7, 7.5); c.lineTo(17, 7.5); c.bezierCurveTo(20, 7.5, 21.8, 14.5, 21, 17)
            c.bezierCurveTo(20.2, 19.2, 17.8, 18.6, 16.2, 15.6); c.lineTo(7.8, 15.6)
            c.bezierCurveTo(6.2, 18.6, 3.8, 19.2, 3, 17); c.bezierCurveTo(2.2, 14.5, 4, 7.5, 7, 7.5); c.closePath()
            c.moveTo(6, 11.3); c.lineTo(10, 11.3); c.moveTo(8, 9.3); c.lineTo(8, 13.3)
            c.moveTo(16.6, 10.2); c.arc(16, 10.2, 0.6, 0, 2 * P); c.moveTo(18.4, 12.2); c.arc(17.8, 12.2, 0.6, 0, 2 * P); break
        case "wifi":
            c.moveTo(4.2, 10.2); c.arc(12, 18.5, 11, -P * 0.78, -P * 0.22)
            c.moveTo(7.1, 13.2); c.arc(12, 18.5, 7, -P * 0.76, -P * 0.24)
            c.moveTo(9.7, 15.9); c.arc(12, 18.5, 3.2, -P * 0.74, -P * 0.26)
            c.moveTo(12.8, 19); c.arc(12, 19, 0.8, 0, 2 * P); break
        case "storage":
            c.rect(3.5, 7, 17, 10); c.moveTo(3.5, 13.5); c.lineTo(20.5, 13.5)
            c.moveTo(17.6, 15.3); c.arc(17, 15.3, 0.6, 0, 2 * P); break
        case "moon":
            c.moveTo(14, 4.2); c.bezierCurveTo(8, 4.8, 5.6, 10.4, 7.8, 14.8); c.bezierCurveTo(10, 19, 15.6, 20, 19.4, 16.4)
            c.bezierCurveTo(14.4, 16.6, 10.6, 12.8, 11.2, 8.4); c.bezierCurveTo(11.5, 6.6, 12.5, 5.2, 14, 4.2); break
        case "restart":
            c.arc(12, 12.5, 7, -P * 0.4, P * 1.42)
            c.moveTo(14.8, 2.8); c.lineTo(17.2, 6.4); c.lineTo(13, 7.4); break
        case "undo":
            c.moveTo(8, 9.5); c.lineTo(15, 9.5); c.bezierCurveTo(18.5, 9.5, 20, 12, 20, 14.2); c.bezierCurveTo(20, 16.6, 18.4, 19, 15, 19); c.lineTo(9, 19)
            c.moveTo(11, 5.8); c.lineTo(7.2, 9.5); c.lineTo(11, 13.2); break
        case "logout":
            c.moveTo(13, 4.5); c.lineTo(5, 4.5); c.lineTo(5, 19.5); c.lineTo(13, 19.5)
            c.moveTo(9.5, 12); c.lineTo(20, 12); c.moveTo(16.5, 8.5); c.lineTo(20, 12); c.lineTo(16.5, 15.5); break
        case "info":
            c.arc(12, 12, 8.5, 0, 2 * P); c.moveTo(12, 10.8); c.lineTo(12, 16.5)
            c.moveTo(12.8, 7.8); c.arc(12, 7.8, 0.8, 0, 2 * P); break
        case "trash":
            c.moveTo(4.5, 7); c.lineTo(19.5, 7); c.moveTo(9.5, 7); c.lineTo(9.5, 4.5); c.lineTo(14.5, 4.5); c.lineTo(14.5, 7)
            c.moveTo(6.5, 7); c.lineTo(7.5, 20); c.lineTo(16.5, 20); c.lineTo(17.5, 7)
            c.moveTo(10.2, 10.5); c.lineTo(10.4, 16.5); c.moveTo(13.8, 10.5); c.lineTo(13.6, 16.5); break
        case "play":
            c.moveTo(7.5, 4.8); c.lineTo(19, 12); c.lineTo(7.5, 19.2); c.closePath(); c.fill(); break
        case "plus":
            c.moveTo(12, 4.5); c.lineTo(12, 19.5); c.moveTo(4.5, 12); c.lineTo(19.5, 12); break
        case "pencil":
            c.moveTo(4.5, 19.5); c.lineTo(5.5, 15.2); c.lineTo(15.4, 5.3); c.lineTo(18.7, 8.6); c.lineTo(8.8, 18.5); c.closePath()
            c.moveTo(13.2, 7.5); c.lineTo(16.5, 10.8); break
        case "home":
            c.moveTo(3.5, 12); c.lineTo(12, 4.2); c.lineTo(20.5, 12)
            c.moveTo(6.2, 9.8); c.lineTo(6.2, 19.5); c.lineTo(10, 19.5); c.lineTo(10, 14.5); c.lineTo(14, 14.5); c.lineTo(14, 19.5); c.lineTo(17.8, 19.5); c.lineTo(17.8, 9.8); break
        case "close":
            c.moveTo(6, 6); c.lineTo(18, 18); c.moveTo(18, 6); c.lineTo(6, 18); break
        case "bag":
            c.moveTo(5, 8); c.lineTo(19, 8); c.lineTo(18, 20); c.lineTo(6, 20); c.closePath()
            c.moveTo(9, 10.5); c.lineTo(9, 7); c.bezierCurveTo(9, 3.6, 15, 3.6, 15, 7); c.lineTo(15, 10.5); break
        case "download":
            c.moveTo(12, 4); c.lineTo(12, 15); c.moveTo(7.5, 10.5); c.lineTo(12, 15); c.lineTo(16.5, 10.5)
            c.moveTo(5, 16.5); c.lineTo(5, 19.5); c.lineTo(19, 19.5); c.lineTo(19, 16.5); break
        case "folder":
            c.moveTo(3.5, 6.5); c.lineTo(9.5, 6.5); c.lineTo(11.5, 8.5); c.lineTo(20.5, 8.5); c.lineTo(20.5, 18.5); c.lineTo(3.5, 18.5); c.closePath(); break
        }
        c.stroke()
    }
    component Ico: Canvas {
        id: ico
        property string name: ""
        property color tint: "white"
        property real stroke: 1.5
        readonly property string kind: win.icoMap[name] || ""
        antialiasing: true
        onKindChanged: requestPaint()
        onTintChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            var c = getContext("2d"); c.reset()
            if (!kind) return
            var k = Math.min(width, height) / 24
            c.save(); c.scale(k, k)
            c.strokeStyle = tint; c.fillStyle = tint
            c.lineWidth = stroke; c.lineCap = "round"; c.lineJoin = "round"
            win.drawIco(c, kind)
            c.restore()
        }
        Image {  // запасной вариант для неизвестных имён
            anchors.fill: parent
            visible: !ico.kind && ico.name !== ""
            sourceSize: Qt.size(96, 96)
            source: !ico.kind && ico.name !== "" ? win.sym(ico.name) : ""
        }
    }

    // ── значки кнопок геймпада ──
    readonly property var padColors: ({ cross: "#7fb0ff", circle: "#ff6f73", triangle: "#3fd8a8", square: "#f08ee0" })
    component PadBtn: Canvas {
        property string kind: "cross"
        width: 30 * win.s; height: width
        antialiasing: true
        onKindChanged: requestPaint()
        onWidthChanged: requestPaint()
        onPaint: {
            var c = getContext("2d"); c.reset()
            var w = width, h = height, P = Math.PI
            c.lineWidth = Math.max(2, w * 0.1); c.lineCap = "round"; c.lineJoin = "round"
            c.strokeStyle = win.padColors[kind] || "white"
            c.beginPath()
            if (kind === "cross") { c.moveTo(w * .2, h * .2); c.lineTo(w * .8, h * .8); c.moveTo(w * .8, h * .2); c.lineTo(w * .2, h * .8) }
            else if (kind === "circle") c.arc(w / 2, h / 2, w * .34, 0, 2 * P)
            else if (kind === "triangle") { c.moveTo(w / 2, h * .16); c.lineTo(w * .86, h * .78); c.lineTo(w * .14, h * .78); c.closePath() }
            else if (kind === "square") c.rect(w * .2, h * .2, w * .6, h * .6)
            else if (kind === "options") {
                c.strokeStyle = "white"; c.lineWidth = Math.max(1.5, w * .07)
                c.moveTo(w * .3, h * .1); c.lineTo(w * .7, h * .1); c.arcTo(w * .9, h * .1, w * .9, h * .3, w * .2)
                c.lineTo(w * .9, h * .7); c.arcTo(w * .9, h * .9, w * .7, h * .9, w * .2); c.lineTo(w * .3, h * .9)
                c.arcTo(w * .1, h * .9, w * .1, h * .7, w * .2); c.lineTo(w * .1, h * .3); c.arcTo(w * .1, h * .1, w * .3, h * .1, w * .2)
                c.moveTo(w * .32, h * .36); c.lineTo(w * .68, h * .36); c.moveTo(w * .32, h * .5); c.lineTo(w * .68, h * .5); c.moveTo(w * .32, h * .64); c.lineTo(w * .68, h * .64)
            }
            else if (kind === "home") {
                c.strokeStyle = "white"; c.lineWidth = Math.max(1.5, w * .07)
                c.arc(w / 2, h / 2, w * .42, 0, 2 * P)
                c.moveTo(w * .28, h * .52); c.lineTo(w * .5, h * .3); c.lineTo(w * .72, h * .52)
                c.moveTo(w * .35, h * .46); c.lineTo(w * .35, h * .7); c.lineTo(w * .65, h * .7); c.lineTo(w * .65, h * .46)
            }
            else if (kind === "lr") {
                c.fillStyle = "white"
                c.moveTo(w * .08, h / 2); c.lineTo(w * .38, h * .25); c.lineTo(w * .38, h * .75); c.closePath()
                c.moveTo(w * .92, h / 2); c.lineTo(w * .62, h * .25); c.lineTo(w * .62, h * .75); c.closePath(); c.fill()
            }
            c.stroke()
        }
    }

    component Hint: Row {
        property string btn: "cross"
        property string label: ""
        spacing: 10 * win.s
        PadBtn { kind: btn; anchors.verticalCenter: parent.verticalCenter }
        Text { text: label; color: "white"; font.pixelSize: 24 * win.s; anchors.verticalCenter: parent.verticalCenter }
    }

    // мягкая светящаяся рамка выделения
    component SelGlow: Item {
        property real rad: 4 * win.s
        property bool fill: true
        property color glow: "#6fd6ff"
        Rectangle {
            anchors.fill: parent
            radius: parent.rad
            visible: parent.fill
            gradient: Gradient {
                GradientStop { position: 0; color: "#3cd8eeff" }
                GradientStop { position: 1; color: "#18d8eeff" }
            }
        }
        Rectangle {
            id: glowLine
            anchors.fill: parent
            radius: parent.rad
            color: "transparent"
            border.color: "#dff6ff"; border.width: 2.5 * win.s
            opacity: 0.75 + win.pulse * 0.25
            layer.enabled: true
            layer.effect: MultiEffect { shadowEnabled: true; shadowColor: glowLine.parent.glow; shadowBlur: 1.0; shadowScale: 1.02; shadowOpacity: 0.7 + win.pulse * 0.3; blurMax: 40 }
        }
    }

    component Glass: Rectangle {
        color: "#d0081428"
        border.color: "#40ffffff"; border.width: 1
    }

    // ───────────────────────── загрузка ─────────────────────────
    // Хореография: чёрный → эмблема Tide → чёрный → тёмно-синий экран с предупреждением → волны → выбор пользователя
    property real bootSec: 0
    readonly property real bootLen: 9.6
    function ramp(t, a, b) { return Math.max(0, Math.min(1, (t - a) / (b - a))) }
    function bootStart() {
        bootSec = 0
        bootAnim.start()
    }
    function bootFinish() {
        bootAnim.stop()
        stage = "users"; bootSec = bootLen
    }

    // Логотипы меню — те, что выбраны (logo_* в настройках, файлы из media/logos); без файла — стандартный знак/значок.
    function logoUrl(key) { return backend.mediaUrl("logos", cfg[key] || "") }
    component SlotLogo: Item {
        id: sl
        property string slot: ""          // ключ настройки, например "logo_store"
        property string icon: ""          // стандартный значок; пусто — знак Tide
        property bool brandText: false    // у знака Tide показать надпись «T I D E»
        property real textScale: 0.66
        property real maxW: 600 * win.s
        readonly property string src: win.logoUrl(slot)
        height: 52 * win.s
        width: src ? Math.min(maxW, img.implicitWidth * height / Math.max(1, img.implicitHeight))
                   : icon ? height : defRow.width
        Image { id: img; visible: !!sl.src; source: sl.src; anchors.fill: parent; fillMode: Image.PreserveAspectFit
                sourceSize.height: 256; smooth: true; mipmap: true }
        Ico { visible: !sl.src && !!sl.icon; anchors.fill: parent; name: sl.icon }
        Row {
            id: defRow
            visible: !sl.src && !sl.icon
            spacing: 18 * win.s; height: parent.height
            TideMark { width: sl.height * 1.4; height: sl.height; anchors.verticalCenter: parent.verticalCenter }
            Text { visible: sl.brandText; text: "T I D E"; color: "white"; font.pixelSize: sl.height * sl.textScale; font.weight: Font.Light
                   anchors.verticalCenter: parent.verticalCenter }
        }
    }

    component TideMark: Canvas {  // эмблема лаунчера: три волны
        property color tint: "white"
        onTintChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            var c = getContext("2d"); c.reset()
            var w = width, h = height, lw = Math.max(2, h * 0.11)
            c.strokeStyle = tint; c.lineWidth = lw; c.lineCap = "round"; c.lineJoin = "round"
            for (var k = 0; k < 3; k++) {
                var y0 = h * (0.26 + k * 0.24), amp = h * 0.09, len = w * (1 - k * 0.16), x0 = (w - len) / 2
                c.globalAlpha = 1 - k * 0.22
                c.beginPath()
                for (var i = 0; i <= 48; i++) {
                    var x = x0 + len * i / 48
                    var y = y0 + Math.sin(i / 48 * Math.PI * 2 + k * 0.9) * amp
                    if (i === 0) c.moveTo(x, y); else c.lineTo(x, y)
                }
                c.stroke()
            }
        }
    }

    Item {
        id: bootScreen
        anchors.fill: parent
        visible: win.stage === "boot"
        readonly property real t: win.bootSec
        // чёрная подложка, потом тёмно-синий экран предупреждения, потом всё растворяется в волнах фона
        Rectangle { anchors.fill: parent; color: "black"; opacity: 1 - win.ramp(bootScreen.t, 7.8, 9.4) }
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0; color: "#020a1c" }
                GradientStop { position: 1; color: "#06163a" }
            }
            opacity: win.ramp(bootScreen.t, 4.8, 5.6) * (1 - win.ramp(bootScreen.t, 7.8, 9.4))
        }
        // эмблема: знак Tide или свой логотип из media/logos
        Item {
            readonly property string logo: win.logoUrl("logo_boot")
            anchors.centerIn: parent
            width: logo ? 520 * win.s : 170 * win.s; height: logo ? 300 * win.s : 120 * win.s
            opacity: win.ramp(bootScreen.t, 0.5, 1.4) * (1 - win.ramp(bootScreen.t, 3.6, 4.5))
            scale: 0.97 + 0.03 * win.ramp(bootScreen.t, 0.5, 4.5)
            TideMark { anchors.fill: parent; visible: !parent.logo }
            Image { anchors.fill: parent; visible: !!parent.logo; source: parent.logo; fillMode: Image.PreserveAspectFit
                    sourceSize.height: 600; smooth: true; mipmap: true }
        }
        // предупреждение
        Text {
            anchors.centerIn: parent
            text: "Важная информация о здоровье и безопасности — в меню «Настройки»."
            color: "#c8d2e6"; font.pixelSize: 24 * win.s; font.weight: Font.Light
            opacity: win.ramp(bootScreen.t, 5.2, 5.9) * (1 - win.ramp(bootScreen.t, 7.9, 8.6))
        }
        NumberAnimation {
            id: bootAnim
            target: win; property: "bootSec"
            from: 0; to: win.bootLen; duration: win.bootLen * 1000
            onFinished: win.stage = "users"
        }
    }

    // ───────────────────────── "нажмите кнопку" ─────────────────────────
    Item {
        anchors.fill: parent
        opacity: win.stage === "press" ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 600 } }
        Row {
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: parent.height * 0.47 }
            spacing: 14 * win.s
            opacity: 0.55 + win.pulse * 0.45
            Text { text: "Нажмите"; color: "white"; font.pixelSize: 40 * win.s; font.weight: Font.Light; anchors.verticalCenter: parent.verticalCenter }
            PadBtn { kind: "home"; width: 46 * win.s; anchors.verticalCenter: parent.verticalCenter }
            Text { text: "на контроллере, чтобы начать (или Enter)"; color: "white"; font.pixelSize: 40 * win.s; font.weight: Font.Light; anchors.verticalCenter: parent.verticalCenter }
        }
    }

    // ───────────────────────── выбор пользователя ─────────────────────────
    property int userIdx: 0
    property real loginT: 0          // 0..1 — анимация входа
    component SqAvatar: Rectangle {
        id: av
        property int ci: 0
        property string nm: ""
        property bool add: false
        readonly property color face: win.avColors[ci % 8]
        radius: width * 0.18
        color: add ? "#30ffffff" : "white"
        border.color: add ? "#70ffffff" : "transparent"; border.width: add ? 2 * win.s : 0
        Canvas {  // лицо: два круглых глаза-точки и толстая улыбка
            visible: !av.add
            anchors.fill: parent
            // тёмный оттенок цвета пользователя (для синего — почти тёмно-синий)
            property color col: Qt.darker(av.face, 2.6)
            onColChanged: requestPaint()
            onWidthChanged: requestPaint()
            onPaint: {
                var c = getContext("2d"); c.reset()
                var w = width, h = height
                c.fillStyle = col; c.strokeStyle = col
                var er = w * 0.072
                c.beginPath(); c.arc(w * 0.30, h * 0.40, er, 0, Math.PI * 2); c.fill()
                c.beginPath(); c.arc(w * 0.70, h * 0.40, er, 0, Math.PI * 2); c.fill()
                c.lineWidth = w * 0.105; c.lineCap = "round"
                c.beginPath(); c.arc(w * 0.5, h * 0.45, w * 0.23, Math.PI * 0.22, Math.PI * 0.78, false); c.stroke()
            }
        }
        Ico { visible: av.add; anchors.centerIn: parent; width: parent.width * 0.36; height: width; name: "list-add"; stroke: 1.2 }
    }
    Item {
        id: usersScreen
        anchors.fill: parent
        opacity: win.stage === "users" ? 1 : win.stage === "welcome" ? 1 - Math.max(0, win.loginT - 0.7) / 0.3 : 0
        visible: opacity > 0
        Behavior on opacity { enabled: win.stage !== "welcome"; NumberAnimation { duration: 450 } }

        readonly property real tw: 252 * win.s      // плитка
        readonly property real th: 364 * win.s
        readonly property real gap: 34 * win.s
        readonly property int n: win.users.length + 1
        readonly property real ty: 452 * win.s
        readonly property real rowW: n * tw + (n - 1) * gap
        // при большом числе пользователей ряд сдвигается за выбранной плиткой
        property real startX: rowW <= width - 200 * win.s ? (width - rowW) / 2
                                       : width / 2 - (win.userIdx * (tw + gap) + tw / 2)
        Behavior on startX { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

        SlotLogo {  // логотип слева вверху, проявляется после заставки
            slot: "logo_users"; brandText: true; textScale: 0.82
            x: 110 * win.s; y: 64 * win.s; height: 104 * win.s; maxW: 700 * win.s
            opacity: win.stage === "users" ? 1 : 0
            Behavior on opacity { SequentialAnimation { PauseAnimation { duration: 250 } NumberAnimation { duration: 700 } } }
        }
        Column {  // текстовый блок над плитками
            id: greet
            anchors.horizontalCenter: parent.horizontalCenter
            y: 262 * win.s; spacing: 8 * win.s
            opacity: win.stage === "users" ? 1 : 1 - Math.min(1, win.loginT * 3)
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "С возвращением в Tide"
                color: "white"; font.pixelSize: 42 * win.s; font.weight: Font.Light
                bottomPadding: 12 * win.s
            }
            Row {
                spacing: 14 * win.s
                Ico { width: 36 * win.s; height: width; name: "input-gaming"; anchors.verticalCenter: parent.verticalCenter }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: win.sysSt.pads && win.sysSt.pads.length ? win.sysSt.pads[0] + " — контроллер подключён"
                          + (win.sysSt.padBattery >= 0 ? " (заряд " + win.sysSt.padBattery + "%)." : ".")
                                                                  : "Контроллер не найден — можно использовать клавиатуру."
                    color: "white"; font.pixelSize: 32 * win.s; font.weight: Font.Light
                }
            }
            Text {
                text: "Кто использует этот контроллер?"
                color: "white"; font.pixelSize: 32 * win.s; font.weight: Font.Light
            }
        }
        Repeater {
            model: usersScreen.n
            Item {
                id: ub
                readonly property bool isAdd: index === win.users.length
                readonly property bool cur: index === win.userIdx
                readonly property bool welcome: win.stage === "welcome"
                readonly property real d: index - win.userIdx
                readonly property var u: isAdd ? null : win.users[index]
                width: usersScreen.tw; height: usersScreen.th
                x: usersScreen.startX + index * (usersScreen.tw + usersScreen.gap)
                   + (welcome && !cur ? (d < 0 ? -1 : 1) * win.loginT * 500 * win.s : 0)
                y: usersScreen.ty
                opacity: welcome && !cur ? 1 - Math.min(1, win.loginT * 2.5) : 1
                scale: welcome && cur ? 1 + Math.sin(Math.min(1, win.loginT * 1.6) * Math.PI) * 0.06 : (cur ? 1.035 : 1)
                Behavior on scale { enabled: !ub.welcome; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                z: cur ? 1 : 0

                Rectangle {  // полупрозрачная плитка
                    anchors.fill: parent
                    color: ub.cur ? "#3a6fc4ff" : "#2a5aa8f0"
                    Behavior on color { ColorAnimation { duration: 180 } }
                }
                Rectangle {  // рамка выбранной плитки
                    visible: ub.cur
                    anchors.fill: parent; anchors.margins: -4 * win.s
                    color: "transparent"; border.color: "white"; border.width: 4 * win.s
                }
                // «Новый пользователь»: крупный плюс
                Ico {
                    visible: ub.isAdd
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: parent.height * 0.2; width: parent.width * 0.4; height: width
                    name: "list-add"; stroke: 3.2
                }
                // аватар пользователя: квадрат со скруглением
                SqAvatar {
                    visible: !ub.isAdd
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 36 * win.s; width: parent.width * 0.72; height: width
                    radius: width * 0.16
                    ci: ub.u ? ub.u.color : 0
                    nm: ub.u ? ub.u.name : ""
                    layer.enabled: true
                    layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "#70000000"; shadowBlur: 0.6; shadowVerticalOffset: 6 * win.s; blurMax: 24 }
                }
                Text {
                    x: ub.isAdd ? 0 : 24 * win.s; y: parent.height * 0.73
                    width: ub.isAdd ? parent.width : parent.width - 48 * win.s
                    horizontalAlignment: ub.isAdd ? Text.AlignHCenter : Text.AlignLeft
                    text: ub.isAdd ? "Новый пользователь" : ub.u.name
                    color: "white"; font.pixelSize: 28 * win.s; font.weight: Font.DemiBold
                    wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: { if (win.userIdx === index) win.handle("accept"); else { win.userIdx = index; win.play("move") } }
                }
            }
        }
        // нижняя панель с подсказками
        Rectangle {
            visible: win.stage === "users"
            x: 0; width: parent.width; height: 1; y: parent.height - 136 * win.s
            color: "#50ffffff"
        }
        Row {
            visible: win.stage === "users"
            x: 110 * win.s; y: parent.height - 136 * win.s + 34 * win.s
            spacing: 50 * win.s
            Hint { btn: "cross"; label: win.userIdx < win.users.length ? "Войти" : "Создать" }
            Hint { btn: "triangle"; label: "Удалить"; visible: win.userIdx < win.users.length && win.users.length > 1 }
        }
    }
    NumberAnimation {
        id: loginAnim; target: win; property: "loginT"; from: 0; to: 1; duration: 1300; easing.type: Easing.InOutQuad
        onFinished: win.enterHome()
    }

    // ───────────────────────── главный экран ─────────────────────────
    property var homeModel: []
    property int homeIdx: 1
    property string zone: "row"      // func | row | info
    property int funcIdx: 0
    property int infoIdx: 0
    property real homeIntro: 0
    readonly property var funcItems: [
        { key: "notify",   label: "Уведомления", sym: "notifications" },
        { key: "profile",  label: "Профиль",     sym: "user-identity" },
        { key: "trophies", label: "Достижения",  sym: "games-achievements" },
        { key: "store",    label: "Магазин",     sym: "store" },
        { key: "library",  label: "Библиотека",  sym: "view-grid" },
        { key: "settings", label: "Настройки",   sym: "configure" },
        { key: "power",    label: "Питание",     sym: "system-shutdown" }
    ]
    readonly property var curItem: homeModel[homeIdx]
    readonly property var cards: cardsFor(curItem, activity, st)

    // ступенчатое появление элементов при входе: k — порядковый номер
    function intro(k) {
        var t = Math.max(0, Math.min(1, homeIntro * 1.9 - k * 0.09))
        return 1 - Math.pow(1 - t, 3)
    }
    function refreshHome() {
        var m = [{ id: "__new", name: "Что нового", special: true, sym: "notifications" }]
        m = m.concat(backend.homeItems())
        m.push({ id: "__store", name: "Магазин", special: true, sym: "store" })
        m.push({ id: "__lib", name: "Библиотека", special: true, sym: "view-grid" })
        homeModel = m
        activity = backend.activity()
        refreshAch()
        st = backend.stats()
        if (homeIdx >= m.length) homeIdx = m.length - 1
    }
    function cardsFor(it, act, stats) {
        if (!it) return []
        var who = me.name
        if (it.id === "__new") {
            if (!act.length) return [{ title: "Пока здесь пусто. Запустите игру или приложение.", sym: "notifications", act: "" }]
            return act.slice(0, 9).map(function (x) {
                return { who: who, title: (x.isGame ? "играл(а) в " : "запускал(а) ") + x.name.toUpperCase() + ". " + x.when,
                         icon: x.icon, act: "launch:" + x.id }
            })
        }
        if (it.id === "__lib") return [
            { title: "Игры — " + stats.games, sym: "applications-games", act: "lib:0" },
            { title: "Приложения — " + stats.apps, sym: "view-list-icons", act: "lib:1" },
            { title: "Всё содержимое — " + (stats.games + stats.apps), sym: "view-grid", act: "lib:2" }
        ]
        return [
            { who: who, title: it.count ? ("запускал(а) " + it.count + " раз, всего " + it.timeText) : "ещё не запускал(а) это", icon: it.icon, act: "info" },
            { title: it.comment || "Описание отсутствует.", sym: "dialog-information", act: "info" },
            { title: it.isGame ? "Перенести в приложения" : "Отметить как игру", sym: "applications-games", act: "togglegame" },
            it.pinned && !it.isGame ? { title: "Убрать с главного экрана", sym: "edit-delete", act: "unpin" }
                                    : { title: "Скрыть с главного экрана", sym: "edit-delete", act: "hide" }
        ]
    }

    Item {
        id: homeScreen
        anchors.fill: parent
        opacity: win.stage === "home" ? 1 : 0
        visible: opacity > 0
        scale: win.stage === "home" ? 1 : 1.04
        Behavior on opacity { NumberAnimation { duration: 400 } }
        Behavior on scale { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }

        readonly property real baseX: 300 * win.s
        readonly property real small: 226 * win.s
        readonly property real big: 376 * win.s
        readonly property real strip: 68 * win.s
        readonly property real gap: 4 * win.s
        readonly property real cardX: 196 * win.s
        readonly property real cardW: 498 * win.s
        readonly property real cardH: 172 * win.s
        readonly property real cardGap: 28 * win.s
        readonly property int infoRow: Math.floor(win.infoIdx / 3)
        property real rowTop: (win.zone === "func" ? 360 : win.zone === "info" ? 150 - Math.max(0, infoRow - 1) * 200 - 330 : 170) * win.s
        Behavior on rowTop { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
        readonly property string lastNote: win.activity.length ? ((win.activity[0].isGame ? "Вы играли в " : "Вы запускали ") + win.activity[0].name) : "Нет новых уведомлений"
        readonly property int trophyN: win.achTotalGot

        // ── верхняя строка (как на консоли) ──
        Item {
            id: topBar
            x: 0; y: (win.zone === "info" ? -110 : 0) * win.s - (1 - win.intro(0)) * 110 * win.s
            opacity: win.intro(0)
            width: parent.width; height: 110 * win.s
            Behavior on y { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
            SlotLogo { x: 60 * win.s; y: 50 * win.s; slot: "logo_home"; icon: "view-grid" }
            Row {
                x: 190 * win.s; anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: 22 * win.s
                spacing: 16 * win.s
                Item {
                    width: 46 * win.s; height: width
                    anchors.verticalCenter: parent.verticalCenter
                    Rectangle { anchors.fill: parent; radius: width / 2; color: "white" }
                    Text { anchors.centerIn: parent; text: "i"; color: "#2c5ac8"; font.pixelSize: 32 * win.s; font.bold: true }
                    Text {
                        visible: win.activity.length > 0
                        anchors { left: parent.right; bottom: parent.top; leftMargin: -14 * win.s; bottomMargin: -10 * win.s }
                        text: Math.min(win.activity.length, 99); color: "white"; font.pixelSize: 20 * win.s
                    }
                }
                Text { text: homeScreen.lastNote; color: "white"; font.pixelSize: 30 * win.s; anchors.verticalCenter: parent.verticalCenter }
            }
            Row {
                x: parent.width * 0.5; anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: 22 * win.s
                spacing: 30 * win.s
                Ico { width: 52 * win.s; height: width; name: "system-switch-user"; anchors.verticalCenter: parent.verticalCenter }
                Row {
                    spacing: 18 * win.s
                    anchors.verticalCenter: parent.verticalCenter
                    Rectangle {
                        width: 50 * win.s; height: width; radius: 8 * win.s
                        color: "white"
                        anchors.verticalCenter: parent.verticalCenter
                        Text { anchors.centerIn: parent; text: win.me.name.charAt(0).toUpperCase(); color: win.avColors[win.me.color % 8]; font.pixelSize: 32 * win.s; font.weight: Font.DemiBold }
                    }
                    Text { text: win.me.name; color: "white"; font.pixelSize: 30 * win.s; anchors.verticalCenter: parent.verticalCenter }
                }
            }
            Row {
                anchors { right: parent.right; rightMargin: 64 * win.s; verticalCenter: parent.verticalCenter; verticalCenterOffset: 22 * win.s }
                spacing: 26 * win.s
                Row {
                    spacing: 10 * win.s
                    anchors.verticalCenter: parent.verticalCenter
                    Ico { width: 50 * win.s; height: width; name: "games-achievements"; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: "★"; color: "#f0c040"; font.pixelSize: 22 * win.s; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: homeScreen.trophyN; color: "white"; font.pixelSize: 28 * win.s; anchors.verticalCenter: parent.verticalCenter }
                }
                Text {
                    visible: win.sysSt.battery >= 0
                    text: win.sysSt.battery + "%"; color: "white"; font.pixelSize: 26 * win.s
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text { text: win.clockText(); color: "white"; font.pixelSize: 32 * win.s; anchors.verticalCenter: parent.verticalCenter }
            }
        }

        // ── функциональная область (появляется по «вверх») ──
        Item {
            id: funcBar
            x: homeScreen.baseX
            // въезжает сверху вниз вместе с уходящей вниз лентой
            y: (win.zone === "func" ? 150 : 104) * win.s
            opacity: win.zone === "func" ? 1 : 0
            visible: opacity > 0.01
            width: parent.width; height: 160 * win.s
            Behavior on y { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
            Row {
                spacing: 40 * win.s
                Repeater {
                    model: win.funcItems
                    Item {
                        readonly property bool cur: index === win.funcIdx
                        width: 110 * win.s; height: width
                        SelGlow { anchors.fill: parent; rad: 4 * win.s; visible: parent.cur }
                        Ico { anchors.centerIn: parent; width: parent.width * 0.58; height: width; name: modelData.sym; stroke: 1.3 }
                        Text {
                            visible: parent.cur
                            anchors { top: parent.bottom; topMargin: 12 * win.s; horizontalCenter: parent.horizontalCenter }
                            text: modelData.label; color: "white"; font.pixelSize: 26 * win.s
                        }
                        MouseArea { anchors.fill: parent; onClicked: { win.zone = "func"; win.funcIdx = index; win.handle("accept") } }
                    }
                }
            }
        }

        // ── ряд плиток ──
        Item {
            id: rowLayer
            anchors.fill: parent
            // в верхнем ряду лента приглушается, чтобы фокус был на значках
            opacity: win.zone === "func" ? 0.45 : 1
            Behavior on opacity { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
            Repeater {
                model: win.homeModel
                Item {
                    id: slot
                    readonly property bool cur: index === win.homeIdx
                    readonly property real ii: win.intro(1 + Math.max(0, index - win.homeIdx + 1))
                    opacity: ii
                    transform: Translate { x: (1 - slot.ii) * 900 * win.s }
                    width: cur ? homeScreen.big : homeScreen.small
                    height: cur ? homeScreen.big + homeScreen.strip : homeScreen.small
                    // одна анимация: rowTop анимируется сам, здесь — только сдвиг невыбранной плитки
                    property real yOff: cur ? 0 : 38 * win.s
                    Behavior on yOff { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                    y: homeScreen.rowTop + yOff
                    x: {
                        var d = index - win.homeIdx
                        if (d < 0) return homeScreen.baseX - 30 * win.s + d * (homeScreen.small + homeScreen.gap)
                        if (d === 0) return homeScreen.baseX
                        return homeScreen.baseX + homeScreen.big + 12 * win.s + (d - 1) * (homeScreen.small + homeScreen.gap)
                    }
                    Behavior on x { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                    Behavior on width { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                    Behavior on height { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                    Tile {
                        width: parent.width; height: width
                        it: modelData
                    }
                    Rectangle {  // чёрная полоса под выбранной плиткой
                        visible: slot.cur
                        y: parent.width; width: parent.width; height: parent.height - parent.width
                        color: "#ee05070c"
                        Text {
                            visible: !(modelData.special)
                            anchors.centerIn: parent
                            text: "Начать"; color: "white"; font.pixelSize: 28 * win.s
                        }
                        Text {
                            visible: !!modelData.special
                            anchors.centerIn: parent
                            text: "↓"; color: "white"; font.pixelSize: 34 * win.s; font.bold: true
                        }
                    }
                    SelGlow {
                        visible: slot.cur && win.zone === "row"
                        anchors.fill: parent; anchors.margins: -3 * win.s
                        rad: 2 * win.s; fill: false
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            if (win.homeIdx === index && win.zone === "row") win.handle("accept")
                            else { win.zone = "row"; win.homeIdx = index; win.play("move") }
                        }
                    }
                }
            }
            // название выбранного
            Column {
                x: homeScreen.baseX + homeScreen.big + 34 * win.s
                y: homeScreen.rowTop + 38 * win.s + homeScreen.small + 30 * win.s
                width: parent.width - x - 80 * win.s
                opacity: win.intro(4)
                spacing: 2 * win.s
                Text {
                    width: parent.width
                    text: win.curItem ? win.curItem.name : ""
                    color: "white"; font.pixelSize: 64 * win.s; font.weight: Font.Light
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    visible: !!(win.curItem && !win.curItem.special)
                    text: win.curItem && !win.curItem.special ? win.curItem.lastText : ""
                    color: "#dbe6ff"; font.pixelSize: 26 * win.s
                    elide: Text.ElideRight
                }
            }
            // белые карточки
            Repeater {
                model: win.cards
                Rectangle {
                    readonly property bool cur: win.zone === "info" && index === win.infoIdx
                    x: homeScreen.cardX + (index % 3) * (homeScreen.cardW + homeScreen.cardGap)
                    y: homeScreen.rowTop + 572 * win.s + Math.floor(index / 3) * (homeScreen.cardH + homeScreen.cardGap)
                    width: homeScreen.cardW; height: homeScreen.cardH
                    color: "#f2f4f8"
                    opacity: (win.zone === "func" ? 0 : 1) * win.intro(5 + index)
                    transform: Translate { y: (1 - win.intro(5 + index)) * 140 * win.s }
                    Behavior on opacity { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
                    // аватар + значок
                    Row {
                        x: 14 * win.s; y: 14 * win.s
                        spacing: 6 * win.s
                        Rectangle {
                            visible: !!modelData.who
                            width: 62 * win.s; height: width; color: "#c9ced6"
                            Text { anchors.centerIn: parent; text: win.me.name.charAt(0).toUpperCase(); color: "white"; font.pixelSize: 34 * win.s; font.weight: Font.DemiBold }
                        }
                        Rectangle {
                            width: 62 * win.s; height: width; color: modelData.icon ? win.accentOf({ icon: modelData.icon }) : "#c9ced6"
                            Image { anchors.fill: parent; anchors.margins: 6 * win.s; sourceSize: Qt.size(96, 96); visible: !!modelData.icon; source: modelData.icon ? win.icon(modelData.icon) : "" }
                            Ico { anchors.fill: parent; anchors.margins: 10 * win.s; visible: !modelData.icon; name: modelData.sym || ""; tint: "white" }
                        }
                    }
                    Ico { visible: !!modelData.who; anchors { right: parent.right; top: parent.top; margins: 12 * win.s } width: 34 * win.s; height: width; name: "applications-games"; tint: "#3a3f48"; stroke: 1.8 }
                    Text {
                        x: 16 * win.s; y: 86 * win.s
                        width: parent.width - 32 * win.s; height: parent.height - 94 * win.s
                        textFormat: Text.StyledText
                        text: (modelData.who ? "<font color='#2f74d8'>" + modelData.who + "</font> " : "") + modelData.title
                        color: "#22262d"; font.pixelSize: 25 * win.s
                        wrapMode: Text.WordWrap; elide: Text.ElideRight; maximumLineCount: 2
                    }
                    SelGlow { anchors.fill: parent; anchors.margins: -4 * win.s; visible: parent.cur; fill: false }
                    MouseArea { anchors.fill: parent; onClicked: { win.zone = "info"; win.infoIdx = index; win.handle("accept") } }
                }
            }
        }
    }
    NumberAnimation { id: homeIntroAnim; target: win; property: "homeIntro"; from: 0; to: 1; duration: 1500; easing.type: Easing.Linear }

    // ───────────────────────── библиотека ─────────────────────────
    property int libCat: 0
    property int libIdx: 0
    property string libZone: "grid"
    property var libModel: []
    readonly property var libCats: [["Игры", "applications-games"], ["Приложения", "view-list-icons"], ["Всё", "view-grid"]]
    function refreshLib() {
        libModel = libCat === 0 ? backend.games() : libCat === 1 ? backend.apps() : backend.allItems()
        if (libIdx >= libModel.length) libIdx = Math.max(0, libModel.length - 1)
    }
    function openLibrary(cat) {
        libCat = cat; libIdx = 0; libZone = libModel.length || cat !== undefined ? "grid" : "side"
        refreshLib()
        if (!libModel.length) libZone = "side"
        stage = "library"; play("open")
    }

    Item {
        id: libScreen
        anchors.fill: parent
        opacity: win.stage === "library" ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 350 } }
        Rectangle { anchors.fill: parent; color: "#14000814" }

        Row {
            x: 80 * win.s; y: 60 * win.s; spacing: 20 * win.s
            SlotLogo { slot: "logo_library"; icon: "view-grid"; anchors.verticalCenter: parent.verticalCenter }
            Text { text: "Библиотека"; color: "white"; font.pixelSize: 48 * win.s; font.weight: Font.Light }
        }
        Text {
            anchors { right: parent.right; top: parent.top; rightMargin: 70 * win.s; topMargin: 70 * win.s }
            text: win.clockText(); color: "white"; font.pixelSize: 30 * win.s
        }
        // боковое меню
        Column {
            x: 80 * win.s; y: 190 * win.s
            width: 380 * win.s
            Repeater {
                model: win.libCats
                Rectangle {
                    readonly property bool cur: index === win.libCat
                    width: parent.width; height: 74 * win.s
                    color: cur ? (win.libZone === "side" ? "#40ffffff" : "#20ffffff") : "transparent"
                    border.color: "white"; border.width: cur && win.libZone === "side" ? 2 * win.s : 0
                    Row {
                        anchors { left: parent.left; leftMargin: 22 * win.s; verticalCenter: parent.verticalCenter }
                        spacing: 18 * win.s
                        Ico { width: 34 * win.s; height: width; name: modelData[1]; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: modelData[0]; color: "white"; font.pixelSize: 30 * win.s; anchors.verticalCenter: parent.verticalCenter }
                    }
                    MouseArea { anchors.fill: parent; onClicked: { win.libCat = index; win.libIdx = 0; win.refreshLib(); win.libZone = "grid" } }
                }
            }
            Item { width: 1; height: 30 * win.s }
            Text {
                width: parent.width; leftPadding: 22 * win.s
                text: win.libModel.length + " " + (win.libCat === 0 ? "игр" : win.libCat === 1 ? "приложений" : "элементов")
                color: win.txt2; font.pixelSize: 24 * win.s
            }
        }
        Rectangle { x: 490 * win.s; y: 190 * win.s; width: 1; height: parent.height - 300 * win.s; color: "#30ffffff" }
        // сетка
        GridView {
            id: libGrid
            x: 540 * win.s; y: 180 * win.s
            width: parent.width - x - 60 * win.s; height: parent.height - y - 120 * win.s
            cellWidth: 250 * win.s; cellHeight: 300 * win.s
            clip: true
            interactive: true
            model: win.libModel
            currentIndex: win.libIdx
            highlightFollowsCurrentItem: false
            readonly property int cols: Math.max(1, Math.floor(width / cellWidth))
            // прокрутка к выбранному элементу при навигации стрелками/геймпадом
            function ensureVisible() {
                if (currentIndex < 0 || !count) return
                var from = contentY
                libScroll.stop()
                positionViewAtIndex(currentIndex, GridView.Contain)
                var to = Math.max(originY, Math.min(contentY, originY + Math.max(0, contentHeight - height)))
                contentY = from
                if (Math.abs(to - from) < 1) return
                libScroll.to = to; libScroll.start()
            }
            onCurrentIndexChanged: ensureVisible()
            onCountChanged: Qt.callLater(ensureVisible)
            onHeightChanged: Qt.callLater(ensureVisible)
            NumberAnimation { id: libScroll; target: libGrid; property: "contentY"; duration: 200; easing.type: Easing.OutCubic }
            delegate: Item {
                width: libGrid.cellWidth; height: libGrid.cellHeight
                readonly property bool cur: index === win.libIdx && win.libZone === "grid"
                Tile {
                    it: modelData
                    sel: parent.cur
                    width: 210 * win.s; height: width
                    x: 10 * win.s; y: 14 * win.s
                    scale: parent.cur ? 1.06 : 1
                    Behavior on scale { NumberAnimation { duration: 160 } }
                }
                Text {
                    x: 10 * win.s; y: 246 * win.s; width: 210 * win.s
                    text: modelData.name; color: parent.cur ? "white" : win.txt2
                    font.pixelSize: 22 * win.s; elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                }
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: function (m) {
                        win.libZone = "grid"
                        if (m.button === Qt.RightButton) { win.libIdx = index; win.handle("options") }
                        else if (win.libIdx === index) win.handle("accept")
                        else { win.libIdx = index; win.play("move") }
                    }
                }
            }
        }
        Text {
            visible: !win.libModel.length
            anchors.centerIn: libGrid
            text: "Здесь пока ничего нет"
            color: win.txt2; font.pixelSize: 30 * win.s
        }
        Row {
            anchors { right: parent.right; bottom: parent.bottom; margins: 54 * win.s }
            spacing: 36 * win.s
            Hint { btn: "cross"; label: win.libZone === "grid" ? "Начать" : "Выбрать" }
            Hint { btn: "options"; label: "Параметры"; visible: win.libZone === "grid" && win.libModel.length > 0 }
            Hint { btn: "circle"; label: "Назад" }
        }
    }

    // ───────────────────────── магазин ─────────────────────────
    property int storeCat: 0
    property int storeIdx: 0
    property string storeZone: "side"
    property var storeAll: []
    property var storeJobs: ({})
    property bool storeBusy: false
    property var storeSrc: []
    property string storeQuery: ""
    property string storeStatus: ""
    property string storeQueryPrev: ""
    function storeNorm(t) { return (t || "").toLowerCase().replace(/ё/g, "е").replace(/[^0-9a-zа-я]+/g, " ") }
    function storeMatch(it, q) {
        var words = storeNorm(q).split(" ").filter(function (w) { return w })
        if (!words.length) return true
        var hay = " " + storeNorm(it.title + " " + (it.titleId || "") + " " + (it.publisher || "") + " " + (it.genre || "")) + " "
        var compact = hay.replace(/ /g, "")
        return words.every(function (w) { return hay.indexOf(w) >= 0 || compact.indexOf(w) >= 0 })
    }
    function openStoreSearch() {
        storeQueryPrev = storeQuery
        if (storeCat === 3) storeCat = 0
        storeIdx = 0
        kbLatin = true
        openKb("Поиск игры", "storesearch", storeQuery)
    }
    readonly property var storeCats: [["Все игры", "store"], ["Из каталогов", "download"], ["Из «Загрузок»", "folder"], ["Источники", "network-wireless"], ["Добавить приложение", "list-add"]]
    readonly property var storeModel: {
        storeJobs
        if (storeCat === 4) return []
        if (storeCat === 3) {
            var r = storeSrc.map(function (x) { return { src: x } })
            r.push({ add: true })
            return r
        }
        var q = storeQuery
        return storeAll.filter(function (x) {
            return (storeCat === 0 || (storeCat === 1 ? x.kind === "catalog" : x.kind === "local")) && storeMatch(x, q)
        })
    }
    readonly property var storeCur: storeCat < 3 ? storeModel[storeIdx] : null
    function storeJob(it) { return it ? storeJobs[it.id] : undefined }
    function refreshStore() {
        storeAll = backend.storeItems(); storeSrc = backend.storeSources(); storeBusy = backend.storeLoading()
        storeStatus = backend.storeStatus()
        if (storeIdx >= storeModel.length) storeIdx = Math.max(0, storeModel.length - 1)
    }
    function openStore() {
        storeSrc = backend.storeSources(); storeQuery = ""
        backend.storeRefresh(); storeBusy = true
        storeAll = backend.storeItems()
        storeIdx = 0; storeZone = storeModel.length ? "grid" : "side"
        overlay = ""; stage = "store"; play("open")
    }
    function storeAccept(it) {
        if (!it) return
        if (storeCat === 3) {
            if (it.add) { openKb("Ссылка или путь к каталогу (JSON)", "storesrc", "https://"); kbLatin = true }
            return
        }
        var j = storeJob(it)
        if (j && j.busy) return
        if (it.installed) {
            var all = backend.games()
            for (var i = 0; i < all.length; i++) if (all[i].id === "ps4-" + it.titleId) { launchItem(all[i]); return }
            return
        }
        if (!ps4.found) { toast("Эмулятор не найден", "Настройки › Эмулятор PS4", "dialog-error"); play("back"); return }
        if (backend.storeInstall(it.id)) {
            var jj = Object.assign({}, storeJobs); jj[it.id] = { busy: true, frac: 0, text: "Подготовка…" }; storeJobs = jj
            toast(it.kind === "local" ? "Установка" : "Загрузка началась", it.title, "download"); play("accept")
        }
    }
    function storeHandle(a) {
        var cols = storeGrid.cols, n = storeModel.length
        if (storeZone === "side") {
            if (a === "up" && storeCat > 0) { storeCat--; storeIdx = 0; play("move") }
            else if (a === "down" && storeCat < storeCats.length - 1) { storeCat++; storeIdx = 0; play("move") }
            else if ((a === "right" || a === "accept") && storeCat === 4) openAddApp()
            else if ((a === "right" || a === "accept") && n) { storeZone = "grid"; play("move") }
            else if (a === "back" && storeQuery) { storeQuery = ""; storeIdx = 0; play("back") }
            else if (a === "back") goHome()
            else if (a === "triangle") { backend.storeRefresh(); storeBusy = true; play("accept") }
            else if (a === "square") { openStoreSearch(); return }
        } else if (storeCat === 3) {
            if (a === "up" && storeIdx > 0) { storeIdx--; play("move") }
            else if (a === "down" && storeIdx < n - 1) { storeIdx++; play("move") }
            else if (a === "left" || a === "back") { storeZone = "side"; play("move") }
            else if (a === "square") openStoreSearch()
            else if (a === "accept") storeAccept(storeModel[storeIdx])
            else if (a === "triangle" && storeModel[storeIdx] && storeModel[storeIdx].src) {
                backend.removeStoreSource(storeModel[storeIdx].src); storeBusy = true; refreshStore()
                toast("Источник удалён", "", "edit-delete"); play("accept")
            }
        } else {
            if (a === "left") { if (storeIdx % cols === 0) storeZone = "side"; else storeIdx--; play("move") }
            else if (a === "right" && storeIdx < n - 1 && storeIdx % cols !== cols - 1) { storeIdx++; play("move") }
            else if (a === "up" && storeIdx - cols >= 0) { storeIdx -= cols; play("move") }
            else if (a === "down" && storeIdx + cols < n) { storeIdx += cols; play("move") }
            else if (a === "accept") storeAccept(storeCur)
            else if (a === "triangle") {
                var j = storeJob(storeCur)
                if (j && j.busy) { backend.storeCancel(storeCur.id); toast("Отмена…", storeCur.title, "window-close") }
                else { backend.storeRefresh(); storeBusy = true }
                play("accept")
            }
            else if (a === "square") openStoreSearch()
            else if (a === "back" && storeQuery) { storeQuery = ""; storeIdx = 0; play("back") }
            else if (a === "back") goHome()
            else if (a === "tabnext") { storeCat = (storeCat + 1) % storeCats.length; storeIdx = 0; if (storeCat === 4) storeZone = "side" }
            else if (a === "tabprev") { storeCat = (storeCat + storeCats.length - 1) % storeCats.length; storeIdx = 0; if (storeCat === 4) storeZone = "side" }
        }
    }

    component StoreButton: Rectangle {
        property var it
        readonly property var job: win.storeJob(it)
        readonly property bool busy: !!(job && job.busy)
        width: 330 * win.s; height: 64 * win.s; radius: 4 * win.s
        color: busy ? "#40000000" : it && it.installed ? "#e8ffffff" : "#ffd84a"
        Rectangle {
            visible: parent.busy
            width: parent.width * (parent.job ? parent.job.frac : 0); height: parent.height; radius: parent.radius
            color: "#6fd6ff"
            Behavior on width { NumberAnimation { duration: 250 } }
        }
        Row {
            anchors.centerIn: parent; spacing: 12 * win.s
            Ico { width: 30 * win.s; height: width; anchors.verticalCenter: parent.verticalCenter; stroke: 1.8
                  name: parent.parent.busy ? "download" : it && it.installed ? "media-playback-start" : "download"
                  tint: parent.parent.busy ? "white" : "#10203a" }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: parent.parent.busy ? Math.round(parent.parent.job.frac * 100) + "%" : it && it.installed ? "Играть" : it && it.kind === "local" ? "Установить" : "Скачать"
                color: parent.parent.busy ? "white" : "#10203a"; font.pixelSize: 27 * win.s; font.weight: Font.DemiBold
            }
        }
    }

    Item {
        id: storeScreen
        anchors.fill: parent
        opacity: win.stage === "store" ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 350 } }
        Rectangle { anchors.fill: parent; color: "#30000814" }

        Row {
            x: 80 * win.s; y: 60 * win.s; spacing: 20 * win.s
            SlotLogo { slot: "logo_store"; icon: "store"; anchors.verticalCenter: parent.verticalCenter }
            Text { text: "Магазин"; color: "white"; font.pixelSize: 48 * win.s; font.weight: Font.Light }
        }
        Rectangle {  // строка поиска
            id: storeSearchBox
            x: 490 * win.s; y: 62 * win.s
            width: Math.min(720 * win.s, parent.width - x - 520 * win.s); height: 60 * win.s; radius: height / 2
            color: win.storeQuery ? "#38ffffff" : "#1effffff"
            border.color: win.storeQuery ? "white" : "#40ffffff"; border.width: win.storeQuery ? 2 * win.s : 1
            Row {
                anchors { left: parent.left; leftMargin: 22 * win.s; verticalCenter: parent.verticalCenter }
                spacing: 14 * win.s
                Ico { width: 30 * win.s; height: width; name: "system-search"; anchors.verticalCenter: parent.verticalCenter }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: storeSearchBox.width - 150 * win.s; elide: Text.ElideRight
                    text: win.storeQuery || "Поиск игр"
                    color: win.storeQuery ? "white" : win.txt2; font.pixelSize: 27 * win.s
                }
            }
            Text {  // крестик — сбросить поиск
                visible: !!win.storeQuery
                anchors { right: parent.right; rightMargin: 24 * win.s; verticalCenter: parent.verticalCenter }
                text: "✕"; color: "white"; font.pixelSize: 26 * win.s
                MouseArea { anchors.fill: parent; anchors.margins: -12 * win.s; onClicked: { win.storeQuery = ""; win.storeIdx = 0; win.play("back") } }
            }
            MouseArea { anchors.fill: parent; z: -1; onClicked: win.openStoreSearch() }
        }
        Row {
            anchors { right: parent.right; top: parent.top; rightMargin: 70 * win.s; topMargin: 70 * win.s }
            spacing: 30 * win.s
            Text { visible: win.storeBusy || !!win.storeStatus; text: win.storeBusy ? "Обновление каталога…" : win.storeStatus; color: win.txt2; font.pixelSize: 26 * win.s; anchors.verticalCenter: parent.verticalCenter }
            Text { text: win.clockText(); color: "white"; font.pixelSize: 30 * win.s }
        }
        // категории
        Column {
            x: 80 * win.s; y: 190 * win.s; width: 340 * win.s
            Repeater {
                model: win.storeCats
                Rectangle {
                    readonly property bool cur: index === win.storeCat
                    width: parent.width; height: 74 * win.s
                    color: cur ? (win.storeZone === "side" ? "#40ffffff" : "#20ffffff") : "transparent"
                    border.color: "white"; border.width: cur && win.storeZone === "side" ? 2 * win.s : 0
                    Row {
                        anchors { left: parent.left; leftMargin: 22 * win.s; verticalCenter: parent.verticalCenter }
                        spacing: 18 * win.s
                        Ico { width: 34 * win.s; height: width; name: modelData[1]; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: modelData[0]; color: "white"; font.pixelSize: 29 * win.s; anchors.verticalCenter: parent.verticalCenter
                               width: 260 * win.s; fontSizeMode: Text.HorizontalFit; minimumPixelSize: 20 * win.s }
                    }
                    MouseArea { anchors.fill: parent; onClicked: { win.storeCat = index; win.storeIdx = 0; win.storeZone = "side"; if (index === 4) win.openAddApp() } }
                }
            }
            Item { width: 1; height: 30 * win.s }
            Text {
                width: parent.width; leftPadding: 22 * win.s; wrapMode: Text.WordWrap
                text: win.storeCat === 4 ? "" : win.storeCat === 3 ? win.storeSrc.length + " источн." : win.storeModel.length + " игр" + (win.storeQuery ? "\nпо запросу «" + win.storeQuery + "»" : "")
                color: win.txt2; font.pixelSize: 24 * win.s
            }
        }
        Rectangle { x: 450 * win.s; y: 190 * win.s; width: 1; height: parent.height - 300 * win.s; color: "#30ffffff" }

        // ── витрина: выбранная игра ──
        Item {
            id: hero
            visible: win.storeCat < 3 && !!win.storeCur
            x: 490 * win.s; y: 170 * win.s
            width: parent.width - x - 70 * win.s; height: 400 * win.s
            clip: true
            Rectangle { anchors.fill: parent; radius: 6 * win.s; color: "#40000814" }
            Image {
                anchors.fill: parent
                source: win.storeCur ? win.storeCur.bg : ""
                fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize.width: 1400
                opacity: status === Image.Ready ? 0.7 : 0
                Behavior on opacity { NumberAnimation { duration: 400 } }
            }
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "#e0061230" }
                    GradientStop { position: 0.75; color: "#40061230" }
                    GradientStop { position: 1; color: "#10061230" }
                }
            }
            Rectangle {
                id: heroIcon
                x: 40 * win.s; anchors.verticalCenter: parent.verticalCenter
                width: 300 * win.s; height: width; color: "#30ffffff"
                Image { anchors.fill: parent; source: win.storeCur ? win.storeCur.icon : ""; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize: Qt.size(512, 512) }
                Ico { anchors.centerIn: parent; width: parent.width * 0.4; height: width; name: "applications-games"; visible: !(win.storeCur && win.storeCur.icon) }
                layer.enabled: true
                layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "#a0000000"; shadowBlur: 0.8; shadowVerticalOffset: 8 * win.s }
            }
            Column {
                x: heroIcon.x + heroIcon.width + 44 * win.s; y: 46 * win.s
                width: parent.width - x - 40 * win.s; spacing: 12 * win.s
                Text { width: parent.width; text: win.storeCur ? win.storeCur.title : ""; color: "white"; font.pixelSize: 52 * win.s; font.weight: Font.Light; elide: Text.ElideRight }
                Text {
                    width: parent.width; color: win.txt2; font.pixelSize: 24 * win.s; elide: Text.ElideRight
                    text: {
                        var c = win.storeCur; if (!c) return ""
                        var p = []
                        if (c.publisher) p.push(c.publisher)
                        if (c.genre) p.push(c.genre)
                        if (c.titleId) p.push(c.titleId)
                        if (c.version) p.push("v" + c.version)
                        if (c.size) p.push(c.size)
                        return p.join("  ·  ")
                    }
                }
                Text { width: parent.width; height: 96 * win.s; text: win.storeCur ? win.storeCur.desc : ""; color: "white"; font.pixelSize: 24 * win.s; wrapMode: Text.WordWrap; elide: Text.ElideRight; maximumLineCount: 3 }
                Item { width: 1; height: 4 * win.s }
                Row {
                    spacing: 24 * win.s
                    StoreButton { it: win.storeCur }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        readonly property var j: win.storeJob(win.storeCur)
                        text: j && j.busy ? j.text : win.storeCur && win.storeCur.installed ? "Установлено" : win.storeCur ? "Источник: " + win.storeCur.source : ""
                        color: win.txt2; font.pixelSize: 23 * win.s
                    }
                }
            }
        }

        // ── сетка игр ──
        GridView {
            id: storeGrid
            visible: win.storeCat < 3
            x: 480 * win.s; y: 600 * win.s
            width: parent.width - x - 60 * win.s; height: parent.height - y - 110 * win.s
            cellWidth: 230 * win.s; cellHeight: 290 * win.s
            clip: true
            model: win.storeCat < 3 ? win.storeModel : []
            currentIndex: win.storeIdx
            highlightFollowsCurrentItem: false
            readonly property int cols: Math.max(1, Math.floor(width / cellWidth))
            // прокрутка к выбранному элементу при навигации стрелками/геймпадом
            function ensureVisible() {
                if (currentIndex < 0 || !count) return
                var from = contentY
                storeScroll.stop()
                positionViewAtIndex(currentIndex, GridView.Contain)
                var to = Math.max(originY, Math.min(contentY, originY + Math.max(0, contentHeight - height)))
                contentY = from
                if (Math.abs(to - from) < 1) return
                storeScroll.to = to; storeScroll.start()
            }
            onCurrentIndexChanged: ensureVisible()
            onCountChanged: Qt.callLater(ensureVisible)
            onHeightChanged: Qt.callLater(ensureVisible)
            NumberAnimation { id: storeScroll; target: storeGrid; property: "contentY"; duration: 200; easing.type: Easing.OutCubic }
            delegate: Item {
                width: storeGrid.cellWidth; height: storeGrid.cellHeight
                readonly property bool cur: index === win.storeIdx && win.storeZone === "grid"
                readonly property var job: win.storeJob(modelData)
                Rectangle {
                    id: cardImg
                    x: 12 * win.s; y: 12 * win.s; width: 200 * win.s; height: width
                    color: "#30ffffff"; radius: 3 * win.s
                    scale: parent.cur ? 1.06 : 1
                    Behavior on scale { NumberAnimation { duration: 160 } }
                    Image { anchors.fill: parent; source: modelData.icon || ""; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize: Qt.size(256, 256) }
                    Ico { anchors.centerIn: parent; width: parent.width * 0.4; height: width; name: "applications-games"; visible: !modelData.icon }
                    Rectangle {  // полоска прогресса
                        visible: !!(parent.parent.job && parent.parent.job.busy)
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        height: 10 * win.s; color: "#90000000"
                        Rectangle { height: parent.height; color: "#6fd6ff"; width: parent.width * (parent.parent.parent.job ? parent.parent.parent.job.frac : 0) }
                    }
                    Rectangle {  // метка «Установлено»
                        visible: !!modelData.installed
                        anchors { right: parent.right; top: parent.top; margins: 8 * win.s }
                        width: 36 * win.s; height: width; radius: width / 2; color: "#3fd8a8"
                        Text { anchors.centerIn: parent; text: "✓"; color: "white"; font.pixelSize: 22 * win.s; font.bold: true }
                    }
                    SelGlow { visible: cardImg.parent.cur; anchors.fill: parent; anchors.margins: -5 * win.s }
                }
                Text {
                    x: 12 * win.s; y: 224 * win.s; width: 200 * win.s
                    text: modelData.title; color: parent.cur ? "white" : win.txt2
                    font.pixelSize: 22 * win.s; elide: Text.ElideRight
                }
                Text {
                    x: 12 * win.s; y: 252 * win.s; width: 200 * win.s
                    text: modelData.installed ? "Установлено" : (parent.job && parent.job.busy) ? Math.round(parent.job.frac * 100) + "%" : modelData.size || (modelData.kind === "local" ? "Архив" : "")
                    color: modelData.installed ? "#7ff0c8" : win.txt2; font.pixelSize: 19 * win.s; elide: Text.ElideRight
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: { win.storeZone = "grid"; if (win.storeIdx === index) win.handle("accept"); else { win.storeIdx = index; win.play("move") } }
                }
            }
        }
        Column {
            visible: win.storeCat < 3 && !win.storeModel.length
            x: 520 * win.s; y: 260 * win.s; width: parent.width - x - 120 * win.s; spacing: 22 * win.s
            Text { width: parent.width; text: win.storeBusy ? "Загрузка каталога…" : win.storeStatus && !win.storeModel.length ? win.storeStatus + "…" : win.storeQuery ? "Ничего не найдено по запросу «" + win.storeQuery + "»" : "Здесь пока нет игр"; color: "white"; font.pixelSize: 40 * win.s; font.weight: Font.Light; wrapMode: Text.WordWrap }
            Text {
                visible: !win.storeBusy && !!win.storeQuery && !win.storeStatus
                width: parent.width; wrapMode: Text.WordWrap; color: win.txt2; font.pixelSize: 25 * win.s
                text: "Нажмите □ (или F), чтобы изменить запрос, или ○ (Esc), чтобы сбросить поиск."
            }
            Text {
                visible: !win.storeBusy && !win.storeQuery && !win.storeStatus
                width: parent.width; wrapMode: Text.WordWrap; color: win.txt2; font.pixelSize: 25 * win.s; lineHeight: 1.25
                text: "Магазин показывает игры из двух мест:\n"
                    + "•  каталоги — добавьте ссылку на JSON-каталог в разделе «Источники» (например, свой сервер или NAS с резервными копиями ваших игр);\n"
                    + "•  папки «Документы/Games» и «Загрузки» — архивы .zip / .7z / .rar / .tar с игрой PS4 (папка с eboot.bin и sce_sys) и пакеты .pkg появятся здесь автоматически.\n"
                    + "Для .pkg нужен распаковщик ShadPs4Plus PKG Extractor (AppImage) — достаточно скачать его в «Загрузки».\n\n"
                    + "После установки игра сразу появится на главном экране и запустится через shadPS4."
            }
        }

        // ── добавить приложение ──
        Column {
            visible: win.storeCat === 4
            x: 520 * win.s; y: 220 * win.s; width: parent.width - x - 120 * win.s; spacing: 26 * win.s
            Text { width: parent.width; text: "Добавить приложение"; color: "white"; font.pixelSize: 44 * win.s; font.weight: Font.Light }
            Text {
                width: parent.width; wrapMode: Text.WordWrap; color: win.txt2; font.pixelSize: 26 * win.s; lineHeight: 1.25
                text: "Выберите программу, установленную на ПК, или укажите файл (AppImage, скрипт). "
                    + "Она появится на главном экране и в библиотеке рядом с играми. Убрать её можно через меню параметров."
            }
            Item { width: 1; height: 6 * win.s }
            Row {
                spacing: 24 * win.s
                Repeater {
                    model: [["Выбрать из приложений на ПК", "list-add", "addapp"], ["Указать файл программы", "document-open", "addappfile"]]
                    Rectangle {
                        width: 440 * win.s; height: 72 * win.s; radius: 4 * win.s
                        color: index === 0 ? "#ffd84a" : "#30ffffff"
                        Row {
                            anchors.centerIn: parent; spacing: 14 * win.s
                            Ico { width: 30 * win.s; height: width; name: modelData[1]; tint: index === 0 ? "#10203a" : "white"; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: modelData[0]; color: index === 0 ? "#10203a" : "white"; font.pixelSize: 26 * win.s; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
                        }
                        MouseArea { anchors.fill: parent; onClicked: win.doAct(modelData[2]) }
                    }
                }
            }
            Text { width: parent.width; color: win.txt2; font.pixelSize: 22 * win.s; text: "✕ — выбрать из приложений на ПК" }
        }

        // ── источники ──
        Column {
            visible: win.storeCat === 3
            x: 490 * win.s; y: 180 * win.s; width: parent.width - x - 70 * win.s
            Repeater {
                model: win.storeCat === 3 ? win.storeModel : []
                Rectangle {
                    readonly property bool cur: index === win.storeIdx && win.storeZone === "grid"
                    width: parent.width; height: 74 * win.s
                    color: cur ? "#40ffffff" : "transparent"
                    border.color: "#cfeaff"; border.width: cur ? 2 * win.s : 0
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#30ffffff"; visible: !parent.cur }
                    Row {
                        anchors { left: parent.left; leftMargin: 22 * win.s; verticalCenter: parent.verticalCenter }
                        spacing: 18 * win.s
                        Ico { width: 32 * win.s; height: width; name: modelData.add ? "list-add" : "download"; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: modelData.add ? "Добавить источник" : modelData.src; color: "white"; font.pixelSize: 27 * win.s; anchors.verticalCenter: parent.verticalCenter }
                    }
                }
            }
            Item { width: 1; height: 34 * win.s }
            Text {
                width: parent.width; wrapMode: Text.WordWrap; color: win.txt2; font.pixelSize: 22 * win.s; lineHeight: 1.2
                textFormat: Text.PlainText
                text: "Источник — JSON-файл по ссылке или на диске:\n"
                    + "{ \"name\": \"Мой сервер\", \"games\": [ { \"title\": \"…\", \"titleId\": \"CUSA00000\", \"url\": \"game.zip\",\n"
                    + "   \"icon\": \"icon0.png\", \"background\": \"pic1.png\", \"size\": 123456789, \"description\": \"…\", \"sha256\": \"…\" } ] }\n"
                    + "Пути в url / icon / background можно указывать относительно файла каталога."
            }
        }

        Row {
            anchors { right: parent.right; bottom: parent.bottom; margins: 54 * win.s }
            spacing: 36 * win.s
            Hint {
                btn: "cross"
                label: win.storeZone === "side" ? "Выбрать" : win.storeCat === 3 ? (win.storeModel[win.storeIdx] && win.storeModel[win.storeIdx].add ? "Добавить" : "—")
                       : win.storeCur && win.storeCur.installed ? "Играть" : win.storeCur && win.storeCur.kind === "local" ? "Установить" : "Скачать"
            }
            Hint {
                btn: "triangle"
                label: win.storeCat === 3 && win.storeZone === "grid" ? "Удалить" : (win.storeJob(win.storeCur) && win.storeJob(win.storeCur).busy) ? "Отменить" : "Обновить"
            }
            Hint { btn: "square"; label: "Поиск" }
            Hint { btn: "circle"; label: win.storeQuery && win.storeCat < 3 ? "Сбросить поиск" : "Назад" }
        }
    }

    // ───────────────────────── настройки ─────────────────────────
    property var setStack: [{ page: "root", idx: 0 }]
    readonly property var setTop: setStack[setStack.length - 1]
    property int setIdx: 0
    readonly property var setRows: { cfg; st; sysSt; sysInfo; users; netResult; ps4; media; return rowsFor(setTop.page) }

    function pageTitle(p) {
        var t = { root: "Настройки", sound: "Звук", theme: "Темы", users: "Пользователи", library: "Библиотека",
                  network: "Сеть", storage: "Хранилище", system: "Система", power: "Питание", sink: "Устройство вывода", ps4: "Эмулятор PS4" }
        if (t[p]) return t[p]
        if (p.indexOf("user:") === 0) return users[+p.split(":")[1]] ? users[+p.split(":")[1]].name : "Пользователь"
        if (p.indexOf("ucolor:") === 0) return "Цвет аватара"
        return p
    }
    function rowsFor(p) {
        var i, r = []
        switch (p) {
        case "root": return [
            { t: "nav", label: "Звук",         sym: "audio-volume-high", to: "sound" },
            { t: "nav", label: "Темы",         sym: "preferences-desktop-color", to: "theme" },
            { t: "nav", label: "Пользователи", sym: "user-identity", to: "users" },
            { t: "nav", label: "Библиотека",   sym: "applications-games", to: "library" },
            { t: "nav", label: "Эмулятор PS4", sym: "input-gaming", to: "ps4", value: ps4.found ? ps4.games + " игр" : "не найден" },
            { t: "nav", label: "Сеть",         sym: "network-wireless", to: "network" },
            { t: "nav", label: "Хранилище",    sym: "drive-harddisk", to: "storage" },
            { t: "nav", label: "Система",      sym: "configure", to: "system" },
            { t: "nav", label: "Питание",      sym: "system-shutdown", to: "power" } ]
        case "sound":
            var sinkName = "—"
            for (i = 0; i < sysSt.sinks.length; i++) if (sysSt.sinks[i][0] === sysSt.sink) sinkName = sysSt.sinks[i][1]
            return [
            { t: "slider", label: "Громкость", value: sysSt.volume, act: "volume" },
            { t: "toggle", label: "Выключить звук", on: sysSt.muted, act: "mute" },
            { t: "nav", label: "Устройство вывода", value: sinkName, to: "sink" },
            { t: "toggle", label: "Звуки интерфейса", on: cfg.sounds, act: "set:sounds" } ]
        case "sink":
            for (i = 0; i < sysSt.sinks.length; i++)
                r.push({ t: "radio", label: sysSt.sinks[i][1], on: sysSt.sinks[i][0] === sysSt.sink, act: "sink:" + sysSt.sinks[i][0] })
            if (!r.length) r.push({ t: "info", label: "Устройства не найдены" })
            return r
        case "theme":
            for (i = 0; i < themeKeys.length; i++)
                r.push({ t: "radio", label: themes[themeKeys[i]].name, on: cfg.theme === themeKeys[i], act: "theme:" + themeKeys[i], swatch: themes[themeKeys[i]].top })
            return r
        case "users":
            for (i = 0; i < users.length; i++)
                r.push({ t: "nav", label: users[i].name, value: i === curUser ? "Вы вошли" : "", to: "user:" + i, avatar: i })
            r.push({ t: "action", label: "Добавить пользователя", sym: "list-add", act: "adduser" })
            r.push({ t: "action", label: "Сменить пользователя", sym: "system-switch-user", act: "logout" })
            return r
        case "library": return [
            { t: "action", label: "Обновить список приложений", sym: "view-refresh", act: "rescan" },
            { t: "action", label: "Вернуть скрытые элементы", value: backend.hiddenCount() + "", sym: "edit-undo", act: "unhide" },
            { t: "info", label: "Игр в библиотеке", value: st.games + "" },
            { t: "info", label: "Приложений", value: st.apps + "" },
            { t: "info", label: "Всего запусков", value: st.launches + "" },
            { t: "info", label: "Общее время", value: st.timeText } ]
        case "network": return [
            { t: "info", label: "Подключение", value: sysSt.net },
            { t: "info", label: "Тип", value: sysSt.netType || "—" },
            { t: "info", label: "IP-адрес", value: sysSt.ip },
            { t: "action", label: "Проверить подключение к Интернету", value: netResult, act: "nettest" } ]
        case "storage":
            for (i = 0; i < sysSt.disks.length; i++)
                r.push({ t: "bar", label: sysSt.disks[i].mount, value: sysSt.disks[i].text, frac: sysSt.disks[i].used / Math.max(1, sysSt.disks[i].total) })
            if (!r.length) r.push({ t: "info", label: "Нет данных" })
            return r
        case "system":
            r = [
            { t: "toggle", label: "Запускать вместе с системой", on: cfg.autostart, act: "set:autostart" },
            { t: "toggle", label: "24-часовой формат времени", on: cfg.clock24, act: "set:clock24" },
            { t: "toggle", label: "Полноэкранный режим", on: win.visibility === Window.FullScreen, act: "fullscreen" } ]
            for (i = 0; i < sysInfo.length; i++) r.push({ t: "info", label: sysInfo[i][0], value: sysInfo[i][1] })
            r.push({ t: "info", label: "Контроллеры", value: sysSt.pads.length ? sysSt.pads.join(", ") + (sysSt.padBattery >= 0 ? " · " + sysSt.padBattery + "%" : "") : "Не подключены" })
            return r
        case "power": return powerItems()
        case "ps4":
            r = [
            { t: "action", label: "shadPS4", value: ps4.found ? ps4.emu.replace(/^\/home\/[^\/]+/, "~") : "Не найден — укажите путь", sym: "input-gaming", act: "ps4emu" },
            { t: "action", label: "Распаковщик PKG", value: ps4.pkgTool ? ps4.pkgTool.replace(/^\/home\/[^\/]+/, "~") : "Не найден — укажите путь", sym: "package-x-generic", act: "pkgtool" },
            { t: "toggle", label: "Игры на весь экран", on: cfg.ps4Fullscreen, act: "set:ps4Fullscreen" },
            { t: "toggle", label: "Показывать FPS", on: cfg.ps4Fps, act: "set:ps4Fps" },
            { t: "action", label: "Найти игры заново", value: ps4.games + " игр", sym: "view-refresh", act: "rescan" },
            { t: "action", label: "Добавить папку с играми", sym: "folder-new", act: "ps4add" } ]
            for (i = 0; i < ps4.dirs.length; i++) {
                var mine = ps4.userDirs.indexOf(ps4.dirs[i]) >= 0
                r.push(mine ? { t: "action", label: ps4.dirs[i].replace(/^\/home\/[^\/]+/, "~"), value: "Удалить", sym: "folder", act: "ps4del:" + i }
                            : { t: "info", label: ps4.dirs[i].replace(/^\/home\/[^\/]+/, "~"), value: "авто" })
            }
            r.push({ t: "info", label: "Игра — папка с eboot.bin и sce_sys/param.sfo" })
            r.push({ t: "info", label: "Пакеты .pkg устанавливаются через Магазин › Из «Загрузок»" })
            return r
        }
        if (p.indexOf("user:") === 0) {
            var ui = +p.split(":")[1], u = users[ui]
            if (!u) return []
            r = [
            { t: "action", label: "Имя пользователя", value: u.name, sym: "edit-rename", act: "rename:" + ui },
            { t: "nav", label: "Цвет аватара", value: avNames[u.color % 8], to: "ucolor:" + ui, swatch: avColors[u.color % 8] } ]
            if (users.length > 1) r.push({ t: "action", label: "Удалить пользователя", sym: "edit-delete", act: "deluser:" + ui })
            return r
        }
        if (p.indexOf("ucolor:") === 0) {
            var ci = +p.split(":")[1]
            for (i = 0; i < avColors.length; i++)
                r.push({ t: "radio", label: avNames[i], on: users[ci] && users[ci].color === i, act: "ucolor:" + ci + ":" + i, swatch: avColors[i] })
            return r
        }
        return r
    }
    function powerItems() {
        return [
            { t: "action", label: "Перейти в режим покоя", sym: "system-suspend", act: "power:suspend" },
            { t: "action", label: "Выключить систему", sym: "system-shutdown", act: "power:poweroff" },
            { t: "action", label: "Перезагрузить систему", sym: "system-reboot", act: "power:reboot" },
            { t: "action", label: "Сменить пользователя", sym: "system-switch-user", act: "logout" },
            { t: "action", label: "Выйти из Tide", sym: "system-log-out", act: "power:quit" } ]
    }
    function openSettings() {
        setStack = [{ page: "root", idx: 0 }]; setIdx = 0
        refreshSys(); sysInfo = backend.sysinfo()
        stage = "settings"; play("open")
    }
    function setPush(page) {
        var stk = setStack.slice(); stk[stk.length - 1].idx = setIdx
        stk.push({ page: page, idx: 0 }); setStack = stk; setIdx = 0
        play("accept")
    }
    function setPop() {
        if (setStack.length <= 1) { goHome(); return }
        var stk = setStack.slice(); stk.pop(); setStack = stk
        setIdx = stk[stk.length - 1].idx
        play("back")
    }

    Item {
        id: setScreen
        anchors.fill: parent
        opacity: win.stage === "settings" ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 350 } }
        Rectangle { anchors.fill: parent; color: "#14000814" }

        Row {
            x: 150 * win.s; y: 70 * win.s; spacing: 20 * win.s
            SlotLogo { slot: "logo_settings"; icon: "configure"; anchors.verticalCenter: parent.verticalCenter }
            Text {
                text: win.setStack.map(function (x) { return win.pageTitle(x.page) }).join("  ›  ")
                color: "white"; font.pixelSize: 44 * win.s; font.weight: Font.Light
            }
        }
        Text {
            anchors { right: parent.right; top: parent.top; rightMargin: 70 * win.s; topMargin: 80 * win.s }
            text: win.clockText(); color: "white"; font.pixelSize: 30 * win.s
        }
        ListView {
            id: setList
            x: 150 * win.s; y: 180 * win.s
            width: parent.width - 300 * win.s; height: parent.height - y - 130 * win.s
            clip: true
            model: win.setRows
            currentIndex: win.setIdx
            highlightFollowsCurrentItem: false
            boundsBehavior: Flickable.StopAtBounds
            // прокрутка к выбранному элементу при навигации стрелками/геймпадом
            function ensureVisible() {
                if (currentIndex < 0 || !count) return
                var from = contentY
                setScroll.stop()
                positionViewAtIndex(currentIndex, ListView.Contain)
                var to = Math.max(originY, Math.min(contentY, originY + Math.max(0, contentHeight - height)))
                contentY = from
                if (Math.abs(to - from) < 1) return
                setScroll.to = to; setScroll.start()
            }
            onCurrentIndexChanged: ensureVisible()
            onCountChanged: Qt.callLater(ensureVisible)
            onHeightChanged: Qt.callLater(ensureVisible)
            NumberAnimation { id: setScroll; target: setList; property: "contentY"; duration: 200; easing.type: Easing.OutCubic }
            delegate: Item {
                width: setList.width; height: 86 * win.s
                readonly property bool cur: index === win.setIdx
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#26ffffff" }
                SelGlow { anchors.fill: parent; anchors.margins: 3 * win.s; visible: parent.cur }
                Row {
                    anchors { left: parent.left; leftMargin: 28 * win.s; verticalCenter: parent.verticalCenter }
                    spacing: 24 * win.s
                    Ico {
                        visible: !!modelData.sym
                        width: 40 * win.s; height: width
                        name: modelData.sym || ""
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Avatar {
                        visible: modelData.avatar !== undefined
                        width: 48 * win.s; height: width
                        ci: modelData.avatar !== undefined && win.users[modelData.avatar] ? win.users[modelData.avatar].color : 0
                        nm: modelData.label
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Rectangle {
                        visible: !!modelData.swatch && modelData.t === "radio"
                        width: 40 * win.s; height: width; radius: 6 * win.s
                        color: modelData.swatch || "transparent"; border.color: "#80ffffff"; border.width: 1
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: modelData.label; color: modelData.t === "info" ? win.txt2 : "white"
                        font.pixelSize: 30 * win.s
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                // правая часть
                Row {
                    anchors { right: parent.right; rightMargin: 28 * win.s; verticalCenter: parent.verticalCenter }
                    spacing: 20 * win.s
                    Text {
                        visible: !!modelData.value && modelData.t !== "slider" && modelData.t !== "bar"
                        text: modelData.value || ""; color: modelData.t === "info" ? "white" : win.txt2
                        font.pixelSize: 26 * win.s; anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, setList.width * 0.5); elide: Text.ElideRight
                    }
                    Rectangle {  // переключатель-флажок
                        visible: modelData.t === "toggle" || modelData.t === "radio"
                        width: 36 * win.s; height: width
                        radius: modelData.t === "radio" ? width / 2 : 4 * win.s
                        color: modelData.on ? "white" : "transparent"
                        border.color: "white"; border.width: 2 * win.s
                        anchors.verticalCenter: parent.verticalCenter
                        Text { anchors.centerIn: parent; visible: !!modelData.on; text: "✓"; color: "#0d3a7a"; font.pixelSize: 26 * win.s; font.bold: true }
                    }
                    Item {  // ползунок / шкала
                        visible: modelData.t === "slider" || modelData.t === "bar"
                        width: 460 * win.s; height: 40 * win.s
                        anchors.verticalCenter: parent.verticalCenter
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 110 * win.s; height: 8 * win.s; radius: 4 * win.s
                            color: "#40ffffff"
                            Rectangle {
                                height: parent.height; radius: parent.radius; color: "white"
                                width: parent.width * (modelData.t === "slider" ? (modelData.value || 0) / 100 : (modelData.frac || 0))
                                Behavior on width { NumberAnimation { duration: 120 } }
                            }
                        }
                        Text {
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            text: modelData.t === "slider" ? (modelData.value + "%") : (modelData.value || "")
                            color: "white"; font.pixelSize: 24 * win.s
                            width: 100 * win.s; horizontalAlignment: Text.AlignRight
                        }
                    }
                    Text {
                        visible: modelData.t === "nav"
                        text: "›"; color: "white"; font.pixelSize: 40 * win.s
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: { if (win.setIdx === index) win.handle("accept"); else { win.setIdx = index; win.play("move") } }
                }
            }
        }
        Row {
            anchors { right: parent.right; bottom: parent.bottom; margins: 54 * win.s }
            spacing: 36 * win.s
            Hint { btn: "cross"; label: "Ввод" }
            Hint { btn: "lr"; label: "Изменить"; visible: win.setRows[win.setIdx] && win.setRows[win.setIdx].t === "slider" }
            Hint { btn: "circle"; label: "Назад" }
        }
    }

    // ───────────────────────── оверлеи ─────────────────────────
    Rectangle {  // затемнение
        anchors.fill: parent
        color: "#000"
        opacity: win.overlay !== "" && win.overlay !== "launch" ? 0.55 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 250 } }
        MouseArea { anchors.fill: parent; enabled: parent.visible; onClicked: win.handle("back") }
    }

    // меню: quick (слева), options (справа), power (по центру)
    property string menuKind: ""
    property string menuTitle: ""
    property var menuItems: []
    property int menuIdx: 0
    property var menuTarget: null
    function openMenu(kind, title, items) {
        menuKind = kind; menuTitle = title; menuItems = items; menuIdx = 0
        overlay = "menu"; play("open")
    }
    function openPower() { openMenu("power", "Параметры питания", powerItems()) }
    function openOptions(it) {
        if (!it || it.special) return
        menuTarget = it
        var r = [
            { t: "action", label: "Начать", sym: "media-playback-start", act: "launch:" + it.id },
            { t: "action", label: "Информация", sym: "dialog-information", act: "info" },
            { t: "action", label: it.isGame ? "Перенести в приложения" : "Отметить как игру", sym: "applications-games", act: "togglegame" },
            it.pinned && !it.isGame ? { t: "action", label: "Убрать с главного экрана", sym: "edit-delete", act: "unpin" }
                                    : { t: "action", label: "Скрыть", sym: "edit-delete", act: "hide" } ]
        var run = backend.running()
        for (var i = 0; i < run.length; i++) if (run[i].id === it.id) r.push({ t: "action", label: "Закрыть приложение", sym: "window-close", act: "close:" + it.id })
        openMenu("options", it.name, r)
    }

    Item {
        id: menuPanel
        anchors.fill: parent
        visible: win.overlay === "menu" || slide.x !== slide.hiddenX
        readonly property bool center: win.menuKind === "power"
        Glass {
            id: slide
            readonly property real w: (menuPanel.center ? 760 : 620) * win.s
            readonly property real hiddenX: win.menuKind === "quick" ? -w - 40 : (menuPanel.center ? (win.width - w) / 2 : win.width + 40)
            readonly property real shownX: win.menuKind === "quick" ? 0 : (menuPanel.center ? (win.width - w) / 2 : win.width - w)
            width: w
            height: menuPanel.center ? menuCol.height + 240 * win.s : win.height
            y: menuPanel.center ? (win.height - height) / 2 : 0
            x: win.overlay === "menu" ? shownX : hiddenX
            opacity: menuPanel.center ? (win.overlay === "menu" ? 1 : 0) : 1
            scale: menuPanel.center ? (win.overlay === "menu" ? 1 : 0.92) : 1
            radius: menuPanel.center ? 6 * win.s : 0
            color: "#ee07122a"
            Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 200 } }
            Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

            Text {
                id: menuHead
                x: 50 * win.s; y: (menuPanel.center ? 40 : 80) * win.s
                width: parent.width - 100 * win.s
                text: win.menuTitle; color: "white"; font.pixelSize: 38 * win.s; font.weight: Font.Light
                elide: Text.ElideRight
            }
            Column {
                id: menuCol
                x: 30 * win.s
                anchors.top: menuHead.bottom; anchors.topMargin: 34 * win.s
                width: parent.width - 60 * win.s
                Repeater {
                    model: win.menuItems
                    Item {
                        width: menuCol.width; height: 80 * win.s
                        readonly property bool cur: index === win.menuIdx
                        SelGlow { anchors.fill: parent; visible: parent.cur }
                        Row {
                            anchors { left: parent.left; leftMargin: 22 * win.s; verticalCenter: parent.verticalCenter }
                            spacing: 20 * win.s
                            Item {
                                width: 38 * win.s; height: width
                                anchors.verticalCenter: parent.verticalCenter
                                Image { anchors.fill: parent; sourceSize: Qt.size(96, 96); visible: !!modelData.icon; source: modelData.icon ? win.icon(modelData.icon) : "" }
                                Ico { anchors.fill: parent; visible: !modelData.icon; name: modelData.sym || "" }
                            }
                            Text {
                                text: modelData.label; color: "white"; font.pixelSize: 28 * win.s
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(implicitWidth, menuCol.width * (modelData.t === "slider" ? 0.38 : 0.62)); elide: Text.ElideRight
                            }
                        }
                        Text {
                            visible: modelData.t !== "slider" && !!modelData.value
                            anchors { right: parent.right; rightMargin: 22 * win.s; verticalCenter: parent.verticalCenter }
                            text: modelData.value || ""; color: win.txt2; font.pixelSize: 22 * win.s
                        }
                        Row {
                            visible: modelData.t === "slider"
                            anchors { right: parent.right; rightMargin: 22 * win.s; verticalCenter: parent.verticalCenter }
                            spacing: 16 * win.s
                            Rectangle {
                                width: 200 * win.s; height: 8 * win.s; radius: 4 * win.s; color: "#40ffffff"
                                anchors.verticalCenter: parent.verticalCenter
                                Rectangle { height: parent.height; radius: 4 * win.s; color: "white"; width: parent.width * (modelData.value || 0) / 100 }
                            }
                            Text { text: (modelData.value || 0) + "%"; color: "white"; font.pixelSize: 22 * win.s; width: 60 * win.s }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: { win.menuIdx = index; win.handle("accept") }
                        }
                    }
                }
            }
            Row {
                anchors { right: parent.right; bottom: parent.bottom; margins: 34 * win.s }
                spacing: 30 * win.s
                Hint { btn: "cross"; label: "Ввод" }
                Hint { btn: "circle"; label: "Закрыть" }
            }
        }
    }

    // ── быстрое меню (панель слева с подменю) ──
    property var qStack: [{ page: "root", idx: 0 }]
    property int qIdx: 0
    property var qItems: []
    property real qSlide: 0
    function qTitle(p) { return { power: "Питание", sound: "Звук и устройства" }[p] || "" }
    function qBuild(p) {
        var r = [], i
        if (p === "root") {
            var run = backend.running()
            for (i = 0; i < run.length; i++)
                r.push({ t: "app", label: run[i].name, value: "Закрыть приложение · " + run[i].since, icon: run[i].icon, act: "close:" + run[i].id })
            r.push({ t: "nav", label: "Питание", sym: "system-shutdown", to: "power" })
            r.push({ t: "nav", label: "Звук и устройства", sym: "audio-volume-high", to: "sound" })
            r.push({ t: "action", label: "Главный экран", sym: "go-home", act: "home" })
            r.push({ t: "action", label: "Магазин", sym: "store", act: "store" })
            r.push({ t: "action", label: "Библиотека", sym: "view-grid", act: "library" })
            r.push({ t: "action", label: "Уведомления", sym: "notifications", act: "notify" })
            r.push({ t: "action", label: "Сменить пользователя", sym: "system-switch-user", act: "logout" })
            r.push({ t: "action", label: "Настройки", sym: "configure", act: "settings" })
        } else if (p === "power") {
            r = powerItems()
        } else if (p === "sound") {
            r.push({ t: "slider", label: "Громкость", sym: "audio-volume-high", value: sysSt.muted ? 0 : sysSt.volume, act: "volume" })
            r.push({ t: "toggle", label: "Выключить звук", on: sysSt.muted, act: "mute" })
            for (i = 0; i < sysSt.sinks.length; i++)
                r.push({ t: "radio", label: sysSt.sinks[i][1], on: sysSt.sinks[i][0] === sysSt.sink, act: "sink:" + sysSt.sinks[i][0] })
        }
        return r
    }
    function openQuick() {
        refreshSys()
        qStack = [{ page: "root", idx: 0 }]; qIdx = 0; qItems = qBuild("root")
        overlay = "quick"; play("open")
    }
    function qRefresh() { refreshSys(); qItems = qBuild(qStack[qStack.length - 1].page); if (qIdx >= qItems.length) qIdx = qItems.length - 1 }
    function qPush(page) {
        var stk = qStack.slice(); stk[stk.length - 1].idx = qIdx; stk.push({ page: page, idx: 0 })
        qStack = stk; qIdx = 0; qItems = qBuild(page)
        qSlide = 1; qSlideAnim.restart(); play("accept")
    }
    function qPop() {
        if (qStack.length <= 1) { overlay = ""; play("back"); return }
        var stk = qStack.slice(); stk.pop(); qStack = stk
        qIdx = stk[stk.length - 1].idx; qItems = qBuild(stk[stk.length - 1].page)
        qSlide = -1; qSlideAnim.restart(); play("back")
    }
    NumberAnimation { id: qSlideAnim; target: win; property: "qSlide"; to: 0; duration: 260; easing.type: Easing.OutCubic }

    Item {
        id: quickPanel
        anchors.fill: parent
        visible: win.overlay === "quick" || qp.x > -qp.width
        Rectangle {
            id: qp
            width: 660 * win.s; height: parent.height
            x: win.overlay === "quick" ? 0 : -width - 30
            Behavior on x { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
            gradient: Gradient {
                GradientStop { position: 0; color: "#fc121519" }
                GradientStop { position: 1; color: "#fa1b1f27" }
            }
            Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: "#30ffffff" }

            // шапка: пользователь и время
            Row {
                x: 44 * win.s; y: 50 * win.s
                spacing: 20 * win.s
                SqAvatar { width: 64 * win.s; height: width; ci: win.me.color; nm: win.me.name }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Text { text: win.me.name; color: "white"; font.pixelSize: 30 * win.s }
                    Text { text: win.dateText() + "  ·  " + win.clockText(); color: "#a8b0c0"; font.pixelSize: 22 * win.s }
                }
            }
            Rectangle { x: 44 * win.s; y: 150 * win.s; width: parent.width - 88 * win.s; height: 1; color: "#30ffffff" }

            Item {
                id: qBody
                x: 0; y: 166 * win.s
                width: parent.width; height: parent.height - y - 110 * win.s
                clip: true
                Item {
                    width: parent.width; height: parent.height
                    x: win.qSlide * 160 * win.s
                    opacity: 1 - Math.abs(win.qSlide)
                    // заголовок подменю
                    Row {
                        id: qHead
                        visible: win.qStack.length > 1
                        x: 44 * win.s; height: visible ? 70 * win.s : 0
                        spacing: 14 * win.s
                        Text { text: "‹"; color: "#a8b0c0"; font.pixelSize: 40 * win.s; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: win.qTitle(win.qStack[win.qStack.length - 1].page); color: "white"; font.pixelSize: 34 * win.s; font.weight: Font.Light; anchors.verticalCenter: parent.verticalCenter }
                    }
                    Column {
                        id: qCol
                        x: 24 * win.s; anchors.top: qHead.bottom; anchors.topMargin: 6 * win.s
                        width: parent.width - 48 * win.s
                        Repeater {
                            model: win.qItems
                            Item {
                                width: qCol.width
                                height: (modelData.t === "app" ? 112 : 82) * win.s
                                readonly property bool cur: index === win.qIdx
                                SelGlow { anchors.fill: parent; anchors.margins: 3 * win.s; visible: parent.cur }
                                Row {
                                    anchors { left: parent.left; leftMargin: 22 * win.s; verticalCenter: parent.verticalCenter }
                                    spacing: 22 * win.s
                                    Item {
                                        width: (modelData.t === "app" ? 76 : 40) * win.s; height: width
                                        anchors.verticalCenter: parent.verticalCenter
                                        Rectangle { anchors.fill: parent; visible: modelData.t === "app"; color: win.accentOf({ icon: modelData.icon || "" }) }
                                        Image { anchors.fill: parent; anchors.margins: 8 * win.s; sourceSize: Qt.size(96, 96); visible: !!modelData.icon; source: modelData.icon ? win.icon(modelData.icon) : "" }
                                        Ico { anchors.fill: parent; visible: !modelData.icon; name: modelData.sym || ""; stroke: 1.4 }
                                    }
                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        Text {
                                            text: modelData.label; color: "white"; font.pixelSize: 30 * win.s
                                            width: Math.min(implicitWidth, qCol.width * (modelData.t === "slider" ? 0.36 : 0.7)); elide: Text.ElideRight
                                        }
                                        Text { visible: modelData.t === "app"; text: modelData.value || ""; color: "#a8b0c0"; font.pixelSize: 22 * win.s }
                                    }
                                }
                                Text {
                                    visible: modelData.t === "nav"
                                    anchors { right: parent.right; rightMargin: 24 * win.s; verticalCenter: parent.verticalCenter }
                                    text: "›"; color: "white"; font.pixelSize: 40 * win.s
                                }
                                Rectangle {
                                    visible: modelData.t === "toggle" || modelData.t === "radio"
                                    anchors { right: parent.right; rightMargin: 24 * win.s; verticalCenter: parent.verticalCenter }
                                    width: 32 * win.s; height: width
                                    radius: modelData.t === "radio" ? width / 2 : 4 * win.s
                                    color: modelData.on ? "white" : "transparent"; border.color: "white"; border.width: 2 * win.s
                                    Text { anchors.centerIn: parent; visible: !!modelData.on; text: "✓"; color: "#1b2a4a"; font.pixelSize: 22 * win.s; font.bold: true }
                                }
                                Row {
                                    visible: modelData.t === "slider"
                                    anchors { right: parent.right; rightMargin: 24 * win.s; verticalCenter: parent.verticalCenter }
                                    spacing: 16 * win.s
                                    Rectangle {
                                        width: 220 * win.s; height: 6 * win.s; radius: 3 * win.s; color: "#40ffffff"
                                        anchors.verticalCenter: parent.verticalCenter
                                        Rectangle { height: parent.height; radius: 3 * win.s; color: "#6fd6ff"; width: parent.width * (modelData.value || 0) / 100 }
                                        Rectangle {
                                            width: 18 * win.s; height: width; radius: width / 2; color: "white"
                                            anchors.verticalCenter: parent.verticalCenter
                                            x: parent.width * (modelData.value || 0) / 100 - width / 2
                                        }
                                    }
                                    Text { text: (modelData.value || 0); color: "white"; font.pixelSize: 24 * win.s; width: 44 * win.s; horizontalAlignment: Text.AlignRight }
                                }
                                MouseArea { anchors.fill: parent; onClicked: { win.qIdx = index; win.handle("accept") } }
                            }
                        }
                    }
                }
            }
            Row {
                anchors { left: parent.left; bottom: parent.bottom; leftMargin: 44 * win.s; bottomMargin: 44 * win.s }
                spacing: 30 * win.s
                Hint { btn: "cross"; label: "Ввод" }
                Hint { btn: "circle"; label: "Назад" }
                Hint { btn: "lr"; label: "Громкость"; visible: !!(win.qItems[win.qIdx] && win.qItems[win.qIdx].t === "slider") }
            }
        }
    }

    // «Добавить приложение»: список приложений на ПК + указать файл вручную
    property var pcApps: []
    property string addQuery: ""
    readonly property var addRows: {
        var r = [{ kind: "file", name: "Указать файл вручную…", comment: "AppImage, скрипт или исполняемый файл" }]
        var q = storeNorm(addQuery).split(" ").filter(function (w) { return w })
        for (var i = 0; i < pcApps.length; i++) {
            var hay = storeNorm(pcApps[i].name + " " + pcApps[i].comment)
            if (q.every(function (w) { return hay.indexOf(w) >= 0 })) r.push(Object.assign({ kind: "app" }, pcApps[i]))
        }
        return r
    }
    function openAddApp() {
        pcApps = backend.pcApps(); addQuery = ""; panelIdx = 0
        overlay = "addapp"; play("open")
    }
    function addAppPick(row) {
        if (!row) return
        if (row.kind === "file") { doAct("addappfile"); return }
        if (backend.addApp(row.id)) {
            overlay = ""; play("accept")
            toast("Добавлено на главный экран", row.name, "list-add")
            refreshHome(); if (stage === "home") { homeIdx = 1; zone = "row" }
        }
    }

    // панель: профиль / достижения / уведомления / информация
    property int panelIdx: 0
    property var infoData: ({})
    readonly property var trophies: {
        var sec = st.seconds || 0, n = st.launches || 0, dg = st.distinctGames || 0, d = st.distinct || 0
        var t = [
            { name: "Первые шаги",   desc: "Запустите что-нибудь из лаунчера",        tier: 0, got: n >= 1 },
            { name: "Завсегдатай",   desc: "Совершите 10 запусков",                    tier: 0, got: n >= 10 },
            { name: "Исследователь", desc: "Запустите 5 разных приложений или игр",    tier: 0, got: d >= 5 },
            { name: "Марафон",       desc: "Проведите в играх и приложениях 1 час",    tier: 1, got: sec >= 3600 },
            { name: "Коллекционер",  desc: "Сыграйте в 5 разных игр",                  tier: 1, got: dg >= 5 },
            { name: "Ветеран",       desc: "Наберите 10 часов",                        tier: 2, got: sec >= 36000 },
            { name: "Легенда",       desc: "Совершите 100 запусков",                   tier: 2, got: n >= 100 } ]
        var all = t.every(function (x) { return x.got })
        t.push({ name: "Повелитель волн", desc: "Получите все остальные достижения", tier: 3, got: all })
        return t
    }
    // достижения по играм: уровень 0 — список «Общие» + игры, уровень 1 — достижения выбранной игры
    property var achGames: []
    property string achGame: ""          // "" — список; "__tide" — общие; иначе id игры
    property var achData: ({})
    readonly property int achTotalGot: trophies.filter(function (x) { return x.got }).length
                                       + achGames.reduce(function (s, g) { return s + g.got }, 0)
    function refreshAch() { achGames = backend.achievementGames() }
    readonly property var achRows: {
        if (!achGame) {
            var tg = trophies.filter(function (x) { return x.got })
            var r = [{ kind: "game", id: "__tide", name: "Общие (Tide)", icon: "", got: tg.length, total: trophies.length,
                       tiers: [0, 1, 2, 3].map(function (k) { return tg.filter(function (x) { return x.tier === k }).length }) }]
            for (var i = 0; i < achGames.length; i++) r.push(Object.assign({ kind: "game" }, achGames[i]))
            return r
        }
        if (achGame === "__tide") return trophies.map(function (x) { return Object.assign({ kind: "ach" }, x) })
        var out = [{ kind: "hdr", name: "Достижения Tide" }]
        var la = achData.launcher || [], ps = achData.ps4 || []
        for (var j = 0; j < la.length; j++) out.push(Object.assign({ kind: "ach" }, la[j]))
        if (ps.length || achData.note) out.push({ kind: "hdr", name: "Трофеи PS4" + (ps.length ? "  ·  " + ps.filter(function (x) { return x.got }).length + " из " + ps.length : "") })
        for (j = 0; j < ps.length; j++) out.push(Object.assign({ kind: "ach" }, ps[j]))
        if (achData.note) out.push({ kind: "note", name: achData.note })
        return out
    }
    function achOpen(row) {
        if (!row || row.kind !== "game") return
        achGame = row.id
        achData = row.id === "__tide" ? ({}) : backend.gameAchievements(row.id)
        panelIdx = 0; play("accept")
    }
    readonly property var monthsRu: ["января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября", "ноября", "декабря"]
    function achDate(t) { if (!t) return ""; var d = new Date(t * 1000); return d.getDate() + " " + monthsRu[d.getMonth()] + " " + d.getFullYear() }
    readonly property var tierColors: ["#c7864a", "#c9d2dc", "#f0c040", "#b8e4ff"]
    readonly property var tierNames: ["Бронза", "Серебро", "Золото", "Платина"]

    Item {
        id: panel
        anchors.fill: parent
        readonly property bool on: ["profile", "trophies", "notify", "info", "addapp"].indexOf(win.overlay) >= 0
        opacity: on ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 250 } }
        Glass {
            id: pbox
            anchors.centerIn: parent
            width: 1200 * win.s; height: 840 * win.s
            radius: 6 * win.s
            color: "#f007122a"
            scale: panel.on ? 1 : 0.94
            Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

            // профиль
            Item {
                anchors.fill: parent; visible: win.overlay === "profile"
                Avatar { x: 70 * win.s; y: 70 * win.s; width: 220 * win.s; height: width; ci: win.me.color; nm: win.me.name }
                Column {
                    x: 340 * win.s; y: 90 * win.s; spacing: 10 * win.s
                    Text { text: win.me.name; color: "white"; font.pixelSize: 60 * win.s; font.weight: Font.Light }
                    Row {
                        spacing: 12 * win.s
                        Rectangle { width: 16 * win.s; height: width; radius: width / 2; color: "#4ad06a"; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: "В сети"; color: win.txt2; font.pixelSize: 28 * win.s }
                    }
                    Text { text: "Достижений: " + win.achTotalGot; color: win.txt2; font.pixelSize: 26 * win.s }
                }
                Grid {
                    x: 70 * win.s; y: 360 * win.s
                    columns: 3; columnSpacing: 30 * win.s; rowSpacing: 30 * win.s
                    Repeater {
                        model: [["Игры", win.st.games], ["Приложения", win.st.apps], ["Запуски", win.st.launches],
                                ["Общее время", win.st.timeText], ["Любимое", win.st.top], ["Достижения", win.achTotalGot + ""]]
                        Rectangle {
                            width: 333 * win.s; height: 150 * win.s; radius: 4 * win.s
                            color: "#20ffffff"
                            Text { x: 24 * win.s; y: 20 * win.s; text: modelData[0]; color: win.txt2; font.pixelSize: 22 * win.s }
                            Text {
                                x: 24 * win.s; y: 60 * win.s; width: parent.width - 48 * win.s
                                text: "" + modelData[1]; color: "white"; font.pixelSize: 38 * win.s; font.weight: Font.Light
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
            // достижения
            Item {
                anchors.fill: parent; visible: win.overlay === "trophies"
                Text {
                    x: 60 * win.s; y: 44 * win.s; width: parent.width - 520 * win.s; elide: Text.ElideRight
                    text: !win.achGame ? "Достижения" : win.achGame === "__tide" ? "Общие достижения" : (win.achData.name || "")
                    color: "white"; font.pixelSize: 44 * win.s; font.weight: Font.Light
                }
                Row {  // итог по уровням (для выбранной игры — по ней, иначе по всем)
                    anchors { right: parent.right; rightMargin: 60 * win.s; top: parent.top; topMargin: 56 * win.s }
                    spacing: 24 * win.s
                    Repeater {
                        model: 4
                        Row {
                            spacing: 8 * win.s
                            readonly property int n: {
                                var rows = win.achRows, c = 0
                                for (var i = 0; i < rows.length; i++) {
                                    if (rows[i].kind === "game") c += rows[i].tiers ? rows[i].tiers[index] : 0
                                    else if (rows[i].kind === "ach" && rows[i].got && rows[i].tier === index) c++
                                }
                                return c
                            }
                            Rectangle { width: 24 * win.s; height: width; radius: width / 2; color: win.tierColors[index]; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: parent.n; color: "white"; font.pixelSize: 26 * win.s }
                        }
                    }
                }
                ListView {
                    id: achList
                    x: 60 * win.s; y: 130 * win.s
                    width: parent.width - 120 * win.s; height: parent.height - 230 * win.s
                    clip: true; interactive: false
                    model: win.achRows
                    currentIndex: win.panelIdx
                    highlightRangeMode: ListView.ApplyRange
                    preferredHighlightBegin: 0; preferredHighlightEnd: height - 90 * win.s
                    delegate: Item {
                        width: ListView.view.width
                        height: modelData.kind === "hdr" ? 64 * win.s : modelData.kind === "note" ? 70 * win.s : 86 * win.s
                        readonly property bool cur: index === win.panelIdx
                        SelGlow { anchors.fill: parent; visible: parent.cur && modelData.kind !== "hdr" }
                        Rectangle { visible: modelData.kind !== "hdr"; anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#20ffffff" }

                        // заголовок раздела
                        Text {
                            visible: modelData.kind === "hdr"
                            x: 20 * win.s; anchors.bottom: parent.bottom; anchors.bottomMargin: 10 * win.s
                            text: modelData.name; color: win.txt2; font.pixelSize: 24 * win.s; font.weight: Font.DemiBold
                        }
                        // пояснение
                        Text {
                            visible: modelData.kind === "note"
                            x: 20 * win.s; width: parent.width - 40 * win.s; anchors.verticalCenter: parent.verticalCenter
                            text: modelData.name; color: win.txt2; font.pixelSize: 22 * win.s; wrapMode: Text.WordWrap
                        }

                        // строка игры
                        Item {
                            id: gameRow
                            readonly property var row: modelData
                            visible: modelData.kind === "game"
                            anchors.fill: parent
                            Rectangle {
                                x: 14 * win.s; anchors.verticalCenter: parent.verticalCenter
                                width: 64 * win.s; height: width; color: "#30ffffff"; clip: true
                                Image { anchors.fill: parent; visible: !!modelData.icon; source: modelData.icon ? win.icon(modelData.icon) : ""
                                        fillMode: Image.PreserveAspectCrop; sourceSize: Qt.size(128, 128); asynchronous: true }
                                TideMark { visible: !modelData.icon; anchors.centerIn: parent; width: parent.width * 0.7; height: parent.height * 0.5 }
                            }
                            Column {
                                x: 100 * win.s; anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 560 * win.s; spacing: 8 * win.s
                                Text { width: parent.width; text: modelData.name || ""; color: "white"; font.pixelSize: 27 * win.s; elide: Text.ElideRight }
                                Rectangle {  // прогресс
                                    width: parent.width; height: 8 * win.s; radius: height / 2; color: "#30ffffff"
                                    Rectangle { height: parent.height; radius: parent.radius; color: "#6fd6ff"
                                                width: parent.width * (modelData.total ? modelData.got / modelData.total : 0) }
                                }
                            }
                            Row {
                                anchors { right: parent.right; rightMargin: 24 * win.s; verticalCenter: parent.verticalCenter }
                                spacing: 18 * win.s
                                Repeater {
                                    model: 4
                                    Row {
                                        spacing: 6 * win.s
                                        Rectangle { width: 18 * win.s; height: width; radius: width / 2; color: win.tierColors[index]; anchors.verticalCenter: parent.verticalCenter }
                                        Text { text: gameRow.row.tiers ? gameRow.row.tiers[index] : 0; color: "white"; font.pixelSize: 22 * win.s }
                                    }
                                }
                                Text { text: (modelData.got || 0) + " / " + (modelData.total || 0); color: win.txt2; font.pixelSize: 22 * win.s; leftPadding: 10 * win.s }
                            }
                        }

                        // строка достижения
                        Item {
                            visible: modelData.kind === "ach"
                            anchors.fill: parent
                            Rectangle {
                                x: 20 * win.s; anchors.verticalCenter: parent.verticalCenter
                                width: 56 * win.s; height: width; radius: modelData.icon ? 4 * win.s : width / 2
                                color: modelData.got ? win.tierColors[modelData.tier || 0] : "#30ffffff"
                                clip: true
                                Image { anchors.fill: parent; visible: !!modelData.icon; source: modelData.kind === "ach" ? (modelData.icon || "") : ""; sourceSize: Qt.size(112, 112)
                                        opacity: modelData.got ? 1 : 0.35; fillMode: Image.PreserveAspectCrop }
                                Text { visible: !modelData.icon; anchors.centerIn: parent; text: modelData.got ? "★" : "?"
                                       color: modelData.got ? "#3a2a10" : "#90ffffff"; font.pixelSize: 28 * win.s }
                            }
                            Column {
                                x: 100 * win.s; anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 420 * win.s
                                Text { width: parent.width; text: modelData.name || ""; color: modelData.got ? "white" : win.txt2; font.pixelSize: 27 * win.s; elide: Text.ElideRight }
                                Text { width: parent.width; text: modelData.desc || ""; color: win.txt2; font.pixelSize: 20 * win.s; opacity: 0.85; elide: Text.ElideRight }
                            }
                            Column {
                                anchors { right: parent.right; rightMargin: 24 * win.s; verticalCenter: parent.verticalCenter }
                                Text { anchors.right: parent.right; text: win.tierNames[modelData.tier || 0]; color: modelData.got ? win.tierColors[modelData.tier || 0] : win.txt2; font.pixelSize: 22 * win.s }
                                Text { anchors.right: parent.right; visible: !!modelData.got; text: modelData.time ? "получено " + win.achDate(modelData.time) : "получено"
                                       color: win.txt2; font.pixelSize: 19 * win.s }
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: { win.panelIdx = index; if (modelData.kind === "game") win.achOpen(modelData) }
                        }
                    }
                }
            }
            // добавить приложение
            Item {
                anchors.fill: parent; visible: win.overlay === "addapp"
                Text { x: 60 * win.s; y: 44 * win.s; text: "Добавить приложение"; color: "white"; font.pixelSize: 44 * win.s; font.weight: Font.Light }
                Rectangle {  // строка поиска
                    anchors { right: parent.right; rightMargin: 60 * win.s; top: parent.top; topMargin: 48 * win.s }
                    width: 420 * win.s; height: 52 * win.s; radius: height / 2
                    color: win.addQuery ? "#38ffffff" : "#1effffff"; border.color: "#40ffffff"; border.width: 1
                    Row {
                        anchors { left: parent.left; leftMargin: 20 * win.s; verticalCenter: parent.verticalCenter }
                        spacing: 12 * win.s
                        Ico { width: 26 * win.s; height: width; name: "system-search"; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: win.addQuery || "Поиск (□ / F)"; color: win.addQuery ? "white" : win.txt2; font.pixelSize: 24 * win.s
                               width: 330 * win.s; elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter }
                    }
                    MouseArea { anchors.fill: parent; onClicked: win.openKb("Поиск приложения", "addappsearch", win.addQuery) }
                }
                ListView {
                    x: 60 * win.s; y: 130 * win.s
                    width: parent.width - 120 * win.s; height: parent.height - 230 * win.s
                    clip: true; interactive: false
                    model: win.addRows
                    currentIndex: win.panelIdx
                    highlightRangeMode: ListView.ApplyRange
                    preferredHighlightBegin: 0; preferredHighlightEnd: height - 80 * win.s
                    delegate: Item {
                        width: ListView.view.width; height: 78 * win.s
                        readonly property bool cur: index === win.panelIdx
                        SelGlow { anchors.fill: parent; visible: parent.cur }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#20ffffff" }
                        Item {
                            x: 20 * win.s; anchors.verticalCenter: parent.verticalCenter
                            width: 52 * win.s; height: width
                            Image { anchors.fill: parent; visible: modelData.kind === "app"; sourceSize: Qt.size(96, 96)
                                    source: modelData.kind === "app" ? win.icon(modelData.icon) : "" }
                            Ico { anchors.fill: parent; visible: modelData.kind === "file"; name: "document-open" }
                        }
                        Column {
                            x: 96 * win.s; anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 140 * win.s
                            Text { width: parent.width; text: modelData.name; color: "white"; font.pixelSize: 27 * win.s; elide: Text.ElideRight }
                            Text { width: parent.width; visible: !!modelData.comment; text: modelData.comment || ""; color: win.txt2
                                   font.pixelSize: 20 * win.s; elide: Text.ElideRight }
                        }
                        MouseArea { anchors.fill: parent; onClicked: { win.panelIdx = index; win.addAppPick(modelData) } }
                    }
                }
                Text {
                    visible: win.addRows.length <= 1
                    x: 60 * win.s; y: 230 * win.s; width: parent.width - 120 * win.s; wrapMode: Text.WordWrap
                    text: win.addQuery ? "Ничего не найдено по запросу «" + win.addQuery + "»" : "Все найденные приложения уже добавлены"
                    color: win.txt2; font.pixelSize: 26 * win.s
                }
            }
            // уведомления
            Item {
                anchors.fill: parent; visible: win.overlay === "notify"
                Text { x: 60 * win.s; y: 44 * win.s; text: "Уведомления"; color: "white"; font.pixelSize: 44 * win.s; font.weight: Font.Light }
                Text {
                    visible: !win.activity.length
                    anchors.centerIn: parent
                    text: "Уведомлений нет"; color: win.txt2; font.pixelSize: 30 * win.s
                }
                ListView {
                    x: 60 * win.s; y: 130 * win.s
                    width: parent.width - 120 * win.s; height: parent.height - 230 * win.s
                    clip: true; interactive: false
                    model: win.activity
                    currentIndex: win.panelIdx
                    highlightRangeMode: ListView.ApplyRange
                    preferredHighlightBegin: 0; preferredHighlightEnd: height - 90 * win.s
                    delegate: Item {
                        width: ListView.view.width; height: 88 * win.s
                        readonly property bool cur: index === win.panelIdx
                        SelGlow { anchors.fill: parent; visible: parent.cur }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#20ffffff" }
                        Image { x: 20 * win.s; anchors.verticalCenter: parent.verticalCenter; width: 56 * win.s; height: width; sourceSize: Qt.size(96, 96); source: win.icon(modelData.icon) }
                        Column {
                            x: 100 * win.s; anchors.verticalCenter: parent.verticalCenter
                            Text { text: (modelData.isGame ? "Вы играли в " : "Вы запускали ") + modelData.name; color: "white"; font.pixelSize: 26 * win.s }
                            Text { text: modelData.when + (modelData.timeText !== "—" ? "  ·  всего " + modelData.timeText : ""); color: win.txt2; font.pixelSize: 21 * win.s }
                        }
                        Text {
                            visible: parent.cur
                            anchors { right: parent.right; rightMargin: 24 * win.s; verticalCenter: parent.verticalCenter }
                            text: "✕  Запустить"; color: "white"; font.pixelSize: 22 * win.s
                        }
                    }
                }
            }
            // информация
            Item {
                anchors.fill: parent; visible: win.overlay === "info"
                Tile {
                    x: 60 * win.s; y: 60 * win.s; width: 260 * win.s; height: width
                    it: win.menuTarget
                }
                Column {
                    x: 360 * win.s; y: 70 * win.s; width: parent.width - 420 * win.s
                    spacing: 10 * win.s
                    Text { width: parent.width; text: win.infoData.name || ""; color: "white"; font.pixelSize: 48 * win.s; font.weight: Font.Light; elide: Text.ElideRight }
                    Text { width: parent.width; text: win.menuTarget ? (win.menuTarget.comment || "") : ""; color: win.txt2; font.pixelSize: 24 * win.s; wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight }
                }
                Column {
                    x: 60 * win.s; y: 380 * win.s; width: parent.width - 120 * win.s
                    Repeater {
                        model: [["Раздел", win.menuTarget && win.menuTarget.isGame ? "Игры" : "Приложения"],
                                ["Последний запуск", (win.infoData.last || "").replace("Последний запуск: ", "")],
                                ["Количество запусков", "" + (win.infoData.count || 0)],
                                ["Время использования", win.infoData.time || "—"],
                                ["Идентификатор", win.infoData.id || ""],
                                ["Команда", win.infoData.cmd || ""]]
                        Item {
                            width: parent.width; height: 62 * win.s
                            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#20ffffff" }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: modelData[0]; color: win.txt2; font.pixelSize: 24 * win.s }
                            Text {
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                width: parent.width * 0.6; horizontalAlignment: Text.AlignRight
                                text: modelData[1]; color: "white"; font.pixelSize: 24 * win.s; elide: Text.ElideMiddle
                            }
                        }
                    }
                }
            }
            Row {
                anchors { right: parent.right; bottom: parent.bottom; margins: 30 * win.s }
                spacing: 30 * win.s
                Hint { btn: "cross"; label: "Открыть"; visible: win.overlay === "trophies" && !win.achGame }
                Hint { btn: "cross"; label: "Добавить"; visible: win.overlay === "addapp" }
                Hint { btn: "square"; label: "Поиск"; visible: win.overlay === "addapp" }
                Hint { btn: "circle"; label: win.overlay === "trophies" && win.achGame ? "К списку игр" : "Закрыть" }
            }
        }
    }

    // экранная клавиатура
    property string kbTitle: ""
    property string kbTarget: ""
    property int kbRow: 4
    property int kbCol: 3
    property bool kbLatin: false
    readonly property var kbRowsCyr: ["1234567890", "йцукенгшщзх", "фывапролджэ", "ячсмитьбю-"]
    readonly property var kbRowsLat: ["1234567890", "qwertyuiop", "asdfghjkl/", "zxcvbnm._-"]
    readonly property var kbSpecial: ["Aa", "RU/EN", "Пробел", "⌫", "Готово"]
    property bool kbShift: true
    function openKb(title, target, initial) {
        kbTitle = title; kbTarget = target
        kbInput.text = initial || ""
        kbRow = 4; kbCol = 4; kbShift = !initial
        overlay = "kb"; play("open")
        kbInput.forceActiveFocus()
    }
    function kbKeys(r) {
        if (r === 4) return kbSpecial
        var row = (kbLatin ? kbRowsLat : kbRowsCyr)[r]
        return row.split("")
    }
    function kbPress() {
        var k = kbKeys(kbRow)[kbCol]
        if (kbRow === 4) {
            if (k === "Aa") kbShift = !kbShift
            else if (k === "RU/EN") kbLatin = !kbLatin
            else if (k === "Пробел") kbInput.insert(kbInput.cursorPosition, " ")
            else if (k === "⌫") { if (kbInput.cursorPosition > 0) kbInput.remove(kbInput.cursorPosition - 1, kbInput.cursorPosition) }
            else kbDone()
        } else {
            kbInput.insert(kbInput.cursorPosition, kbShift ? k.toUpperCase() : k)
            if (kbShift) kbShift = false
        }
        play("move")
    }
    function kbDone() {
        var name = kbInput.text.trim()
        overlay = ""
        keyCatcher.forceActiveFocus()
        if (kbTarget === "addappsearch") {
            addQuery = name; panelIdx = 0; overlay = "addapp"; play("accept"); return
        }
        if (kbTarget === "storesearch") {
            storeQuery = name; storeIdx = 0
            storeZone = storeModel.length ? "grid" : "side"
            play(name ? "accept" : "back")
            if (name && !storeModel.length) toast("Ничего не найдено", name, "system-search")
            return
        }
        if (!name) { play("back"); return }
        play("accept")
        if (kbTarget === "newuser" || kbTarget === "newuser-login") {
            var i = backend.addUser(name, users.length % 8)
            users = backend.users()
            if (kbTarget === "newuser-login") userIdx = i
            toast("Пользователь создан", name, "user-identity")
        } else if (kbTarget === "addappfile") {
            if (backend.addAppFile(name)) {
                toast("Добавлено на главный экран", name.replace(/^.*\//, ""), "list-add"); refreshHome(); if (stage === "home") { homeIdx = 1; zone = "row" }
            } else toast("Не удалось добавить", "Файл не найден или не запускается: " + name, "dialog-error")
        } else if (kbTarget === "storesrc") {
            if (backend.addStoreSource(name)) { storeBusy = true; refreshStore(); toast("Источник добавлен", name, "download") }
            else toast("Не удалось добавить", "Файл не найден: " + name, "dialog-error")
        } else if (kbTarget === "ps4add") {
            if (backend.addPs4Dir(name)) { refreshPs4(); refreshHome(); toast("Папка добавлена", ps4.games + " игр PS4", "folder") }
            else toast("Папка не найдена", name, "dialog-error")
        } else if (kbTarget === "pkgtool") {
            setCfg("pkgExtractor", name); refreshPs4()
            toast(ps4.pkgTool ? "Распаковщик подключён" : "Файл не найден", name, ps4.pkgTool ? "package-x-generic" : "dialog-error")
        } else if (kbTarget === "ps4emu") {
            setCfg("ps4Emu", name); backend.rescan(); refreshPs4(); refreshHome()
            toast(ps4.found ? "Эмулятор подключён" : "Файл не найден", name, ps4.found ? "input-gaming" : "dialog-error")
        } else if (kbTarget.indexOf("rename:") === 0) {
            backend.renameUser(+kbTarget.split(":")[1], name)
            users = backend.users()
        }
    }

    Item {
        id: kbPanel
        anchors.fill: parent
        opacity: win.overlay === "kb" ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 220 } }
        Glass {
            anchors.horizontalCenter: parent.horizontalCenter
            y: (win.overlay === "kb" ? 150 : 210) * win.s
            Behavior on y { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
            width: 1240 * win.s; height: 790 * win.s; radius: 6 * win.s
            color: "#f207122a"
            Text { x: 50 * win.s; y: 36 * win.s; text: win.kbTitle; color: "white"; font.pixelSize: 36 * win.s; font.weight: Font.Light }
            Rectangle {
                x: 50 * win.s; y: 100 * win.s; width: parent.width - 100 * win.s; height: 76 * win.s
                color: "white"; radius: 3 * win.s
                TextInput {
                    id: kbInput
                    anchors { fill: parent; leftMargin: 20 * win.s; rightMargin: 20 * win.s }
                    verticalAlignment: TextInput.AlignVCenter
                    font.pixelSize: 34 * win.s; color: "#0a1a33"
                    maximumLength: win.kbTarget === "newuser" || win.kbTarget === "newuser-login" || win.kbTarget.indexOf("rename:") === 0 ? 24 : 1024
                    cursorVisible: true
                    selectByMouse: true
                    onTextEdited: { win.kbRow = 4; win.kbCol = 4 }
                    onTextChanged: {
                        if (win.overlay !== "kb") return
                        if (win.kbTarget === "storesearch") { win.storeQuery = text.trim(); win.storeIdx = 0 }
                        else if (win.kbTarget === "addappsearch") { win.addQuery = text.trim(); win.panelIdx = 0 }
                    }
                    Keys.priority: Keys.BeforeItem
                    Keys.onPressed: function (e) {
                        var a = win.keyAction(e)
                        if (["up", "down", "left", "right", "accept", "back", "triangle"].indexOf(a) >= 0) {
                            win.handle(a); e.accepted = true
                        }
                    }
                }
            }
            Column {
                x: 50 * win.s; y: 210 * win.s
                spacing: 10 * win.s
                Repeater {
                    model: 5
                    Row {
                        id: kr
                        readonly property int r: index
                        readonly property var keys: { win.kbLatin; return win.kbKeys(index) }
                        spacing: 10 * win.s
                        Repeater {
                            model: kr.keys
                            Rectangle {
                                readonly property bool cur: win.kbRow === kr.r && win.kbCol === index
                                readonly property bool wide: kr.r === 4
                                width: wide ? (modelData === "Пробел" ? 400 : 172) * win.s : 94 * win.s
                                height: 80 * win.s; radius: 4 * win.s
                                color: cur ? "white" : (modelData === "Готово" ? "#2f6fd0" : "#30ffffff")
                                Text {
                                    anchors.centerIn: parent
                                    text: kr.r < 4 && win.kbShift ? modelData.toUpperCase() : modelData
                                    color: parent.cur ? "#0a1a33" : "white"; font.pixelSize: 30 * win.s
                                }
                                MouseArea { anchors.fill: parent; onClicked: { win.kbRow = kr.r; win.kbCol = index; win.kbPress() } }
                            }
                        }
                    }
                }
            }
            Row {
                anchors { right: parent.right; bottom: parent.bottom; margins: 26 * win.s }
                spacing: 30 * win.s
                Hint { btn: "cross"; label: "Ввод" }
                Hint { btn: "triangle"; label: "Пробел" }
                Hint { btn: "circle"; label: "Отмена" }
            }
        }
    }

    // запуск приложения
    property var launchIt: null
    property real launchT: 0
    Item {
        anchors.fill: parent
        visible: win.overlay === "launch"
        Rectangle { anchors.fill: parent; color: Qt.darker(win.accentOf(win.launchIt), 1.6); opacity: win.launchT }
        Tile {
            anchors.centerIn: parent
            width: 300 * win.s; height: width
            it: win.launchIt
            scale: 0.8 + win.launchT * 0.5
            opacity: Math.min(1, win.launchT * 2)
        }
        Column {
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.verticalCenter; topMargin: 260 * win.s }
            spacing: 12 * win.s
            opacity: win.launchT
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: win.launchIt ? win.launchIt.name : ""; color: "white"; font.pixelSize: 44 * win.s; font.weight: Font.Light }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 14 * win.s
                Repeater {
                    model: 3
                    Rectangle {
                        width: 12 * win.s; height: width; radius: width / 2; color: "white"
                        opacity: 0.3 + 0.7 * Math.max(0, Math.sin((win.launchT * 6 - index * 0.6) * 3.14159))
                    }
                }
            }
        }
    }
    SequentialAnimation {
        id: launchAnim
        NumberAnimation { target: win; property: "launchT"; from: 0; to: 1; duration: 900; easing.type: Easing.OutCubic }
        ScriptAction {
            script: {
                var ok = backend.launch(win.launchIt.id)
                if (!ok) { win.overlay = ""; win.toast("Не удалось запустить", win.launchIt.name, "dialog-error") }
            }
        }
        PauseAnimation { duration: 1400 }
        ScriptAction {
            script: {
                if (win.overlay === "launch") {
                    win.overlay = ""
                    win.refreshHome()
                    win.showMinimized()
                }
            }
        }
    }
    function launchItem(it) {
        if (!it || it.special) return
        launchIt = it; launchT = 0
        overlay = "launch"; play("launch")
        launchAnim.restart()
    }

    // всплывающее уведомление (слева сверху)
    property var toastData: ({ title: "", text: "", sym: "" })
    property bool toastOn: false
    property var toastQueue: []
    function toast(title, text, symName) {
        if (toastOn && toastTimer.running && toastData.queued) {   // идёт уведомление о достижении — встаём в очередь
            toastQueue = toastQueue.concat([{ title: title, text: text || "", sym: symName || "notifications" }]); return
        }
        toastData = { title: title, text: text || "", sym: symName || "notifications" }
        toastOn = true; toastTimer.restart()
    }
    function toastAch(title, text) {
        var t = { title: title, text: text, sym: "games-achievements", queued: true }
        if (toastOn && toastTimer.running) { toastQueue = toastQueue.concat([t]); return }
        toastData = t; toastOn = true; toastTimer.restart()
    }
    Timer {
        id: toastTimer; interval: 4200
        onTriggered: {
            if (win.toastQueue.length) {
                win.toastData = win.toastQueue[0]; win.toastQueue = win.toastQueue.slice(1); restart()
            } else win.toastOn = false
        }
    }
    Glass {
        x: win.toastOn ? 40 * win.s : -width - 40
        y: 40 * win.s
        width: 560 * win.s; height: 110 * win.s; radius: 6 * win.s
        color: "#f00a1a36"
        Behavior on x { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
        Ico { x: 24 * win.s; anchors.verticalCenter: parent.verticalCenter; width: 48 * win.s; height: width; name: win.toastData.sym || "" }
        Column {
            x: 96 * win.s; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 120 * win.s
            Text { width: parent.width; text: win.toastData.title; color: "white"; font.pixelSize: 26 * win.s; elide: Text.ElideRight }
            Text { width: parent.width; text: win.toastData.text; color: win.txt2; font.pixelSize: 22 * win.s; elide: Text.ElideRight; visible: text !== "" }
        }
    }

    // ───────────────────────── логика ─────────────────────────
    function goHome() {
        if (stage !== "home") { stage = "home"; zone = "row"; play("back") }
        refreshHome()
    }
    function login() {
        if (userIdx >= users.length) { openKb("Имя нового пользователя", "newuser-login", ""); return }
        curUser = userIdx
        setCfg("lastUser", userIdx)
        refreshHome()
        homeIdx = Math.min(1, homeModel.length - 1); zone = "row"; homeIntro = 0
        stage = "welcome"; play("login")
        loginT = 0; loginAnim.restart()
    }
    function enterHome() {
        stage = "home"; homeIntro = 0; homeIntroAnim.restart()
        toast(me.name, "Вход выполнен", "user-identity")
    }
    function logout() {
        overlay = ""; userIdx = curUser
        users = backend.users()
        stage = "users"; play("back")
    }

    function doAct(act, it) {
        var p = act.split(":")
        switch (p[0]) {
        case "launch":
            var target = null, all = backend.allItems()
            for (var i = 0; i < all.length; i++) if (all[i].id === act.substring(7)) target = all[i]
            overlay = ""
            launchItem(target); return
        case "lib": openLibrary(+p[1]); return
        case "info":
            menuTarget = it; infoData = backend.appInfo(it.id); overlay = "info"; play("open"); return
        case "togglegame":
            backend.toggleGame(it.id); overlay = ""; play("accept")
            toast(it.isGame ? "Перенесено в приложения" : "Отмечено как игра", it.name, "applications-games")
            refreshHome(); if (stage === "library") refreshLib(); return
        case "addapp": openAddApp(); return
        case "addappfile": openKb("Путь к программе (AppImage, скрипт, файл)", "addappfile", "~/"); kbLatin = true; return
        case "unpin":
            backend.removeApp(it.id); overlay = ""; play("accept")
            toast("Убрано с главного экрана", it.name, "edit-delete")
            refreshHome(); if (stage === "library") refreshLib(); return
        case "hide":
            backend.hide(it.id); overlay = ""; play("accept")
            toast("Скрыто", it.name + " — вернуть: Настройки › Библиотека", "edit-delete")
            refreshHome(); if (stage === "library") refreshLib()
            if (zone === "info") zone = "row"; return
        case "close": backend.closeApp(act.substring(6)); overlay = ""; play("accept"); toast("Приложение закрыто", "", "window-close"); return
        case "home": overlay = ""; goHome(); return
        case "library": overlay = ""; openLibrary(0); return
        case "store": openStore(); return
        case "settings": overlay = ""; openSettings(); return
        case "logout": logout(); return
        case "powermenu": openPower(); return
        case "power":
            overlay = ""
            if (p[1] === "quit") { backend.power("quit"); return }
            toast(p[1] === "suspend" ? "Переход в режим покоя…" : p[1] === "reboot" ? "Перезагрузка…" : "Выключение…", "", "system-shutdown")
            Qt.callLater(function () { backend.power(p[1]) }); return
        case "volume": return
        case "mute": backend.setSys("muted", !sysSt.muted); refreshSys(); play("accept"); return
        case "set": setCfg(p[1], !cfg[p[1]]); play("accept"); return
        case "cfgval": setCfg(p[1], p.slice(2).join(":")); play("accept"); return
        case "theme": setCfg("theme", p[1]); play("accept"); return
        case "sink": backend.setSys("sink", act.substring(5)); refreshSys(); play("accept"); return
        case "fullscreen": if (visibility === Window.FullScreen) showNormal(); else showFullScreen(); play("accept"); return
        case "adduser": openKb("Имя нового пользователя", "newuser", ""); return
        case "rename": openKb("Имя пользователя", act, users[+p[1]].name); return
        case "deluser":
            var di = +p[1]
            backend.removeUser(di); users = backend.users()
            if (curUser >= users.length) curUser = users.length - 1
            else if (di < curUser) curUser--
            setPop(); toast("Пользователь удалён", "", "edit-delete"); return
        case "ucolor": backend.setUserColor(+p[1], +p[2]); users = backend.users(); play("accept"); return
        case "rescan": backend.rescan(); refreshPs4(); accCache = ({}); refreshHome(); st = backend.stats(); toast("Список обновлён", st.games + " игр, " + st.apps + " приложений", "view-refresh"); play("accept"); return
        case "unhide": backend.unhideAll(); refreshHome(); st = backend.stats(); toast("Скрытые элементы возвращены", "", "edit-undo"); play("accept"); return
        case "pkgtool": openKb("Путь к распаковщику PKG (AppImage)", "pkgtool", cfg.pkgExtractor || ps4.pkgTool || "~/"); kbLatin = true; return
        case "ps4emu": openKb("Путь к shadPS4 (AppImage)", "ps4emu", cfg.ps4Emu || ps4.emu || "~/"); kbLatin = true; return
        case "ps4add": openKb("Папка с играми PS4", "ps4add", "~/"); kbLatin = true; return
        case "ps4del":
            backend.removePs4Dir(ps4.dirs[+p[1]]); refreshPs4(); refreshHome()
            toast("Папка удалена", "", "folder"); play("accept"); return
        case "nettest": netResult = "Проверка…"; backend.testNetwork(); play("accept"); return
        }
    }
    function changeVolume(d) {
        var v = Math.max(0, Math.min(100, sysSt.volume + d))
        backend.setSys("volume", v)
        if (sysSt.muted && d > 0) backend.setSys("muted", false)
        refreshSys(); play("move")
        if (overlay === "quick") qRefresh()
    }

    function handle(a) {
        if (a === "fullscreen") { doAct("fullscreen"); return }
        if (stage === "boot") { bootFinish(); return }
        if (stage === "press") { if (a === "accept" || a === "ps") { stage = "users"; play("accept") } return }
        if (stage === "welcome" || overlay === "launch") return
        if (overlay !== "") { overlayHandle(a); return }
        if (a === "quick") { openQuick(); return }
        if (a === "ps") { if (stage === "home") openQuick(); else if (stage !== "users") goHome(); return }
        switch (stage) {
        case "users": usersHandle(a); break
        case "home": homeHandle(a); break
        case "library": libHandle(a); break
        case "store": storeHandle(a); break
        case "settings": setHandle(a); break
        }
    }
    function usersHandle(a) {
        var n = users.length + 1
        if (a === "left" && userIdx > 0) { userIdx--; play("move") }
        else if (a === "right" && userIdx < n - 1) { userIdx++; play("move") }
        else if (a === "accept") login()
        else if (a === "triangle" && userIdx < users.length && users.length > 1) {
            backend.removeUser(userIdx); users = backend.users()
            if (userIdx > users.length) userIdx = users.length
            play("back")
        }
    }
    function homeHandle(a) {
        var it = curItem
        if (zone === "row") {
            if (a === "left" && homeIdx > 0) { homeIdx--; infoIdx = 0; play("move") }
            else if (a === "right" && homeIdx < homeModel.length - 1) { homeIdx++; infoIdx = 0; play("move") }
            else if (a === "up") { zone = "func"; play("move") }
            else if (a === "down" && cards.length) { zone = "info"; infoIdx = 0; play("move") }
            else if (a === "accept") {
                if (!it) return
                if (it.id === "__new") { zone = "info"; infoIdx = 0; play("accept") }
                else if (it.id === "__lib") openLibrary(0)
                else if (it.id === "__store") openStore()
                else launchItem(it)
            }
            else if (a === "options") openOptions(it)
            else if (a === "triangle") openLibrary(0)
        } else if (zone === "func") {
            if (a === "left" && funcIdx > 0) { funcIdx--; play("move") }
            else if (a === "right" && funcIdx < funcItems.length - 1) { funcIdx++; play("move") }
            else if (a === "down" || a === "back") { zone = "row"; play("move") }
            else if (a === "accept") funcOpen(funcItems[funcIdx].key)
        } else if (zone === "info") {
            if (a === "left" && infoIdx % 3 > 0) { infoIdx--; play("move") }
            else if (a === "right" && infoIdx % 3 < 2 && infoIdx < cards.length - 1) { infoIdx++; play("move") }
            else if (a === "down" && infoIdx + 3 < cards.length) { infoIdx += 3; play("move") }
            else if (a === "up" && infoIdx >= 3) { infoIdx -= 3; play("move") }
            else if (a === "up" || a === "back") { zone = "row"; play("move") }
            else if (a === "accept" && cards[infoIdx] && cards[infoIdx].act) doAct(cards[infoIdx].act, it)
            else if (a === "options") openOptions(it)
        }
    }
    function funcOpen(k) {
        panelIdx = 0
        st = backend.stats(); activity = backend.activity()
        if (k === "trophies") { achGame = ""; achData = ({}); refreshAch() }
        if (k === "notify" || k === "profile" || k === "trophies") { overlay = k; play("open") }
        else if (k === "library") openLibrary(0)
        else if (k === "store") openStore()
        else if (k === "settings") openSettings()
        else if (k === "power") openPower()
    }
    function libHandle(a) {
        var cols = libGrid.cols
        if (libZone === "side") {
            if (a === "up" && libCat > 0) { libCat--; libIdx = 0; refreshLib(); play("move") }
            else if (a === "down" && libCat < libCats.length - 1) { libCat++; libIdx = 0; refreshLib(); play("move") }
            else if ((a === "right" || a === "accept") && libModel.length) { libZone = "grid"; play("move") }
            else if (a === "back") goHome()
        } else {
            if (a === "left") { if (libIdx % cols === 0) libZone = "side"; else libIdx--; play("move") }
            else if (a === "right" && libIdx < libModel.length - 1 && libIdx % cols !== cols - 1) { libIdx++; play("move") }
            else if (a === "up" && libIdx - cols >= 0) { libIdx -= cols; play("move") }
            else if (a === "down" && libIdx + cols < libModel.length) { libIdx += cols; play("move") }
            else if (a === "down" && Math.floor(libIdx / cols) < Math.floor((libModel.length - 1) / cols)) { libIdx = libModel.length - 1; play("move") }
            else if (a === "accept") launchItem(libModel[libIdx])
            else if (a === "options") openOptions(libModel[libIdx])
            else if (a === "back") goHome()
            else if (a === "tabnext") { libCat = (libCat + 1) % 3; libIdx = 0; refreshLib() }
            else if (a === "tabprev") { libCat = (libCat + 2) % 3; libIdx = 0; refreshLib() }
        }
    }
    function setHandle(a) {
        var rows = setRows, r = rows[setIdx]
        if (a === "up" && setIdx > 0) { setIdx--; play("move") }
        else if (a === "down" && setIdx < rows.length - 1) { setIdx++; play("move") }
        else if (a === "back") setPop()
        else if (r && r.t === "slider" && (a === "left" || a === "right")) changeVolume(a === "left" ? -5 : 5)
        else if (a === "accept" && r) {
            if (r.t === "nav") setPush(r.to)
            else if (r.act) {
                doAct(r.act)
                if (r.t === "radio" && setTop.page === "sink") {}
            }
        }
    }
    function overlayHandle(a) {
        if (overlay === "quick") {
            var q = qItems[qIdx]
            if (a === "up" && qIdx > 0) { qIdx--; play("move") }
            else if (a === "down" && qIdx < qItems.length - 1) { qIdx++; play("move") }
            else if (q && q.t === "slider" && (a === "left" || a === "right")) changeVolume(a === "left" ? -5 : 5)
            else if (a === "back" || a === "left") qPop()
            else if (a === "ps" || a === "quick") { overlay = ""; play("back") }
            else if ((a === "accept" || a === "right") && q) {
                if (q.t === "nav") qPush(q.to)
                else if (a === "accept" && q.act && q.act !== "volume") {
                    if (q.act === "notify") { overlay = ""; funcOpen("notify"); return }
                    doAct(q.act)
                    if (overlay === "quick") qRefresh()
                }
            }
            return
        }
        if (overlay === "menu") {
            var r = menuItems[menuIdx]
            if (a === "up" && menuIdx > 0) { menuIdx--; play("move") }
            else if (a === "down" && menuIdx < menuItems.length - 1) { menuIdx++; play("move") }
            else if (r && r.t === "slider" && (a === "left" || a === "right")) changeVolume(a === "left" ? -5 : 5)
            else if (a === "back" || (a === "options" && menuKind === "options") || ((a === "ps" || a === "quick") && menuKind === "quick")) { overlay = ""; play("back") }
            else if (a === "accept" && r && r.act) doAct(r.act, menuTarget)
        } else if (overlay === "kb") {
            var keys = kbKeys(kbRow)
            if (a === "left") { kbCol = (kbCol + keys.length - 1) % keys.length; play("move") }
            else if (a === "right") { kbCol = (kbCol + 1) % keys.length; play("move") }
            else if (a === "up" || a === "down") {
                var frac = (kbCol + 0.5) / keys.length
                kbRow = a === "up" ? (kbRow + 4) % 5 : (kbRow + 1) % 5
                kbCol = Math.min(kbKeys(kbRow).length - 1, Math.floor(frac * kbKeys(kbRow).length))
                play("move")
            }
            else if (a === "accept") kbPress()
            else if (a === "triangle") kbInput.insert(kbInput.cursorPosition, " ")
            else if (a === "back") {
                if (kbTarget === "storesearch") storeQuery = storeQueryPrev
                if (kbTarget === "addappsearch") { overlay = "addapp"; keyCatcher.forceActiveFocus(); play("back"); return }
                overlay = ""; keyCatcher.forceActiveFocus(); play("back")
            }
        } else {
            var list = overlay === "trophies" ? achRows : overlay === "notify" ? activity : overlay === "addapp" ? addRows : []
            if (overlay === "addapp") {
                if (a === "accept") { addAppPick(list[panelIdx]); return }
                if (a === "square") { openKb("Поиск приложения", "addappsearch", addQuery); return }
                if (a === "back" && addQuery) { addQuery = ""; panelIdx = 0; play("back"); return }
            }
            if (overlay === "trophies") {
                // заголовки разделов пропускаем
                if (a === "up" || a === "down") {
                    var k = panelIdx, step = a === "up" ? -1 : 1
                    do { k += step } while (k >= 0 && k < list.length && list[k].kind === "hdr")
                    if (k >= 0 && k < list.length) { panelIdx = k; play("move") }
                    return
                }
                if (a === "accept" && !achGame) { achOpen(list[panelIdx]); return }
                if (a === "back" && achGame) {
                    var prev = achGame; achGame = ""; achData = ({}); refreshAch()
                    panelIdx = 0
                    for (var q = 0; q < achRows.length; q++) if (achRows[q].id === prev) panelIdx = q
                    play("back"); return
                }
            }
            if (a === "up" && panelIdx > 0) { panelIdx--; play("move") }
            else if (a === "down" && panelIdx < list.length - 1) { panelIdx++; play("move") }
            else if (a === "accept" && overlay === "notify" && activity[panelIdx]) doAct("launch:" + activity[panelIdx].id)
            else if (a === "back" || a === "ps") { overlay = ""; play("back") }
        }
    }

    function keyAction(e) {
        switch (e.key) {
        case Qt.Key_Left: return "left"
        case Qt.Key_Right: return "right"
        case Qt.Key_Up: return "up"
        case Qt.Key_Down: return "down"
        case Qt.Key_Return: case Qt.Key_Enter: return "accept"
        case Qt.Key_Space: return overlay === "kb" ? "" : "accept"
        case Qt.Key_Escape: return "back"
        case Qt.Key_Backspace: return overlay === "kb" ? "" : "back"
        case Qt.Key_Home: case Qt.Key_F1: return "ps"
        case Qt.Key_Q: return overlay === "kb" ? "" : "quick"
        case Qt.Key_Menu: case Qt.Key_F2: case Qt.Key_Tab: return "options"
        case Qt.Key_O: return overlay === "kb" ? "" : "options"
        case Qt.Key_T: case Qt.Key_Delete: return overlay === "kb" ? "" : "triangle"
        case Qt.Key_F: case Qt.Key_Slash: case Qt.Key_S: return overlay === "kb" ? "" : "square"
        case Qt.Key_PageDown: return "tabnext"
        case Qt.Key_PageUp: return "tabprev"
        case Qt.Key_F11: return "fullscreen"
        }
        return ""
    }

    Item {
        id: keyCatcher
        focus: true
        Keys.onPressed: function (e) {
            var a = win.keyAction(e)
            if (a) { win.handle(a); e.accepted = true }
        }
    }
    Connections {
        target: backend
        function onPadInput(a) {
            if (win.visibility === Window.Minimized) {
                if (a === "ps") { if (backend.windowed) win.showNormal(); else win.showFullScreen(); win.raise(); win.requestActivate() }
                return
            }
            win.handle(a)
        }
        function onAppFinished() {
            if (backend.windowed) win.showNormal(); else win.showFullScreen()
            win.raise(); win.requestActivate()
            win.refreshHome()
            win.toast("С возвращением", "", "go-home")
        }
        function onNetTested(r) { win.netResult = r }
        function onAchievementUnlocked(name, game, tier) {
            win.toastAch("Достижение получено · " + win.tierNames[tier], name + (game ? "  —  " + game : ""))
            win.refreshAch()
        }
        function onStoreLoaded() {
            win.refreshStore()
            if (win.stage === "store" && win.storeZone === "side" && win.storeCat < 3 && win.storeModel.length) win.storeZone = "grid"
        }
        function onStoreProgress(id, frac, text) {
            var j = Object.assign({}, win.storeJobs); j[id] = { busy: true, frac: frac, text: text }; win.storeJobs = j
        }
        function onStoreDone(id, ok, msg) {
            var j = Object.assign({}, win.storeJobs); delete j[id]; win.storeJobs = j
            var t = ""; for (var i = 0; i < win.storeAll.length; i++) if (win.storeAll[i].id === id) t = win.storeAll[i].title
            if (ok) { backend.rescan(); win.refreshPs4(); win.accCache = ({}); win.refreshHome(); win.toast("Игра установлена", t, "download"); win.play("accept") }
            else { win.toast("Ошибка установки", msg, "dialog-error"); win.play("back") }
            win.refreshStore()
        }
    }

    // ───────────────────────── старт ─────────────────────────
    Component.onCompleted: {
        curUser = Math.min(cfg.lastUser || 0, users.length - 1)
        userIdx = curUser
        refreshSys()
        refreshHome()
        var dp = backend.debugPage
        if (dp) {
            stage = "home"; homeIntro = 1
            if (dp === "boot") { stage = "boot"; bootStart(); return }
            if (dp === "press") stage = "press"
            else if (dp === "users") stage = "users"
            else if (dp === "welcome") { stage = "welcome"; loginT = 0.35 }
            else if (dp === "func") zone = "func"
            else if (dp === "info") zone = "info"
            else if (dp === "new") { homeIdx = 0; zone = "row" }
            else if (dp === "library") openLibrary(0)
            else if (dp === "store") openStore()
            else if (dp === "settings") openSettings()
            else if (dp === "settings2") { openSettings(); setPush("sound") }
            else if (dp === "theme") { openSettings(); setPush("theme") }
            else if (dp === "system") { openSettings(); setPush("system") }
            else if (dp === "quick") openQuick()
            else if (dp === "quickpower") { openQuick(); qPush("power") }
            else if (dp === "quicksound") { openQuick(); qPush("sound") }
            else if (dp === "options") openOptions(curItem)
            else if (dp === "power") openPower()
            else if (dp === "kb") openKb("Имя нового пользователя", "newuser", "")
            else if (dp === "launch") launchIt = curItem, overlay = "launch", launchT = 0.8
            else funcOpen(dp)
            return
        }
        if (backend.skipIntro) { stage = "home"; homeIntro = 1; return }
        if (cfg.intro) { stage = "boot"; bootDelay.start() }
        else stage = "users"
    }
    property var dbgKeys: backend.debugKeys ? backend.debugKeys.split(",") : []
    Timer {
        interval: 450; repeat: true; running: win.dbgKeys.length > 0
        onTriggered: { var k = win.dbgKeys.shift(); if (k === "wait") return; win.handle(k); if (!win.dbgKeys.length) stop() }
    }
    Timer { id: bootDelay; interval: 300; onTriggered: win.bootStart() }
}

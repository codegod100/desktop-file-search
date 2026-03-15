from __future__ import annotations

import os
import shlex
import shutil
import subprocess
import sys
import threading
from pathlib import Path

from PySide6.QtCore import Property, QAbstractListModel, QByteArray, QEvent, QModelIndex, QObject, Qt, QUrl, Signal, Slot, QSize
from PySide6.QtGui import QColor, QDesktopServices, QGuiApplication, QIcon, QImage, QPainter, QWheelEvent
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickImageProvider
from PySide6.QtQuickControls2 import QQuickStyle
from PySide6.QtWidgets import QApplication, QFileDialog


STANDARD_PATHS = (
    Path("/usr/share/applications"),
    Path("/usr/local/share/applications"),
    Path("/var/lib/flatpak/exports/share/applications"),
)

HOME_APPLICATIONS = Path.home() / ".local/share/applications"
PLACEHOLDER_ICON = "application-x-executable"


def _run_command(*argv: str) -> subprocess.CompletedProcess[str] | None:
    try:
        return subprocess.run(
            argv,
            check=False,
            capture_output=True,
            text=True,
        )
    except (FileNotFoundError, OSError):
        return None


def parse_desktop_file(path: Path) -> dict[str, object] | None:
    try:
        content = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None

    in_desktop_entry = False
    fields: dict[str, object] = {
        "name": "",
        "icon": PLACEHOLDER_ICON,
        "path": str(path),
        "exec": "",
        "comment": "",
        "desktop_type": "Application",
        "categories": "",
        "mimetypes": "",
        "terminal": False,
        "startup_notify": False,
    }

    for raw_line in content.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue

        if line == "[Desktop Entry]":
            in_desktop_entry = True
            continue
        if line.startswith("[") and line != "[Desktop Entry]":
            in_desktop_entry = False
            continue
        if not in_desktop_entry or "=" not in line:
            continue

        key, value = line.split("=", 1)
        if key == "Name":
            fields["name"] = value
        elif key.startswith("Name["):
            continue
        elif key == "Icon":
            fields["icon"] = value or PLACEHOLDER_ICON
        elif key == "Exec":
            fields["exec"] = value
        elif key == "Comment":
            fields["comment"] = value
        elif key == "Type":
            fields["desktop_type"] = value or "Application"
        elif key == "Categories":
            fields["categories"] = value
        elif key == "MimeType":
            fields["mimetypes"] = value
        elif key == "Terminal":
            fields["terminal"] = value.lower() == "true"
        elif key == "StartupNotify":
            fields["startup_notify"] = value.lower() == "true"

    if not fields["name"]:
        return None
    return fields


def scan_desktop_entries() -> list[dict[str, object]]:
    entries: list[dict[str, object]] = []
    for directory in (*STANDARD_PATHS, HOME_APPLICATIONS):
        if not directory.is_dir():
            continue
        try:
            candidates = sorted(directory.glob("*.desktop"))
        except OSError:
            continue
        for path in candidates:
            entry = parse_desktop_file(path)
            if entry is not None:
                entries.append(entry)

    entries.sort(key=lambda item: str(item["name"]).lower())
    return entries


def extract_executable(exec_line: str) -> str | None:
    try:
        parts = shlex.split(exec_line, posix=True)
    except ValueError:
        return None

    if not parts:
        return None

    index = 0
    if parts[0] == "env":
        index = 1
        while index < len(parts) and "=" in parts[index] and not parts[index].startswith("/"):
            key, _, _ = parts[index].partition("=")
            if key:
                index += 1
                continue
            break

    while index < len(parts) and parts[index].startswith("%"):
        index += 1

    if index >= len(parts):
        return None

    executable = parts[index]
    if not executable or executable.startswith("%"):
        return None
    if os.path.isabs(executable):
        return executable
    return shutil.which(executable)


def lookup_pacman_package(exec_line: str) -> str | None:
    executable = extract_executable(exec_line)
    if not executable:
        return None

    result = _run_command("pacman", "-Qo", executable)
    if result is None or result.returncode != 0:
        return None

    marker = " is owned by "
    if marker not in result.stdout:
        return None

    package_segment = result.stdout.split(marker, 1)[1].strip()
    package_name = package_segment.split(maxsplit=1)[0]
    return package_name or None


def get_package_info(package_name: str) -> dict[str, str] | None:
    result = _run_command("pacman", "-Qi", package_name)
    if result is None or result.returncode != 0:
        return None

    info = {
        "name": "",
        "version": "",
        "description": "",
        "url": "",
        "license": "",
        "depends": "",
    }

    for raw_line in result.stdout.splitlines():
        if ":" not in raw_line:
            continue
        key, value = raw_line.split(":", 1)
        key = key.strip()
        value = value.strip()
        if key == "Name":
            info["name"] = value
        elif key == "Version":
            info["version"] = value
        elif key == "Description":
            info["description"] = value
        elif key == "URL":
            info["url"] = value
        elif key == "Licenses":
            info["license"] = value
        elif key == "Depends On":
            info["depends"] = value

    if not info["name"]:
        return None
    return info


class DesktopEntryModel(QAbstractListModel):
    NameRole = Qt.UserRole + 1
    IconRole = Qt.UserRole + 2
    PathRole = Qt.UserRole + 3
    CommentRole = Qt.UserRole + 4
    ExecRole = Qt.UserRole + 5
    TypeRole = Qt.UserRole + 6

    def __init__(self) -> None:
        super().__init__()
        self._entries: list[dict[str, object]] = []
        self._filtered_entries: list[dict[str, object]] = []
        self._query = ""

    def rowCount(self, parent: QModelIndex = QModelIndex()) -> int:
        if parent.isValid():
            return 0
        return len(self._filtered_entries)

    def data(self, index: QModelIndex, role: int = Qt.DisplayRole) -> object:
        if not index.isValid():
            return None
        row = index.row()
        if row < 0 or row >= len(self._filtered_entries):
            return None

        entry = self._filtered_entries[row]
        if role == self.NameRole:
            return entry["name"]
        if role == self.IconRole:
            return entry["icon"]
        if role == self.PathRole:
            return entry["path"]
        if role == self.CommentRole:
            return entry["comment"]
        if role == self.ExecRole:
            return entry["exec"]
        if role == self.TypeRole:
            return entry["desktop_type"]
        return None

    def roleNames(self) -> dict[int, QByteArray]:
        return {
            self.NameRole: QByteArray(b"name"),
            self.IconRole: QByteArray(b"icon"),
            self.PathRole: QByteArray(b"path"),
            self.CommentRole: QByteArray(b"comment"),
            self.ExecRole: QByteArray(b"execLine"),
            self.TypeRole: QByteArray(b"desktopType"),
        }

    def set_entries(self, entries: list[dict[str, object]]) -> None:
        self.beginResetModel()
        self._entries = entries
        self._filtered_entries = self._apply_query(entries, self._query)
        self.endResetModel()

    def set_query(self, query: str) -> None:
        lowered = query.strip().lower()
        if lowered == self._query:
            return
        self.beginResetModel()
        self._query = lowered
        self._filtered_entries = self._apply_query(self._entries, lowered)
        self.endResetModel()

    def count(self) -> int:
        return len(self._filtered_entries)

    def entry_at(self, row: int) -> dict[str, object] | None:
        if row < 0 or row >= len(self._filtered_entries):
            return None
        return dict(self._filtered_entries[row])

    @staticmethod
    def _apply_query(entries: list[dict[str, object]], query: str) -> list[dict[str, object]]:
        if not query:
            return list(entries)
        return [entry for entry in entries if query in str(entry["name"]).lower()]


class DesktopIconProvider(QQuickImageProvider):
    def __init__(self) -> None:
        super().__init__(QQuickImageProvider.Image)

    def requestImage(self, identifier: str, size: QSize, requested_size: QSize) -> QImage:
        name = QUrl.fromPercentEncoding(identifier.encode("utf-8")) or PLACEHOLDER_ICON
        target = requested_size if requested_size.isValid() else QSize(48, 48)
        image = QImage()

        if name.startswith("/"):
            direct = QImage(name)
            if not direct.isNull():
                image = direct.scaled(target, Qt.KeepAspectRatio, Qt.SmoothTransformation)

        if image.isNull():
            icon = QIcon.fromTheme(name)
            if icon.isNull():
                icon = QIcon.fromTheme(PLACEHOLDER_ICON)
            image = icon.pixmap(target).toImage()

        if image.isNull():
            image = QImage(target, QImage.Format_ARGB32_Premultiplied)
            image.fill(QColor("#00000000"))
            painter = QPainter(image)
            painter.setRenderHint(QPainter.Antialiasing, True)
            painter.setPen(Qt.NoPen)
            painter.setBrush(QColor("#4b5160"))
            painter.drawRoundedRect(0, 0, target.width(), target.height(), 10, 10)
            painter.setBrush(QColor("#5294e2"))
            inset = max(8, min(target.width(), target.height()) // 4)
            painter.drawRoundedRect(
                inset,
                inset,
                max(8, target.width() - inset * 2),
                max(8, target.height() - inset * 2),
                8,
                8,
            )
            painter.end()
        if size is not None:
            size.setWidth(image.width())
            size.setHeight(image.height())
        return image


class WheelDebugFilter(QObject):
    def __init__(self, controller: "AppController") -> None:
        super().__init__()
        self._controller = controller

    @staticmethod
    def _named_ancestor(obj: QObject | None) -> QObject | None:
        current = obj
        while current is not None:
            if current.objectName() in {"resultsView", "detailsScroll"}:
                return current
            current = current.parent()
        return None

    def eventFilter(self, watched: QObject, event: QObject) -> bool:
        if event.type() == QEvent.Type.Wheel:
            wheel_event = event  # type: ignore[assignment]
            if isinstance(wheel_event, QWheelEvent):
                pixel = wheel_event.pixelDelta()
                angle = wheel_event.angleDelta()
                target = self._named_ancestor(watched)
                if target is not None and (pixel.y() != 0 or angle.y() != 0):
                    target_name = target.objectName()
                    delta_y = float(pixel.y() if pixel.y() != 0 else angle.y())
                    is_touchpad = pixel.y() != 0
                    multiplier = 18.0 if is_touchpad else 8.5
                    scaled = delta_y * multiplier

                    if target_name == "resultsView":
                        current_y = float(target.property("contentY") or 0.0)
                        content_height = float(target.property("contentHeight") or 0.0)
                        viewport_height = float(target.property("height") or 0.0)
                        max_y = max(0.0, content_height - viewport_height)
                        next_y = max(0.0, min(max_y, current_y - scaled))
                        target.setProperty("contentY", next_y)
                        self._controller.recordWheelDebug(
                            "results",
                            float(pixel.y()),
                            float(angle.y()),
                            scaled,
                            next_y,
                            max_y,
                        )
                        return True

                    if target_name == "detailsScroll":
                        flickable = target.property("contentItem")
                        if flickable is not None:
                            current_y = float(flickable.property("contentY") or 0.0)
                            content_height = float(flickable.property("contentHeight") or 0.0)
                            viewport_height = float(flickable.property("height") or 0.0)
                            max_y = max(0.0, content_height - viewport_height)
                            next_y = max(0.0, min(max_y, current_y - scaled))
                            flickable.setProperty("contentY", next_y)
                            self._controller.recordWheelDebug(
                                "details",
                                float(pixel.y()),
                                float(angle.y()),
                                scaled,
                                next_y,
                                max_y,
                            )
                            return True

                if pixel.y() != 0 or angle.y() != 0:
                    watched_name = watched.objectName() or watched.metaObject().className()
                    self._controller.recordWheelEventDebug(
                        watched_name,
                        float(pixel.y()),
                        float(angle.y()),
                    )
        return super().eventFilter(watched, event)


class AppController(QObject):
    scanFinished = Signal(list)
    detailFinished = Signal(int, dict)
    scanningChanged = Signal()
    statusTextChanged = Signal()
    selectedEntryChanged = Signal()
    detailLoadingChanged = Signal()
    wheelDebugChanged = Signal()

    def __init__(self) -> None:
        super().__init__()
        self._model = DesktopEntryModel()
        self._scanning = False
        self._status_text = "Ready"
        self._selected_entry: dict[str, object] = {}
        self._detail_loading = False
        self._detail_request = 0
        self._wheel_debug = "Wheel debug idle"

        self.scanFinished.connect(self._apply_scan_results)
        self.detailFinished.connect(self._apply_detail_results)

    @Property(QObject, constant=True)
    def entryModel(self) -> QObject:
        return self._model

    @Property(bool, notify=scanningChanged)
    def scanning(self) -> bool:
        return self._scanning

    @Property(str, notify=statusTextChanged)
    def statusText(self) -> str:
        return self._status_text

    @Property("QVariantMap", notify=selectedEntryChanged)
    def selectedEntry(self) -> dict[str, object]:
        return self._selected_entry

    @Property(bool, notify=detailLoadingChanged)
    def detailLoading(self) -> bool:
        return self._detail_loading

    @Property(str, notify=wheelDebugChanged)
    def wheelDebug(self) -> str:
        return self._wheel_debug

    @Slot()
    def startScan(self) -> None:
        if self._scanning:
            return
        self._set_scanning(True)
        self._set_status_text("Scanning for desktop files...")
        worker = threading.Thread(target=self._scan_worker, daemon=True)
        worker.start()

    @Slot(str)
    def setQuery(self, query: str) -> None:
        self._model.set_query(query)
        self._refresh_count_status()

    @Slot(int)
    def selectEntry(self, row: int) -> None:
        entry = self._model.entry_at(row)
        if entry is None:
            return

        entry.setdefault("packageName", "")
        entry.setdefault("packageVersion", "")
        entry.setdefault("packageDescription", "")
        entry.setdefault("packageUrl", "")
        entry.setdefault("packageLicense", "")
        entry.setdefault("packageDepends", "")
        self._selected_entry = entry
        self.selectedEntryChanged.emit()

        self._detail_request += 1
        request_id = self._detail_request
        self._set_detail_loading(True)
        worker = threading.Thread(target=self._detail_worker, args=(request_id, entry), daemon=True)
        worker.start()

    @Slot()
    def openSelected(self) -> None:
        path = str(self._selected_entry.get("path", ""))
        if path:
            QDesktopServices.openUrl(QUrl.fromLocalFile(path))

    @Slot()
    def chooseEditor(self) -> None:
        path = str(self._selected_entry.get("path", ""))
        if not path:
            return

        chosen, _ = QFileDialog.getOpenFileName(
            None,
            "Choose Editor",
            "/usr/bin",
        )
        if not chosen:
            return

        try:
            subprocess.Popen([chosen, path])
        except OSError:
            pass

    @Slot()
    def openPackageUrl(self) -> None:
        url = str(self._selected_entry.get("packageUrl", ""))
        if url:
            QDesktopServices.openUrl(QUrl(url))

    @Slot(str, float, float)
    def recordWheelEventDebug(
        self,
        source: str,
        pixel_delta_y: float,
        angle_delta_y: float,
    ) -> None:
        self._wheel_debug = (
            f"raw {source}  pixel={pixel_delta_y:.1f}  angle={angle_delta_y:.1f}"
        )
        print(self._wheel_debug, file=sys.stderr, flush=True)
        self.wheelDebugChanged.emit()

    @Slot(str, float, float, float, float, float)
    def recordWheelDebug(
        self,
        source: str,
        pixel_delta_y: float,
        angle_delta_y: float,
        scaled_delta: float,
        content_y: float,
        max_y: float,
    ) -> None:
        self._wheel_debug = (
            f"{source}  pixel={pixel_delta_y:.1f}  angle={angle_delta_y:.1f}  "
            f"scaled={scaled_delta:.1f}  y={content_y:.1f}/{max_y:.1f}"
        )
        print(self._wheel_debug, file=sys.stderr, flush=True)
        self.wheelDebugChanged.emit()

    def _scan_worker(self) -> None:
        entries = scan_desktop_entries()
        self.scanFinished.emit(entries)

    def _detail_worker(self, request_id: int, entry: dict[str, object]) -> None:
        detailed = dict(entry)
        package_name = lookup_pacman_package(str(entry.get("exec", "")))
        if package_name:
            package_info = get_package_info(package_name)
            detailed["packageName"] = package_name
            if package_info:
                detailed["packageName"] = package_info["name"]
                detailed["packageVersion"] = package_info["version"]
                detailed["packageDescription"] = package_info["description"]
                detailed["packageUrl"] = package_info["url"]
                detailed["packageLicense"] = package_info["license"]
                detailed["packageDepends"] = package_info["depends"]
        self.detailFinished.emit(request_id, detailed)

    @Slot(list)
    def _apply_scan_results(self, entries: list[dict[str, object]]) -> None:
        self._model.set_entries(entries)
        self._set_scanning(False)
        self._refresh_count_status()

    @Slot(int, dict)
    def _apply_detail_results(self, request_id: int, detailed: dict[str, object]) -> None:
        if request_id != self._detail_request:
            return
        self._selected_entry = detailed
        self.selectedEntryChanged.emit()
        self._set_detail_loading(False)

    def _refresh_count_status(self) -> None:
        count = self._model.count()
        label = "desktop file" if count == 1 else "desktop files"
        self._set_status_text(f"Found {count} {label}")

    def _set_scanning(self, value: bool) -> None:
        if self._scanning == value:
            return
        self._scanning = value
        self.scanningChanged.emit()

    def _set_status_text(self, value: str) -> None:
        if self._status_text == value:
            return
        self._status_text = value
        self.statusTextChanged.emit()

    def _set_detail_loading(self, value: bool) -> None:
        if self._detail_loading == value:
            return
        self._detail_loading = value
        self.detailLoadingChanged.emit()


def main() -> int:
    # Use a built-in Qt Quick Controls style so startup does not depend on
    # the user's global style configuration such as Kvantum being installed.
    QQuickStyle.setStyle("Fusion")
    app = QApplication(sys.argv)
    QGuiApplication.setApplicationName("Desktop File Search")
    QGuiApplication.setOrganizationName("desktop-file-search")
    QIcon.setThemeName(QIcon.themeName() or "hicolor")

    engine = QQmlApplicationEngine()
    engine.addImageProvider("desktopicons", DesktopIconProvider())

    controller = AppController()
    wheel_debug_filter = WheelDebugFilter(controller)
    app.installEventFilter(wheel_debug_filter)
    engine.rootContext().setContextProperty("backend", controller)
    engine.load(QUrl.fromLocalFile(str(Path(__file__).resolve().parent / "qml" / "Main.qml")))

    if not engine.rootObjects():
        return 1

    controller.startScan()
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())

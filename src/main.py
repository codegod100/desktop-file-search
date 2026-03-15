from __future__ import annotations

import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import threading
from pathlib import Path

from PySide6.QtCore import Property, QAbstractListModel, QByteArray, QEvent, QModelIndex, QObject, Qt, QTimer, QUrl, Signal, Slot, QSize
from PySide6.QtGui import QColor, QDesktopServices, QGuiApplication, QIcon, QImage, QPainter, QWheelEvent
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickImageProvider
from PySide6.QtQuickControls2 import QQuickStyle
from PySide6.QtSvg import QSvgRenderer
from PySide6.QtWidgets import QApplication, QFileDialog


STANDARD_PATHS = (
    Path("/usr/share/applications"),
    Path("/usr/local/share/applications"),
    Path("/var/lib/flatpak/exports/share/applications"),
)

HOME_APPLICATIONS = Path.home() / ".local/share/applications"
PLACEHOLDER_ICON = "application-x-executable"
APP_CACHE_DIR = Path.home() / ".cache" / "desktop-file-search"
ICON_CACHE_FILE = APP_CACHE_DIR / "icon-map.json"
_icon_path_map_cache: dict[str, str] | None = None
_icon_path_map_lock = threading.Lock()


def _load_persisted_icon_map() -> dict[str, str]:
    try:
        payload = json.loads(ICON_CACHE_FILE.read_text(encoding="utf-8"))
    except (OSError, ValueError, TypeError):
        return {}

    if not isinstance(payload, dict):
        return {}

    icon_map = payload.get("icons", payload)
    if not isinstance(icon_map, dict):
        return {}

    loaded: dict[str, str] = {}
    for name, path in icon_map.items():
        if not isinstance(name, str) or not isinstance(path, str):
            continue
        if not path.startswith("/") or Path(path).is_file():
            loaded[name] = path
    return loaded


def _persist_icon_map(icon_map: dict[str, str]) -> None:
    APP_CACHE_DIR.mkdir(parents=True, exist_ok=True)
    payload = {"icons": icon_map}
    tmp_path = ICON_CACHE_FILE.with_suffix(".tmp")
    try:
        tmp_path.write_text(json.dumps(payload, separators=(",", ":")), encoding="utf-8")
        tmp_path.replace(ICON_CACHE_FILE)
    except OSError:
        return


def _data_share_paths() -> list[Path]:
    roots: list[Path] = []
    seen: set[Path] = set()

    candidates = [
        Path.home() / ".local/share",
        Path.home() / ".nix-profile/share",
        Path("/etc/profiles/per-user") / os.environ.get("USER", "") / "share",
        Path("/nix/var/nix/profiles/default/share"),
        Path("/run/current-system/sw/share"),
        Path("/usr/local/share"),
        Path("/usr/share"),
    ]

    for value in os.environ.get("XDG_DATA_DIRS", "").split(":"):
        if value:
            candidates.append(Path(value))

    for candidate in candidates:
        try:
            resolved = candidate.expanduser().resolve(strict=False)
        except RuntimeError:
            continue
        if resolved in seen:
            continue
        seen.add(resolved)
        roots.append(resolved)

    return roots


def _icon_search_paths() -> list[Path]:
    paths: list[Path] = []
    seen: set[Path] = set()

    for root in _data_share_paths():
        for candidate in (root / "icons", root / "pixmaps"):
            resolved = candidate.resolve(strict=False)
            if resolved in seen:
                continue
            seen.add(resolved)
            paths.append(resolved)

    return paths


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


def collect_icon_names() -> list[str]:
    names: set[str] = set()
    for root_names in _scan_icon_roots(_icon_search_paths())[1]:
        names.update(root_names)

    names.add(PLACEHOLDER_ICON)
    return sorted(names, key=str.lower)


def _icon_candidate_score(candidate: Path) -> tuple[int, int, int, int, int]:
    path_text = str(candidate).lower()
    parts = [part.lower() for part in candidate.parts]
    stem = candidate.stem.lower()

    if stem.endswith("-symbolic"):
        symbolic_rank = 0
    elif "symbolic" in parts:
        symbolic_rank = 1
    else:
        symbolic_rank = 2

    category_rank = 0
    if "apps" in parts:
        category_rank = 4
    elif "scalable" in parts:
        category_rank = 3
    elif "panel" in parts:
        category_rank = 2
    elif "status" in parts:
        category_rank = 1

    theme_rank = 0
    if "hicolor" in parts:
        theme_rank = 3
    elif "papirus" in parts or "papirus-light" in parts:
        theme_rank = 2
    elif "adwaita" in parts:
        theme_rank = 1

    size_rank = 0
    for part in parts:
        if part == "scalable":
            size_rank = max(size_rank, 4096)
            continue
        match = re.fullmatch(r"(\d+)(?:x(\d+))?", part)
        if not match:
            continue
        width = int(match.group(1))
        height = int(match.group(2) or match.group(1))
        size_rank = max(size_rank, min(width, height))

    extension_rank = {
        ".svg": 3,
        ".png": 2,
        ".webp": 1,
        ".xpm": 0,
        ".jpg": 0,
        ".jpeg": 0,
    }.get(candidate.suffix.lower(), 0)

    if "legacy" in path_text:
        category_rank -= 1
        theme_rank -= 1

    return (symbolic_rank, category_rank, theme_rank, size_rank, extension_rank)


def _scan_icon_root(root: Path) -> tuple[dict[str, tuple[tuple[int, int, int, int, int], str]], set[str]]:
    valid_suffixes = {".png", ".svg", ".xpm", ".jpg", ".jpeg", ".webp"}
    icon_entries: dict[str, tuple[tuple[int, int, int, int, int], str]] = {}
    names: set[str] = set()

    if not root.exists():
        return icon_entries, names

    try:
        walker = os.walk(root, followlinks=False)
    except OSError:
        return icon_entries, names

    for dirpath, dirnames, filenames in walker:
        dirnames[:] = [name for name in dirnames if name not in {"cursors"}]
        for filename in filenames:
            suffix = Path(filename).suffix.lower()
            if suffix not in valid_suffixes:
                continue
            stem = Path(filename).stem
            if not stem:
                continue
            candidate = Path(dirpath) / filename
            names.add(stem)
            score = _icon_candidate_score(candidate)
            current = icon_entries.get(stem)
            if current is None or score > current[0]:
                icon_entries[stem] = (score, str(candidate))

    return icon_entries, names


def _scan_requested_icon_root(
    root: Path,
    requested_names: set[str],
) -> dict[str, tuple[tuple[int, int, int, int, int], str]]:
    valid_suffixes = {".png", ".svg", ".xpm", ".jpg", ".jpeg", ".webp"}
    icon_entries: dict[str, tuple[tuple[int, int, int, int, int], str]] = {}

    if not root.exists() or not requested_names:
        return icon_entries

    try:
        walker = os.walk(root, followlinks=False)
    except OSError:
        return icon_entries

    for dirpath, dirnames, filenames in walker:
        dirnames[:] = [name for name in dirnames if name not in {"cursors"}]
        for filename in filenames:
            suffix = Path(filename).suffix.lower()
            if suffix not in valid_suffixes:
                continue
            stem = Path(filename).stem
            if stem not in requested_names:
                continue
            candidate = Path(dirpath) / filename
            score = _icon_candidate_score(candidate)
            current = icon_entries.get(stem)
            if current is None or score > current[0]:
                icon_entries[stem] = (score, str(candidate))

    return icon_entries


def _scan_icon_roots(roots: list[Path]) -> tuple[dict[str, str], list[set[str]]]:
    merged_map: dict[str, str] = {}
    merged_scores: dict[str, tuple[int, int, int, int, int]] = {}
    name_sets: list[set[str]] = []

    for root in roots:
        icon_entries, names = _scan_icon_root(root)
        name_sets.append(names)
        for stem, (score, path) in icon_entries.items():
            current_score = merged_scores.get(stem)
            if current_score is None or score > current_score:
                merged_scores[stem] = score
                merged_map[stem] = path

    return merged_map, name_sets


def collect_requested_icon_map(icon_names: set[str]) -> dict[str, str]:
    requested_names = {name for name in icon_names if name and not name.startswith("/")}
    if not requested_names:
        return {}

    merged_map: dict[str, str] = {}
    merged_scores: dict[str, tuple[int, int, int, int, int]] = {}
    roots = _icon_search_paths()

    for root in roots:
        icon_entries = _scan_requested_icon_root(root, requested_names)
        for stem, (score, path) in icon_entries.items():
            current_score = merged_scores.get(stem)
            if current_score is None or score > current_score:
                merged_scores[stem] = score
                merged_map[stem] = path

    return merged_map


def collect_icon_map() -> dict[str, str]:
    icon_map, _ = _scan_icon_roots(_icon_search_paths())
    icon_map.setdefault(PLACEHOLDER_ICON, PLACEHOLDER_ICON)
    return icon_map


def resolve_icon_path(icon_name: str) -> str | None:
    global _icon_path_map_cache
    if not icon_name or icon_name.startswith("/"):
        return icon_name or None
    cache = _icon_path_map_cache or {}
    resolved = cache.get(icon_name)
    if resolved:
        return resolved
    if icon_name.endswith("-symbolic"):
        fallback = cache.get(icon_name.removesuffix("-symbolic"))
        if fallback:
            return fallback
    return None


def _load_icon_image(path: str, target: QSize) -> QImage:
    source = Path(path)
    if not source.is_file():
        return QImage()

    if source.suffix.lower() == ".svg":
        renderer = QSvgRenderer(str(source))
        if not renderer.isValid():
            return QImage()

        canvas = QImage(target, QImage.Format_ARGB32_Premultiplied)
        canvas.fill(QColor("#00000000"))
        painter = QPainter(canvas)
        renderer.render(painter)
        painter.end()
        return canvas

    direct = QImage(str(source))
    if direct.isNull():
        return QImage()
    return direct.scaled(target, Qt.KeepAspectRatio, Qt.SmoothTransformation)


def update_desktop_icon(path: Path, icon_value: str) -> Path | None:
    icon_value = icon_value.strip()
    if not icon_value:
        return None

    target_path = path
    if not os.access(path, os.W_OK):
        HOME_APPLICATIONS.mkdir(parents=True, exist_ok=True)
        target_path = HOME_APPLICATIONS / path.name
        try:
            shutil.copy2(path, target_path)
        except OSError:
            return None

    try:
        content = target_path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None

    lines = content.splitlines()
    output: list[str] = []
    in_desktop_entry = False
    icon_written = False

    for line in lines:
        stripped = line.strip()
        if stripped == "[Desktop Entry]":
            in_desktop_entry = True
            output.append(line)
            continue

        if stripped.startswith("[") and stripped != "[Desktop Entry]":
            if in_desktop_entry and not icon_written:
                output.append(f"Icon={icon_value}")
                icon_written = True
            in_desktop_entry = False
            output.append(line)
            continue

        if in_desktop_entry and re.match(r"^Icon\s*=", stripped):
            if not icon_written:
                output.append(f"Icon={icon_value}")
                icon_written = True
            continue

        output.append(line)

    if in_desktop_entry and not icon_written:
        output.append(f"Icon={icon_value}")
    elif not icon_written:
        output.extend(["", "[Desktop Entry]", f"Icon={icon_value}"])

    new_content = "\n".join(output) + "\n"
    try:
        target_path.write_text(new_content, encoding="utf-8")
    except OSError:
        return None
    return target_path


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


class IconNameModel(QAbstractListModel):
    NameRole = Qt.UserRole + 1
    PreviewRole = Qt.UserRole + 2

    def __init__(self) -> None:
        super().__init__()
        self._items: list[dict[str, str]] = []

    def rowCount(self, parent: QModelIndex = QModelIndex()) -> int:
        if parent.isValid():
            return 0
        return len(self._items)

    def data(self, index: QModelIndex, role: int = Qt.DisplayRole) -> object:
        if not index.isValid():
            return None
        row = index.row()
        if row < 0 or row >= len(self._items):
            return None
        item = self._items[row]
        if role == self.NameRole:
            return item["name"]
        if role == self.PreviewRole:
            return item["preview"]
        return None

    def roleNames(self) -> dict[int, QByteArray]:
        return {
            self.NameRole: QByteArray(b"name"),
            self.PreviewRole: QByteArray(b"preview"),
        }

    def set_items(self, items: list[dict[str, str]]) -> None:
        self.beginResetModel()
        self._items = items
        self.endResetModel()


class DesktopIconProvider(QQuickImageProvider):
    def __init__(self) -> None:
        super().__init__(QQuickImageProvider.Image)

    def requestImage(self, identifier: str, size: QSize, requested_size: QSize) -> QImage:
        raw_name = QUrl.fromPercentEncoding(identifier.encode("utf-8")) or PLACEHOLDER_ICON
        name = raw_name.split("?", 1)[0] or PLACEHOLDER_ICON
        target = requested_size if requested_size.isValid() else QSize(48, 48)
        image = QImage()

        resolved_name = resolve_icon_path(name) or name

        if resolved_name.startswith("/"):
            image = _load_icon_image(resolved_name, target)

        if image.isNull():
            icon = QIcon.fromTheme(name)
            if icon.isNull() and name.endswith("-symbolic"):
                icon = QIcon.fromTheme(name.removesuffix("-symbolic"))
            if icon.isNull() and resolved_name != name:
                icon = QIcon(resolved_name)
            if icon.isNull():
                icon = QIcon.fromTheme(PLACEHOLDER_ICON)
            if icon.isNull():
                fallback_path = resolve_icon_path(PLACEHOLDER_ICON)
                if fallback_path:
                    icon = QIcon(fallback_path)
            image = icon.pixmap(target).toImage()

        if image.isNull() and resolved_name.startswith("/"):
            image = _load_icon_image(resolved_name, target)

        if not image.isNull() and name.endswith("-symbolic"):
            tinted = QImage(image.size(), QImage.Format_ARGB32_Premultiplied)
            tinted.fill(QColor("#00000000"))
            painter = QPainter(tinted)
            painter.setRenderHint(QPainter.Antialiasing, True)
            painter.drawImage(0, 0, image)
            painter.setCompositionMode(QPainter.CompositionMode_SourceIn)
            painter.fillRect(tinted.rect(), QColor("#ffffff"))
            painter.end()
            image = tinted

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
            if current.objectName() in {"resultsView", "detailsScroll", "iconGrid"}:
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

                    if target_name == "iconGrid":
                        current_y = float(target.property("contentY") or 0.0)
                        content_height = float(target.property("contentHeight") or 0.0)
                        viewport_height = float(target.property("height") or 0.0)
                        max_y = max(0.0, content_height - viewport_height)
                        next_y = max(0.0, min(max_y, current_y - scaled))
                        target.setProperty("contentY", next_y)
                        self._controller.recordWheelDebug(
                            "iconGrid",
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
    iconCacheLoaded = Signal(dict)
    iconScanFinished = Signal(dict, list)
    entryIconScanFinished = Signal(dict)
    detailFinished = Signal(int, dict)
    entryModelChanged = Signal()
    iconNameModelChanged = Signal()
    scanningChanged = Signal()
    statusTextChanged = Signal()
    selectedEntryChanged = Signal()
    detailLoadingChanged = Signal()
    wheelDebugChanged = Signal()
    iconSearchChanged = Signal()
    iconRevisionChanged = Signal()

    def __init__(self) -> None:
        super().__init__()
        self._entries_all: list[dict[str, object]] = []
        self._entries_filtered: list[dict[str, object]] = []
        self._query = ""
        self._icon_items: list[dict[str, str]] = [{"name": PLACEHOLDER_ICON, "preview": PLACEHOLDER_ICON}]
        self._scanning = False
        self._status_text = "Ready"
        self._selected_entry: dict[str, object] = {}
        self._detail_loading = False
        self._detail_request = 0
        self._wheel_debug = "Wheel debug idle"
        self._all_icon_names: list[str] = []
        self._icon_path_map: dict[str, str] = {}
        self._icon_query = ""
        self._icon_revision = 0
        self._icon_cache_loading = False
        self._icon_cache_loaded = False
        self._icon_index_started = False
        self._icon_index_ready = False
        global _icon_path_map_cache
        _icon_path_map_cache = dict(self._icon_path_map)

        self.scanFinished.connect(self._apply_scan_results)
        self.iconCacheLoaded.connect(self._apply_icon_cache_results)
        self.iconScanFinished.connect(self._apply_icon_scan_results)
        self.entryIconScanFinished.connect(self._apply_entry_icon_results)
        self.detailFinished.connect(self._apply_detail_results)

    @Property("QVariantList", notify=entryModelChanged)
    def entryModel(self) -> list[dict[str, object]]:
        return self._entries_filtered

    @Property("QVariantList", notify=iconNameModelChanged)
    def iconNameModel(self) -> list[dict[str, str]]:
        return self._icon_items

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

    @Property(int, notify=iconRevisionChanged)
    def iconRevision(self) -> int:
        return self._icon_revision

    @Slot()
    def startScan(self) -> None:
        if self._scanning:
            return
        self._set_scanning(True)
        self._set_status_text("Scanning for desktop files...")
        worker = threading.Thread(target=self._scan_worker, daemon=True)
        worker.start()

    @Slot()
    def warmCaches(self) -> None:
        if self._icon_cache_loaded or self._icon_cache_loading:
            return
        self._icon_cache_loading = True
        worker = threading.Thread(target=self._icon_cache_worker, daemon=True)
        worker.start()

    @Slot(str)
    def setQuery(self, query: str) -> None:
        self._query = query.strip().lower()
        self._entries_filtered = self._apply_query(self._entries_all, self._query)
        self.entryModelChanged.emit()
        self._refresh_count_status()

    @Slot(int)
    def selectEntry(self, row: int) -> None:
        if row < 0 or row >= len(self._entries_filtered):
            return
        entry = dict(self._entries_filtered[row])

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

    @Slot(str)
    def setIconSearchQuery(self, query: str) -> None:
        self.startIconIndex()
        self._icon_query = query
        self._update_icon_picker_items(self._icon_query)
        self.iconNameModelChanged.emit()
        self.iconSearchChanged.emit()

    @Slot(str, result=str)
    def iconPreviewSource(self, icon_name: str) -> str:
        icon_name = icon_name.strip()
        if not icon_name:
            return PLACEHOLDER_ICON
        return self._icon_path_map.get(icon_name, icon_name)

    @Slot()
    def chooseIconFile(self) -> None:
        path = str(self._selected_entry.get("path", ""))
        if not path:
            return
        chosen, _ = QFileDialog.getOpenFileName(
            None,
            "Choose Icon File",
            str(Path.home()),
            "Images (*.png *.svg *.xpm *.jpg *.jpeg *.webp)",
        )
        if chosen:
            self._apply_icon_update(chosen)

    @Slot(str)
    def applyIconName(self, icon_name: str) -> None:
        if icon_name.strip():
            resolved = self._icon_path_map.get(icon_name.strip(), icon_name.strip())
            self._apply_icon_update(resolved)

    @Slot()
    def startIconIndex(self) -> None:
        self.warmCaches()
        if not self._icon_index_ready and self._icon_path_map:
            self._all_icon_names = sorted(self._icon_path_map.keys(), key=str.lower)
            self._icon_index_ready = True
            self._update_icon_picker_items(self._icon_query)
            self.iconNameModelChanged.emit()
            self.iconSearchChanged.emit()
        if self._icon_index_started:
            return
        self._icon_index_started = True
        icon_worker = threading.Thread(target=self._icon_scan_worker, daemon=True)
        icon_worker.start()

    @Slot(str, float, float)
    def recordWheelEventDebug(
        self,
        source: str,
        pixel_delta_y: float,
        angle_delta_y: float,
    ) -> None:
        _ = (source, pixel_delta_y, angle_delta_y)

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
        _ = (source, pixel_delta_y, angle_delta_y, scaled_delta, content_y, max_y)

    def _scan_worker(self) -> None:
        entries = scan_desktop_entries()
        try:
            self.scanFinished.emit(entries)
        except RuntimeError:
            pass

    def _icon_scan_worker(self) -> None:
        icon_map = collect_icon_map()
        names = sorted(icon_map.keys(), key=str.lower)
        try:
            self.iconScanFinished.emit(icon_map, names)
        except RuntimeError:
            pass

    def _icon_cache_worker(self) -> None:
        icon_map = _load_persisted_icon_map()
        try:
            self.iconCacheLoaded.emit(icon_map)
        except RuntimeError:
            pass

    def _entry_icon_scan_worker(self, icon_names: set[str]) -> None:
        icon_map = collect_requested_icon_map(icon_names)
        try:
            self.entryIconScanFinished.emit(icon_map)
        except RuntimeError:
            pass

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
        self._entries_all = entries
        self._entries_filtered = self._apply_query(entries, self._query)
        self.entryModelChanged.emit()
        self._set_scanning(False)
        self._refresh_count_status()
        visible_icon_names = {
            str(entry.get("icon", "")).strip()
            for entry in self._entries_filtered[:64]
            if str(entry.get("icon", "")).strip() and not str(entry.get("icon", "")).startswith("/")
        }
        all_icon_names = {
            str(entry.get("icon", "")).strip()
            for entry in self._entries_all
            if str(entry.get("icon", "")).strip() and not str(entry.get("icon", "")).startswith("/")
        }
        remaining_icon_names = all_icon_names - visible_icon_names
        if visible_icon_names:
            threading.Thread(
                target=self._entry_icon_scan_worker,
                args=(visible_icon_names,),
                daemon=True,
            ).start()
        if remaining_icon_names:
            threading.Thread(
                target=self._entry_icon_scan_worker,
                args=(remaining_icon_names,),
                daemon=True,
            ).start()

    @Slot(dict, list)
    def _apply_icon_scan_results(self, icon_map: dict[str, str], names: list[str]) -> None:
        global _icon_path_map_cache
        merged_map = dict(self._icon_path_map)
        merged_map.update(icon_map)
        _icon_path_map_cache = merged_map
        self._icon_path_map = merged_map
        self._all_icon_names = names
        self._icon_index_ready = True
        self._update_icon_picker_items(self._icon_query)
        _persist_icon_map(merged_map)
        self._icon_revision += 1
        self.iconNameModelChanged.emit()
        self.iconSearchChanged.emit()
        self.iconRevisionChanged.emit()
        self.entryModelChanged.emit()
        self.selectedEntryChanged.emit()

    @Slot(dict)
    def _apply_icon_cache_results(self, icon_map: dict[str, str]) -> None:
        self._icon_cache_loading = False
        self._icon_cache_loaded = True
        if not icon_map:
            return

        global _icon_path_map_cache
        merged_map = dict(self._icon_path_map)
        merged_map.update(icon_map)
        self._icon_path_map = merged_map
        _icon_path_map_cache = merged_map
        self._icon_revision += 1
        self.iconRevisionChanged.emit()
        self.entryModelChanged.emit()
        self.selectedEntryChanged.emit()

    @Slot(dict)
    def _apply_entry_icon_results(self, icon_map: dict[str, str]) -> None:
        global _icon_path_map_cache
        with _icon_path_map_lock:
            merged_map = dict(self._icon_path_map)
            merged_map.update(icon_map)
            self._icon_path_map = merged_map
            _icon_path_map_cache = merged_map
        _persist_icon_map(merged_map)
        self._icon_revision += 1
        self.iconRevisionChanged.emit()
        self.entryModelChanged.emit()
        self.selectedEntryChanged.emit()

    def _update_icon_picker_items(self, query: str) -> None:
        lowered = query.strip().lower()
        if not self._icon_index_ready:
            names = []
        elif not lowered:
            names = self._all_icon_names[:200]
        else:
            names = [name for name in self._all_icon_names if lowered in name.lower()][:200]
        self._icon_items = [
            {"name": name, "preview": self._icon_path_map.get(name, name)}
            for name in names
        ]

    @Slot(int, dict)
    def _apply_detail_results(self, request_id: int, detailed: dict[str, object]) -> None:
        if request_id != self._detail_request:
            return
        self._selected_entry = detailed
        self.selectedEntryChanged.emit()
        self._set_detail_loading(False)

    def _refresh_count_status(self) -> None:
        count = len(self._entries_filtered)
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

    def _apply_icon_update(self, icon_value: str) -> None:
        path_str = str(self._selected_entry.get("path", ""))
        if not path_str:
            return
        updated_path = update_desktop_icon(Path(path_str), icon_value)
        if updated_path is None:
            return
        updated_entry = parse_desktop_file(updated_path)
        if updated_entry is None:
            return

        # Preserve any already-fetched package metadata on the refreshed selection.
        for key in (
            "packageName",
            "packageVersion",
            "packageDescription",
            "packageUrl",
            "packageLicense",
            "packageDepends",
        ):
            if key in self._selected_entry:
                updated_entry[key] = self._selected_entry[key]

        self._selected_entry = updated_entry
        refreshed_entries = [
            entry for entry in self._entries_all if str(entry.get("path", "")) not in {path_str, str(updated_path)}
        ]
        refreshed_entries.append(updated_entry)
        refreshed_entries.sort(key=lambda item: str(item["name"]).lower())
        self._entries_all = refreshed_entries
        self._entries_filtered = self._apply_query(refreshed_entries, self._query)
        self.entryModelChanged.emit()
        self.selectedEntryChanged.emit()

    @staticmethod
    def _apply_query(entries: list[dict[str, object]], query: str) -> list[dict[str, object]]:
        if not query:
            return list(entries)
        return [entry for entry in entries if query in str(entry["name"]).lower()]


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

    QTimer.singleShot(0, controller.startScan)
    QTimer.singleShot(0, controller.warmCaches)
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())

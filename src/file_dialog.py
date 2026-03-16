from __future__ import annotations

from PySide6.QtWidgets import QApplication, QFileDialog


APP_SURFACE_LEFT = "#353b47"
APP_SURFACE_RIGHT = "#303641"
APP_SURFACE_RAISED = "#4a5160"
APP_BORDER_STRONG = "#16191f"
APP_BORDER_SOFT = "#2b313a"
APP_TEXT_PRIMARY = "#eff0f1"
APP_TEXT_SECONDARY = "#aeb6c2"
APP_ACCENT_PRIMARY = "#5294e2"


def styled_file_dialog(
    title: str,
    directory: str,
    name_filter: str = "",
) -> QFileDialog:
    parent = QApplication.activeWindow()
    dialog = QFileDialog(parent, title, directory)
    dialog.setFileMode(QFileDialog.ExistingFile)
    dialog.setOption(QFileDialog.DontUseNativeDialog, True)
    if name_filter:
        dialog.setNameFilter(name_filter)
    dialog.setStyleSheet(
        f"""
        QFileDialog {{
            background-color: {APP_SURFACE_RIGHT};
            color: {APP_TEXT_PRIMARY};
        }}
        QFileDialog QListView,
        QFileDialog QTreeView,
        QFileDialog QLineEdit,
        QFileDialog QComboBox,
        QFileDialog QSplitter,
        QFileDialog QDialogButtonBox,
        QFileDialog QToolButton {{
            background-color: {APP_SURFACE_LEFT};
            color: {APP_TEXT_PRIMARY};
            border: 1px solid {APP_BORDER_SOFT};
        }}
        QFileDialog QListView::item,
        QFileDialog QTreeView::item {{
            padding: 6px;
        }}
        QFileDialog QListView::item:selected,
        QFileDialog QTreeView::item:selected {{
            background: {APP_ACCENT_PRIMARY};
            color: {APP_TEXT_PRIMARY};
        }}
        QFileDialog QLabel {{
            color: {APP_TEXT_SECONDARY};
        }}
        QFileDialog QPushButton {{
            background-color: {APP_SURFACE_RAISED};
            color: {APP_TEXT_PRIMARY};
            border: 1px solid {APP_BORDER_STRONG};
            padding: 6px 12px;
        }}
        QFileDialog QPushButton:hover {{
            background-color: {APP_ACCENT_PRIMARY};
        }}
        """
    )
    return dialog


def get_open_file_name(
    title: str,
    directory: str,
    name_filter: str = "",
) -> str:
    dialog = styled_file_dialog(title, directory, name_filter)
    if dialog.exec() != QFileDialog.Accepted:
        return ""
    selected = dialog.selectedFiles()
    return selected[0] if selected else ""

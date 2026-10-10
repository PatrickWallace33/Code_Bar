"""
Uso IA (Code_Bar) para Windows
Barra flutuante minimalista e elegante para monitoramento em tempo real do uso de cotas das principais IAs de código:
- Claude (Anthropic)
- Codex / OpenAI
- Google Antigravity

Compatível com Windows 10/11 utilizando Python e PySide6 / PyQt6.
"""

from __future__ import annotations

import json
import math
import os
import re
import sys
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Tuple

# ==============================================================================
# Modelos e Constantes de Design
# ==============================================================================

BAR_WIDTH = 54
SNAP_DISTANCE = 36


class DockEdge(str, Enum):
    RIGHT = "right"
    LEFT = "left"
    TOP = "top"
    BOTTOM = "bottom"
    FLOATING = "floating"

    @property
    def is_horizontal(self) -> bool:
        return self in (DockEdge.TOP, DockEdge.BOTTOM)

    @property
    def is_docked(self) -> bool:
        return self != DockEdge.FLOATING


@dataclass
class UsageWindow:
    id: str
    label: str
    used_percent: float
    resets_at: Optional[datetime] = None
    runs_out_at: Optional[datetime] = None


@dataclass
class RecentProject:
    id: str
    name: str
    parent: str
    last_used: datetime
    session_id: Optional[str]
    provider: str
    summary: Optional[str] = None


@dataclass
class ProviderUsage:
    id: str
    name: str
    plan: Optional[str] = None
    windows: List[UsageWindow] = field(default_factory=list)
    reset_credits_count: Optional[int] = None
    reset_credits_expire_at: Optional[datetime] = None

    @property
    def session_window(self) -> Optional[UsageWindow]:
        for w in self.windows:
            lbl = w.label.lower()
            if "sessão" in lbl or "session" in lbl or "5" in lbl:
                return w
        return self.windows[0] if self.windows else None

    @property
    def weekly_window(self) -> Optional[UsageWindow]:
        for w in self.windows:
            lbl = w.label.lower()
            if "semanal" in lbl or "weekly" in lbl:
                return w
        return None

    def operational_window(self, shows_weekly_claude: bool = False) -> Optional[UsageWindow]:
        if self.id == "claude":
            if shows_weekly_claude:
                return self.weekly_window or self.session_window
            return self.session_window or self.windows[0] if self.windows else None
        elif self.id == "codex":
            return self.weekly_window or (self.windows[0] if self.windows else None)
        return self.windows[0] if self.windows else None


# ==============================================================================
# Geometria Canônica da Curva em S (SidebarShape)
# ==============================================================================

class ShapeGeometry:
    """
    Gera o contorno perfeito da aba em S idêntico ao validado no macOS.
    Utiliza mapeamento rígido (rotação e espelhamento) a partir da borda direita canônica.
    """

    @staticmethod
    def map_point(x: float, y: float, edge: DockEdge, T: float, L: float,
                  offset_x: float = 0, offset_y: float = 0) -> Tuple[float, float]:
        if edge == DockEdge.RIGHT:
            return (offset_x + x, offset_y + y)
        elif edge == DockEdge.LEFT:
            return (offset_x + (T - x), offset_y + y)
        elif edge == DockEdge.TOP:
            return (offset_x + y, offset_y + (T - x))
        elif edge == DockEdge.BOTTOM:
            return (offset_x + y, offset_y + x)
        return (offset_x + x, offset_y + y)

    @classmethod
    def get_canonical_commands(cls, width: float, height: float, edge: DockEdge,
                               offset_x: float = 0, offset_y: float = 0) -> List[Tuple]:
        T = height if edge.is_horizontal else width
        L = width if edge.is_horizontal else height

        cap = min(T * 1.30, L / 2)
        middle = T * 0.60

        def mp(x: float, y: float) -> Tuple[float, float]:
            return cls.map_point(x, y, edge, T, L, offset_x, offset_y)

        commands = [
            ("move", mp(T, 0)),
            ("cubic", mp(T, cap * 0.48), mp(T * 0.90, cap * 0.54), mp(middle, cap * 0.54)),
            ("cubic", mp(T * 0.16, cap * 0.54), mp(0, cap * 0.72), mp(0, cap)),
            ("line", mp(0, L - cap)),
            ("cubic", mp(0, L - cap * 0.72), mp(T * 0.16, L - cap * 0.54), mp(middle, L - cap * 0.54)),
            ("cubic", mp(T * 0.90, L - cap * 0.54), mp(T, L - cap * 0.48), mp(T, L)),
            ("close", ())
        ]
        return commands


# ==============================================================================
# Posicionamento e Atração Magnética (BarPlacement)
# ==============================================================================

@dataclass
class BarPlacement:
    x: float
    y: float
    width: float
    height: float
    docked: bool
    edge: DockEdge

    @classmethod
    def detect_edge(cls, rect: Tuple[float, float, float, float],
                    target: Tuple[float, float, float, float],
                    current_edge: DockEdge = DockEdge.RIGHT,
                    snap_distance: float = SNAP_DISTANCE) -> DockEdge:
        rx, ry, rw, rh = rect
        tx, ty, tw, th = target

        r_maxX = rx + rw
        r_maxY = ry + rh
        t_maxX = tx + tw
        t_maxY = ty + th

        dist_right = 0 if r_maxX >= t_maxX else (t_maxX - r_maxX)
        dist_left = 0 if rx <= tx else (rx - tx)
        dist_top = 0 if ry <= ty else (ry - ty)
        dist_bottom = 0 if r_maxY >= t_maxY else (t_maxY - r_maxY)

        candidates = [
            (DockEdge.RIGHT, dist_right),
            (DockEdge.LEFT, dist_left),
            (DockEdge.TOP, dist_top),
            (DockEdge.BOTTOM, dist_bottom),
        ]

        min_dist = min(c[1] for c in candidates)
        if min_dist >= snap_distance:
            return DockEdge.FLOATING

        close_ones = [c for c in candidates if abs(c[1] - min_dist) < 4]
        if len(close_ones) > 1:
            for c in close_ones:
                if c[0] == current_edge:
                    return c[0]
            for c in close_ones:
                if c[0].is_horizontal == current_edge.is_horizontal:
                    return c[0]

        return min(candidates, key=lambda c: c[1])[0]

    def restored_rect(self, size: Tuple[float, float],
                      screen_rect: Tuple[float, float, float, float]) -> Tuple[float, float, float, float]:
        sw, sh = size
        sx, sy, sw_screen, sh_screen = screen_rect
        s_maxX = sx + sw_screen
        s_maxY = sy + sh_screen

        res_x = self.x
        res_y = self.y

        if self.edge == DockEdge.RIGHT:
            res_x = s_maxX - sw
        elif self.edge == DockEdge.LEFT:
            res_x = sx
        elif self.edge == DockEdge.TOP:
            res_y = sy
        elif self.edge == DockEdge.BOTTOM:
            res_y = s_maxY - sh

        # Limitar dentro da tela
        res_x = max(sx, min(res_x, s_maxX - sw))
        res_y = max(sy, min(res_y, s_maxY - sh))
        return (res_x, res_y, sw, sh)


# ==============================================================================
# Leitura de Sessões e Projetos Recentes no Windows
# ==============================================================================

class RecentProjectsScanner:
    UUID_REGEX = re.compile(r"([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})")
    CWD_REGEX = re.compile(r'"cwd"\s*:\s*"((?:[^"\\]|\\.)*)"')
    AGY_CWD_REGEX = re.compile(r'"(?:Cwd|DirectoryPath|TargetFile)"\s*:\s*"?\\?"?([^"\\,}]+)')
    TEXT_REGEX = re.compile(r'"(?:text|content)"\s*:\s*"((?:[^"\\]|\\.)*)"')

    @classmethod
    def clean_summary(cls, raw: str) -> Optional[str]:
        text = raw.replace("\\n", " ").replace('\\"', '"').replace("\\/", "/")
        text = re.sub(r"<environment_context>[\s\S]*?</environment_context>", "", text)
        req_match = re.search(r"<USER_REQUEST>([\s\S]*?)</USER_REQUEST>", text)
        if req_match:
            text = req_match.group(1)
        text = re.sub(r"<[^>]+>", " ", text)
        text = re.sub(r"\s+", " ", text).strip()

        if ".png" in text:
            idx = text.find(".png")
            after = text[idx + 4:].strip()
            text = after if after else "Captura de tela enviada"

        lower = text.lower()
        skip = ["caveat:", "filesystem sandboxing", "you are", "permissions instructions"]
        if any(s in lower for s in skip) or text.startswith(("{", "[", "#", "<")) or len(text) < 3:
            return None
        return (text[:45] + "…") if len(text) > 48 else text

    @classmethod
    def scan_claude(cls, limit: int = 3) -> List[RecentProject]:
        home = Path.home()
        projects_dir = home / ".claude" / "projects"
        if not projects_dir.exists():
            return []
        files = sorted(projects_dir.glob("**/*.jsonl"), key=lambda p: p.stat().st_mtime, reverse=True)
        seen = set()
        results = []
        for f in files[:200]:
            try:
                head = f.read_text(encoding="utf-8", errors="ignore")[:65536]
            except Exception:
                continue
            m = cls.CWD_REGEX.search(head)
            if not m:
                continue
            cwd = m.group(1).replace("\\\\", "\\").replace("\\/", "/")
            if cwd in seen:
                continue
            seen.add(cwd)
            p_cwd = Path(cwd)
            summary = None
            for line in head.splitlines()[:50]:
                if '"user"' in line or '"USER_INPUT"' in line:
                    tm = cls.TEXT_REGEX.search(line)
                    if tm:
                        summary = cls.clean_summary(tm.group(1))
                        if summary:
                            break
            sess_m = cls.UUID_REGEX.search(f.name)
            results.append(RecentProject(
                id=cwd,
                name=p_cwd.name or "~",
                parent=p_cwd.parent.name if p_cwd.parent else "",
                last_used=datetime.fromtimestamp(f.stat().st_mtime, tz=timezone.utc),
                session_id=sess_m.group(1) if sess_m else None,
                provider="claude",
                summary=summary
            ))
            if len(results) >= limit:
                break
        return results

    @classmethod
    def scan_codex(cls, limit: int = 3) -> List[RecentProject]:
        home = Path.home()
        sessions_dir = home / ".codex" / "sessions"
        if not sessions_dir.exists():
            return []
        files = sorted(sessions_dir.glob("**/*.jsonl"), key=lambda p: p.stat().st_mtime, reverse=True)
        seen = set()
        results = []
        for f in files[:200]:
            try:
                head = f.read_text(encoding="utf-8", errors="ignore")[:98304]
            except Exception:
                continue
            m = cls.CWD_REGEX.search(head)
            if not m:
                continue
            cwd = m.group(1).replace("\\\\", "\\").replace("\\/", "/")
            if cwd in seen:
                continue
            seen.add(cwd)
            p_cwd = Path(cwd)
            summary = None
            for line in head.splitlines()[:50]:
                if '"user"' in line or '"USER_INPUT"' in line:
                    tm = cls.TEXT_REGEX.search(line)
                    if tm:
                        summary = cls.clean_summary(tm.group(1))
                        if summary:
                            break
            sess_m = cls.UUID_REGEX.search(f.name)
            results.append(RecentProject(
                id=cwd,
                name=p_cwd.name or "~",
                parent=p_cwd.parent.name if p_cwd.parent else "",
                last_used=datetime.fromtimestamp(f.stat().st_mtime, tz=timezone.utc),
                session_id=sess_m.group(1) if sess_m else None,
                provider="codex",
                summary=summary
            ))
            if len(results) >= limit:
                break
        return results

    @classmethod
    def scan_antigravity(cls, limit: int = 3) -> List[RecentProject]:
        home = Path.home()
        brain_dir = home / ".gemini" / "antigravity-cli" / "brain"
        if not brain_dir.exists():
            return []
        dirs = [d for d in brain_dir.iterdir() if d.is_dir()]
        entries = []
        for d in dirs:
            t = d / ".system_generated" / "logs" / "transcript.jsonl"
            if t.exists():
                entries.append((t, t.stat().st_mtime, d.name))
        entries.sort(key=lambda e: e[1], reverse=True)
        seen = set()
        results = []
        for t, mtime, uuid_str in entries[:100]:
            try:
                head = t.read_text(encoding="utf-8", errors="ignore")[:32768]
            except Exception:
                continue
            m = cls.AGY_CWD_REGEX.search(head)
            if not m:
                continue
            cwd = m.group(1).replace("\\\\", "\\").replace("\\/", "/").strip('" ')
            if cwd in seen:
                continue
            seen.add(cwd)
            p_cwd = Path(cwd)
            summary = None
            for line in head.splitlines()[:50]:
                if '"USER_INPUT"' in line or '"USER_EXPLICIT"' in line:
                    tm = cls.TEXT_REGEX.search(line)
                    if tm:
                        summary = cls.clean_summary(tm.group(1))
                        if summary:
                            break
            results.append(RecentProject(
                id=cwd,
                name=p_cwd.name or "~",
                parent=p_cwd.parent.name if p_cwd.parent else "",
                last_used=datetime.fromtimestamp(mtime, tz=timezone.utc),
                session_id=uuid_str,
                provider="antigravity",
                summary=summary
            ))
            if len(results) >= limit:
                break
        return results

    @classmethod
    def scan_all(cls, limit: int = 3) -> Dict[str, List[RecentProject]]:
        return {
            "claude": cls.scan_claude(limit),
            "codex": cls.scan_codex(limit),
            "antigravity": cls.scan_antigravity(limit),
        }


# ==============================================================================
# Configurações Persistentes no Windows (%APPDATA%/Code_Bar)
# ==============================================================================

class SettingsManager:
    @staticmethod
    def get_config_dir() -> Path:
        appdata = os.environ.get("APPDATA")
        if appdata:
            path = Path(appdata) / "Code_Bar"
        else:
            path = Path.home() / ".code_bar"
        path.mkdir(parents=True, exist_ok=True)
        return path

    @classmethod
    def load_settings(cls) -> Dict[str, Any]:
        cfg_file = cls.get_config_dir() / "settings.json"
        defaults = {
            "dockEdge": "right",
            "docked": True,
            "x": 100,
            "y": 200,
            "refreshInterval": 60,
            "showsWeeklyUsage": False,
        }
        if cfg_file.exists():
            try:
                data = json.loads(cfg_file.read_text(encoding="utf-8"))
                defaults.update(data)
            except Exception:
                pass
        return defaults

    @classmethod
    def save_settings(cls, settings: Dict[str, Any]) -> None:
        cfg_file = cls.get_config_dir() / "settings.json"
        try:
            cfg_file.write_text(json.dumps(settings, indent=2), encoding="utf-8")
        except Exception:
            pass


# ==============================================================================
# Interface Gráfica Windows (PySide6 / PyQt6)
# ==============================================================================

try:
    from PySide6.QtCore import Qt, QPoint, QRect, QTimer, Signal
    from PySide6.QtGui import (
        QColor, QFont, QPainter, QPainterPath, QPen, QAction, QCursor
    )
    from PySide6.QtWidgets import (
        QApplication, QWidget, QMenu, QVBoxLayout, QLabel, QPushButton
    )
    QT_AVAILABLE = True
except ImportError:
    try:
        from PyQt6.QtCore import Qt, QPoint, QRect, QTimer, pyqtSignal as Signal
        from PyQt6.QtGui import (
            QColor, QFont, QPainter, QPainterPath, QPen, QAction, QCursor
        )
        from PyQt6.QtWidgets import (
            QApplication, QWidget, QMenu, QVBoxLayout, QLabel, QPushButton
        )
        QT_AVAILABLE = True
    except ImportError:
        QT_AVAILABLE = False


if QT_AVAILABLE:
    class CodeBarWindow(QWidget):
        """Janela flutuante minimalista para Windows com atração magnética e curvas em S."""

        def __init__(self):
            super().__init__()
            self.settings = SettingsManager.load_settings()
            self.dock_edge = DockEdge(self.settings.get("dockEdge", "right"))
            self.docked = self.settings.get("docked", True)
            self.refresh_interval = int(self.settings.get("refreshInterval", 60))
            self.shows_weekly = self.settings.get("showsWeeklyUsage", False)

            self.is_dragging = False
            self.drag_start_pos = QPoint()
            self.drag_window_pos = QPoint()
            self.hovered = False

            # Provedores mock/padrão
            self.providers = [
                ProviderUsage(id="claude", name="Claude", plan="Pro", windows=[
                    UsageWindow(id="sess", label="Sessão (5 horas)", used_percent=24),
                    UsageWindow(id="week", label="Semanal (todos os modelos)", used_percent=42)
                ]),
                ProviderUsage(id="codex", name="Codex", plan="Plus", windows=[
                    UsageWindow(id="week", label="Limite semanal", used_percent=19)
                ], reset_credits_count=1),
                ProviderUsage(id="antigravity", name="Antigravity", windows=[
                    UsageWindow(id="gem", label="Gemini", used_percent=68)
                ])
            ]
            self.recent_projects = RecentProjectsScanner.scan_all()

            self.init_ui()
            self.init_timer()

        def init_ui(self):
            self.setWindowFlags(
                Qt.WindowType.FramelessWindowHint |
                Qt.WindowType.WindowStaysOnTopHint |
                Qt.WindowType.Tool
            )
            self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)
            self.setMouseTracking(True)

            self.update_geometry()
            self.restore_position()

        def update_geometry(self):
            if self.dock_edge.is_horizontal:
                self.resize(250, BAR_WIDTH)
            else:
                self.resize(BAR_WIDTH, 260)

        def restore_position(self):
            screen = QApplication.primaryScreen()
            if not screen:
                return
            geom = screen.availableGeometry()
            placement = BarPlacement(
                x=float(self.settings.get("x", 100)),
                y=float(self.settings.get("y", 200)),
                width=float(self.width()),
                height=float(self.height()),
                docked=self.docked,
                edge=self.dock_edge
            )
            rx, ry, rw, rh = placement.restored_rect(
                (float(self.width()), float(self.height())),
                (float(geom.x()), float(geom.y()), float(geom.width()), float(geom.height()))
            )
            self.move(int(rx), int(ry))

        def init_timer(self):
            self.timer = QTimer(self)
            self.timer.timeout.connect(self.refresh_data)
            self.timer.start(self.refresh_interval * 1000)

        def refresh_data(self):
            self.recent_projects = RecentProjectsScanner.scan_all()
            self.update()

        def enterEvent(self, event):
            self.hovered = True
            self.update()
            super().enterEvent(event)

        def leaveEvent(self, event):
            self.hovered = False
            self.update()
            super().leaveEvent(event)

        def mousePressEvent(self, event):
            if event.button() == Qt.MouseButton.LeftButton:
                self.is_dragging = True
                self.drag_start_pos = event.globalPosition().toPoint()
                self.drag_window_pos = self.frameGeometry().topLeft()
            super().mousePressEvent(event)

        def mouseMoveEvent(self, event):
            if self.is_dragging:
                delta = event.globalPosition().toPoint() - self.drag_start_pos
                self.move(self.drag_window_pos + delta)
            super().mouseMoveEvent(event)

        def mouseReleaseEvent(self, event):
            if event.button() == Qt.MouseButton.LeftButton and self.is_dragging:
                self.is_dragging = False
                self.snap_to_edge()
            super().mouseReleaseEvent(event)

        def snap_to_edge(self):
            screen = QApplication.primaryScreen()
            if not screen:
                return
            geom = screen.availableGeometry()
            target = (float(geom.x()), float(geom.y()), float(geom.width()), float(geom.height()))
            rect = (float(self.x()), float(self.y()), float(self.width()), float(self.height()))

            new_edge = BarPlacement.detect_edge(rect, target, self.dock_edge)
            orientation_changed = (new_edge.is_horizontal != self.dock_edge.is_horizontal)
            self.dock_edge = new_edge
            self.docked = new_edge.is_docked

            if orientation_changed:
                self.update_geometry()

            placement = BarPlacement(
                x=float(self.x()), y=float(self.y()),
                width=float(self.width()), height=float(self.height()),
                docked=self.docked, edge=self.dock_edge
            )
            rx, ry, _, _ = placement.restored_rect(
                (float(self.width()), float(self.height())), target
            )
            self.move(int(rx), int(ry))

            self.settings["dockEdge"] = self.dock_edge.value
            self.settings["docked"] = self.docked
            self.settings["x"] = int(rx)
            self.settings["y"] = int(ry)
            SettingsManager.save_settings(self.settings)
            self.update()

        def set_edge(self, edge: DockEdge):
            screen = QApplication.primaryScreen()
            if not screen:
                return
            geom = screen.availableGeometry()
            target = (float(geom.x()), float(geom.y()), float(geom.width()), float(geom.height()))

            self.dock_edge = edge
            self.docked = edge.is_docked
            self.update_geometry()

            placement = BarPlacement(
                x=float(self.x()), y=float(self.y()),
                width=float(self.width()), height=float(self.height()),
                docked=self.docked, edge=self.dock_edge
            )
            rx, ry, _, _ = placement.restored_rect(
                (float(self.width()), float(self.height())), target
            )
            self.move(int(rx), int(ry))

            self.settings["dockEdge"] = self.dock_edge.value
            self.settings["docked"] = self.docked
            self.settings["x"] = int(rx)
            self.settings["y"] = int(ry)
            SettingsManager.save_settings(self.settings)
            self.update()

        def contextMenuEvent(self, event):
            menu = QMenu(self)
            menu.setStyleSheet("""
                QMenu {
                    background-color: #242424;
                    color: #FFFFFF;
                    border: 1px solid rgba(255, 255, 255, 0.15);
                    border-radius: 8px;
                    padding: 4px;
                }
                QMenu::item {
                    padding: 6px 24px;
                    border-radius: 4px;
                }
                QMenu::item:selected {
                    background-color: rgba(255, 255, 255, 0.15);
                }
            """)

            act_refresh = menu.addAction("Atualizar agora")
            act_refresh.triggered.connect(self.refresh_data)
            menu.addSeparator()

            pos_menu = menu.addMenu("Posição na tela")
            for edge, label in [
                (DockEdge.RIGHT, "Lado direito"),
                (DockEdge.LEFT, "Lado esquerdo"),
                (DockEdge.TOP, "Topo (cima)"),
                (DockEdge.BOTTOM, "Base (baixo)")
            ]:
                mark = " ✓" if self.dock_edge == edge else ""
                act = pos_menu.addAction(f"{label}{mark}")
                act.triggered.connect(lambda checked, e=edge: self.set_edge(e))

            interval_menu = menu.addMenu("Intervalo de atualização")
            for sec, label in [(30, "30 segundos"), (60, "1 minuto (padrão)"), (120, "2 minutos"), (300, "5 minutos")]:
                mark = " ✓" if self.refresh_interval == sec else ""
                act = interval_menu.addAction(f"{label}{mark}")
                act.triggered.connect(lambda checked, s=sec: self.set_interval(s))

            menu.addSeparator()
            act_weekly = menu.addAction(f"Mostrar consumo semanal no Claude{' ✓' if self.shows_weekly else ''}")
            act_weekly.triggered.connect(self.toggle_weekly)

            menu.addSeparator()
            act_quit = menu.addAction("Sair do Uso IA")
            act_quit.triggered.connect(QApplication.quit)

            menu.exec(event.globalPos())

        def set_interval(self, sec: int):
            self.refresh_interval = sec
            self.settings["refreshInterval"] = sec
            SettingsManager.save_settings(self.settings)
            self.timer.setInterval(sec * 1000)

        def toggle_weekly(self):
            self.shows_weekly = not self.shows_weekly
            self.settings["showsWeeklyUsage"] = self.shows_weekly
            SettingsManager.save_settings(self.settings)
            self.update()

        def paintEvent(self, event):
            painter = QPainter(self)
            painter.setRenderHint(QPainter.RenderHint.Antialiasing)

            w = float(self.width())
            h = float(self.height())

            # Desenha contorno translúcido em S
            path = QPainterPath()
            if self.dock_edge == DockEdge.FLOATING:
                path.addRoundedRect(0, 0, w, h, 18, 18)
            else:
                cmds = ShapeGeometry.get_canonical_commands(w, h, self.dock_edge)
                for cmd in cmds:
                    op = cmd[0]
                    if op == "move":
                        path.moveTo(*cmd[1])
                    elif op == "cubic":
                        path.cubicTo(cmd[1][0], cmd[1][1], cmd[2][0], cmd[2][1], cmd[3][0], cmd[3][1])
                    elif op == "line":
                        path.lineTo(*cmd[1])
                    elif op == "close":
                        path.closeSubpath()

            alpha = 240 if self.hovered else 90
            fill_color = QColor(20, 20, 20, alpha)
            painter.fillPath(path, fill_color)

            pen = QPen(QColor(255, 255, 255, 30 if self.hovered else 15), 0.75)
            painter.setPen(pen)
            painter.drawPath(path)

            # Desenha anéis de consumo
            self.draw_rings(painter, w, h)

        def draw_rings(self, painter: QPainter, w: float, h: float):
            is_horiz = self.dock_edge.is_horizontal
            num_providers = len(self.providers)

            for i, p in enumerate(self.providers):
                win = p.operational_window(self.shows_weekly)
                pct = win.used_percent if win else 0.0

                if is_horiz:
                    cx = 46 + i * 50 + 20
                    cy = h / 2
                else:
                    cx = w / 2
                    cy = 46 + i * 55 + 20

                # Círculo base (trilho)
                pen_track = QPen(QColor(255, 255, 255, 45), 3.0)
                painter.setPen(pen_track)
                radius = 16.0
                painter.drawEllipse(QPoint(int(cx), int(cy)), int(radius), int(radius))

                # Arco de consumo
                if pct > 0:
                    color = QColor(247, 217, 56) if pct < 75 else (QColor(255, 171, 61) if pct < 90 else QColor(255, 92, 84))
                    pen_arc = QPen(color, 3.2)
                    pen_arc.setCapStyle(Qt.PenCapStyle.RoundCap)
                    painter.setPen(pen_arc)
                    span_angle = int(-pct / 100.0 * 360 * 16)
                    painter.drawArc(int(cx - radius), int(cy - radius), int(radius * 2), int(radius * 2), 90 * 16, span_angle)

                # Letra/Ícone no centro
                painter.setPen(QColor(255, 255, 255, 240))
                font = QFont("Segoe UI", 8, QFont.Weight.Bold)
                painter.setFont(font)
                letter = p.name[:1].upper()
                painter.drawText(QRect(int(cx - 10), int(cy - 10), 20, 20), Qt.AlignmentFlag.AlignCenter, letter)

                # Percentual abaixo do anel
                pct_text = f"{int(pct)}%"
                font_pct = QFont("Segoe UI", 8, QFont.Weight.Bold)
                painter.setFont(font_pct)
                painter.setPen(QColor(255, 255, 255, 230))
                if is_horiz:
                    painter.drawText(QRect(int(cx - 16), int(cy + radius + 1), 32, 12), Qt.AlignmentFlag.AlignCenter, pct_text)
                else:
                    painter.drawText(QRect(int(cx - 16), int(cy + radius + 2), 32, 12), Qt.AlignmentFlag.AlignCenter, pct_text)


def main():
    if not QT_AVAILABLE:
        print("[AVISO] PySide6 ou PyQt6 não instalado.")
        print("Para instalar no Windows, execute: pip install -r requirements.txt")
        sys.exit(1)

    app = QApplication(sys.argv)
    window = CodeBarWindow()
    window.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
Testes automatizados para a versão Windows do Uso IA (Code_Bar).
Valida geometria de curvas, detecção de bordas, persistência e modelos de cota.
"""

import os
import sys
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

# Adiciona o diretório windows ao sys.path para importação
sys.path.insert(0, str(Path(__file__).parent))

from code_bar import (
    BAR_WIDTH,
    SNAP_DISTANCE,
    BarPlacement,
    DockEdge,
    ProviderUsage,
    RecentProjectsScanner,
    SettingsManager,
    ShapeGeometry,
    UsageWindow,
)


class TestDockEdge(unittest.TestCase):
    def test_orientation_and_docking(self):
        self.assertFalse(DockEdge.RIGHT.is_horizontal)
        self.assertFalse(DockEdge.LEFT.is_horizontal)
        self.assertTrue(DockEdge.TOP.is_horizontal)
        self.assertTrue(DockEdge.BOTTOM.is_horizontal)

        self.assertTrue(DockEdge.RIGHT.is_docked)
        self.assertTrue(DockEdge.LEFT.is_docked)
        self.assertTrue(DockEdge.TOP.is_docked)
        self.assertTrue(DockEdge.BOTTOM.is_docked)
        self.assertFalse(DockEdge.FLOATING.is_docked)


class TestShapeGeometry(unittest.TestCase):
    def test_canonical_mapping(self):
        T = 54.0
        L = 260.0

        # Right (identidade)
        self.assertEqual(ShapeGeometry.map_point(10, 20, DockEdge.RIGHT, T, L), (10, 20))

        # Left (inverte X em relação a T)
        self.assertEqual(ShapeGeometry.map_point(10, 20, DockEdge.LEFT, T, L), (44, 20))

        # Top (troca eixos com T - x)
        self.assertEqual(ShapeGeometry.map_point(10, 20, DockEdge.TOP, T, L), (20, 44))

        # Bottom (troca eixos com x)
        self.assertEqual(ShapeGeometry.map_point(10, 20, DockEdge.BOTTOM, T, L), (20, 10))

    def test_canonical_commands_structure(self):
        cmds = ShapeGeometry.get_canonical_commands(54.0, 260.0, DockEdge.RIGHT)
        self.assertEqual(len(cmds), 7)
        self.assertEqual(cmds[0][0], "move")
        self.assertEqual(cmds[1][0], "cubic")
        self.assertEqual(cmds[2][0], "cubic")
        self.assertEqual(cmds[3][0], "line")
        self.assertEqual(cmds[4][0], "cubic")
        self.assertEqual(cmds[5][0], "cubic")
        self.assertEqual(cmds[6][0], "close")


class TestBarPlacement(unittest.TestCase):
    def setUp(self):
        self.screen = (0, 0, 1920, 1080)

    def test_edge_detection_right(self):
        # Janela próxima da borda direita (ex: x=1900, w=54 -> maxX = 1954 >= 1920)
        rect = (1890, 200, 54, 260)
        edge = BarPlacement.detect_edge(rect, self.screen)
        self.assertEqual(edge, DockEdge.RIGHT)

    def test_edge_detection_left(self):
        rect = (10, 200, 54, 260)
        edge = BarPlacement.detect_edge(rect, self.screen)
        self.assertEqual(edge, DockEdge.LEFT)

    def test_edge_detection_top(self):
        rect = (500, 15, 260, 54)
        edge = BarPlacement.detect_edge(rect, self.screen)
        self.assertEqual(edge, DockEdge.TOP)

    def test_edge_detection_bottom(self):
        rect = (500, 1050, 260, 54)
        edge = BarPlacement.detect_edge(rect, self.screen)
        self.assertEqual(edge, DockEdge.BOTTOM)

    def test_edge_detection_floating(self):
        # No meio da tela
        rect = (800, 400, 54, 260)
        edge = BarPlacement.detect_edge(rect, self.screen)
        self.assertEqual(edge, DockEdge.FLOATING)

    def test_restored_rect_docked_bounds(self):
        p = BarPlacement(x=1000, y=200, width=54, height=260, docked=True, edge=DockEdge.RIGHT)
        rx, ry, rw, rh = p.restored_rect((54, 260), self.screen)
        self.assertEqual(rx, 1920 - 54)
        self.assertEqual(ry, 200)
        self.assertEqual(rw, 54)
        self.assertEqual(rh, 260)

        p_left = BarPlacement(x=500, y=100, width=54, height=260, docked=True, edge=DockEdge.LEFT)
        rx, ry, rw, rh = p_left.restored_rect((54, 260), self.screen)
        self.assertEqual(rx, 0)
        self.assertEqual(ry, 100)


class TestProviderUsage(unittest.TestCase):
    def test_claude_operational_window(self):
        sess = UsageWindow(id="sess", label="Sessão (5 horas)", used_percent=30)
        week = UsageWindow(id="week", label="Semanal (todos os modelos)", used_percent=55)
        claude = ProviderUsage(id="claude", name="Claude", windows=[sess, week])

        # Padrão: prioriza sessão (diário por sessão)
        op_default = claude.operational_window(shows_weekly_claude=False)
        self.assertIsNotNone(op_default)
        self.assertEqual(op_default.used_percent, 30)
        self.assertEqual(op_default.id, "sess")

        # Com toggle semanal ativado
        op_weekly = claude.operational_window(shows_weekly_claude=True)
        self.assertIsNotNone(op_weekly)
        self.assertEqual(op_weekly.used_percent, 55)
        self.assertEqual(op_weekly.id, "week")

    def test_codex_operational_window(self):
        week = UsageWindow(id="week", label="Limite semanal", used_percent=19)
        codex = ProviderUsage(id="codex", name="Codex", windows=[week], reset_credits_count=2)

        op = codex.operational_window(shows_weekly_claude=False)
        self.assertIsNotNone(op)
        self.assertEqual(op.used_percent, 19)
        self.assertEqual(codex.reset_credits_count, 2)


class TestRecentProjectsScanner(unittest.TestCase):
    def test_clean_summary(self):
        raw = '<environment_context>some info</environment_context><USER_REQUEST>ajuste a barra para o windows</USER_REQUEST>'
        cleaned = RecentProjectsScanner.clean_summary(raw)
        self.assertEqual(cleaned, "ajuste a barra para o windows")

        # Teste truncamento longo
        long_raw = "Esta é uma instrução muito longa com mais de cinquenta caracteres que precisa ser resumida"
        long_cleaned = RecentProjectsScanner.clean_summary(long_raw)
        self.assertTrue(len(long_cleaned) <= 48)
        self.assertTrue(long_cleaned.endswith("…"))

        # Teste caveat
        caveat_raw = "caveat: este arquivo é restrito"
        self.assertIsNone(RecentProjectsScanner.clean_summary(caveat_raw))


class TestSettingsManager(unittest.TestCase):
    def test_save_and_load(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            old_appdata = os.environ.get("APPDATA")
            try:
                os.environ["APPDATA"] = tmpdir
                test_cfg = {
                    "dockEdge": "left",
                    "docked": True,
                    "x": 0,
                    "y": 150,
                    "refreshInterval": 30,
                    "showsWeeklyUsage": True
                }
                SettingsManager.save_settings(test_cfg)
                loaded = SettingsManager.load_settings()
                self.assertEqual(loaded["dockEdge"], "left")
                self.assertEqual(loaded["refreshInterval"], 30)
                self.assertTrue(loaded["showsWeeklyUsage"])
            finally:
                if old_appdata is not None:
                    os.environ["APPDATA"] = old_appdata
                else:
                    os.environ.pop("APPDATA", None)


if __name__ == "__main__":
    unittest.main()

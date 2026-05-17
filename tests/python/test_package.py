"""Tests for baseball/__init__.py package exports."""
from __future__ import annotations

import typer

import baseball


class TestPackageExports:
    def test_app_is_exported(self):
        assert hasattr(baseball, "app")

    def test_app_is_typer_instance(self):
        assert isinstance(baseball.app, typer.Typer)

    def test_all_contains_app(self):
        assert "app" in baseball.__all__

    def test_app_is_same_object_as_cli_app(self):
        from baseball.cli import app as cli_app
        assert baseball.app is cli_app
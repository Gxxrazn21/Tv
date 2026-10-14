import os
from pathlib import Path

from alembic import command
from alembic.config import Config
from alembic.script import ScriptDirectory
from sqlalchemy import create_engine, inspect

from openfoot.db import Base

ROOT = Path(__file__).resolve().parent.parent


def _config(url: str) -> Config:
    cfg = Config(str(ROOT / "alembic.ini"))
    cfg.set_main_option("script_location", str(ROOT / "alembic"))
    cfg.set_main_option("sqlalchemy.url", url)
    cfg.attributes["configure_logger"] = False
    return cfg


def test_single_head():
    assert len(ScriptDirectory.from_config(_config("sqlite://")).get_heads()) == 1


def test_upgrade_creates_all_tables_and_downgrade(tmp_path):
    # Con OPENFOOT_TEST_MIGRATIONS_URL se prueba sobre PostgreSQL (base vacía y desechable).
    url = os.environ.get("OPENFOOT_TEST_MIGRATIONS_URL") or f"sqlite:///{tmp_path / 'm.db'}"
    cfg = _config(url)
    command.upgrade(cfg, "head")
    tables = set(inspect(create_engine(url)).get_table_names())
    assert set(Base.metadata.tables) <= tables
    command.check(cfg)  # el modelo y las migraciones no divergen
    command.downgrade(cfg, "base")
    assert set(inspect(create_engine(url)).get_table_names()) <= {"alembic_version"}

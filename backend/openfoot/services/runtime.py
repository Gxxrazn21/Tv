"""Preparación automática y sincronización bajo demanda para entornos sin procesos en
segundo plano (por ejemplo, funciones de Vercel).

- bootstrap(): aplica las migraciones y carga el catálogo una vez por instancia.
- sync_if_stale(): si la última sincronización tiene más de N minutos, sincroniza una ventana
  corta de fechas antes de responder.

En PostgreSQL se usan bloqueos consultivos de transacción (pg_advisory_xact_lock) para que
varias instancias simultáneas no migren ni sincronicen a la vez. En SQLite basta un bloqueo
del proceso.
"""

import logging
import threading
from contextlib import contextmanager
from datetime import UTC, datetime, timedelta
from pathlib import Path

from sqlalchemy import select, text
from sqlalchemy.engine import Engine

from openfoot.config import Settings
from openfoot.models import Competition, SyncRun

log = logging.getLogger("openfoot.runtime")

BOOTSTRAP_LOCK_KEY = 72_001
SYNC_LOCK_KEY = 72_002
ROOT = Path(__file__).resolve().parents[2]

_local_locks = {BOOTSTRAP_LOCK_KEY: threading.Lock(), SYNC_LOCK_KEY: threading.Lock()}
_bootstrapped = False


@contextmanager
def try_lock(engine: Engine, key: int, *, wait: bool):
    """Devuelve True si se obtuvo el bloqueo. Con wait=False no espera si está ocupado.

    En PostgreSQL se usa un bloqueo consultivo de TRANSACCIÓN, que funciona también a través
    de poolers en modo transacción (PgBouncer, el pooler de Neon): la transacción abierta fija
    la conexión del servidor hasta el COMMIT, que libera el bloqueo.
    """
    local = _local_locks[key]
    if not local.acquire(blocking=wait):
        yield False
        return
    try:
        if engine.dialect.name != "postgresql":
            yield True
            return
        with engine.connect() as conn, conn.begin():
            if wait:
                conn.execute(text("SELECT pg_advisory_xact_lock(:k)"), {"k": key})
                got = True
            else:
                got = bool(
                    conn.execute(text("SELECT pg_try_advisory_xact_lock(:k)"), {"k": key}).scalar()
                )
            yield got
    finally:
        local.release()


def bootstrap(engine: Engine, settings: Settings, root: Path = ROOT) -> None:
    """Migra la base de datos y carga el catálogo YAML (idempotente)."""
    global _bootstrapped
    if _bootstrapped:
        return
    from alembic import command
    from alembic.config import Config
    from sqlalchemy.orm import Session

    from openfoot.services.catalog import load_catalog

    with try_lock(engine, BOOTSTRAP_LOCK_KEY, wait=True):
        if _bootstrapped:
            return
        cfg = Config(str(root / "alembic.ini"))
        cfg.set_main_option("script_location", str(root / "alembic"))
        cfg.set_main_option("sqlalchemy.url", settings.database_url.replace("%", "%%"))
        cfg.attributes["configure_logger"] = False
        command.upgrade(cfg, "head")
        with Session(engine) as session:
            counts = load_catalog(session, root / "data" / "catalog.yaml")
        log.info("Base de datos preparada; catálogo: %s", counts)
        _bootstrapped = True


def reset_bootstrap_flag() -> None:  # para pruebas
    global _bootstrapped
    _bootstrapped = False


def sync_if_stale(engine: Engine, settings: Settings, sources, now: datetime | None = None) -> bool:
    """Sincroniza si la última ejecución es más antigua que el intervalo. Devuelve True si
    sincronizó. Nunca lanza excepciones: el fallo queda registrado en sync_runs."""
    from sqlalchemy.orm import Session

    from openfoot.services.sync import sync_all

    now = now or datetime.now(UTC)
    limit = now - timedelta(minutes=settings.sync_on_request_interval_minutes)
    try:
        with Session(engine) as session:
            last = session.scalar(select(SyncRun.started_at).order_by(SyncRun.started_at.desc()))
        if last is not None and last > limit:
            return False
        with try_lock(engine, SYNC_LOCK_KEY, wait=False) as got:
            if not got:
                return False  # otra instancia ya está sincronizando
            with Session(engine, expire_on_commit=False) as session:
                last = session.scalar(
                    select(SyncRun.started_at).order_by(SyncRun.started_at.desc())
                )
                if last is not None and last > limit:
                    return False
                # Los metadatos (temporada, logos de competiciones) se piden solo si faltan:
                # normalmente los actualiza la tarea diaria.
                missing_meta = session.scalar(
                    select(Competition.id)
                    .where(
                        Competition.data_status == "available",
                        Competition.data_source.like("football-data%"),
                        Competition.emblem_url.is_(None),
                    )
                    .limit(1)
                )
                sync_all(
                    session,
                    sources,
                    days_back=settings.sync_on_request_days_back,
                    days_ahead=settings.sync_on_request_days_ahead,
                    include_meta=missing_meta is not None,
                )
        return True
    except Exception:  # noqa: BLE001 - nunca debe romper la respuesta al usuario
        log.exception("Fallo en la sincronización bajo demanda")
        return False

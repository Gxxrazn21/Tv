from datetime import UTC, datetime, timedelta

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, func, inspect, select
from sqlalchemy.orm import sessionmaker

from openfoot.config import Settings, get_settings
from openfoot.db import get_session
from openfoot.main import create_app
from openfoot.models import Competition, Match, SyncRun
from openfoot.services import runtime
from tests.conftest import make_football_data


def test_database_url_aliases_and_driver(monkeypatch):
    monkeypatch.delenv("OPENFOOT_DATABASE_URL", raising=False)
    monkeypatch.setenv("DATABASE_URL", "postgres://u:p@host/db?sslmode=require")
    monkeypatch.setenv("CRON_SECRET", "s3")
    s = Settings(_env_file=None)
    assert s.database_url == "postgresql+psycopg://u:p@host/db?sslmode=require"
    assert s.cron_secret.get_secret_value() == "s3"
    assert Settings(_env_file=None, database_url="postgresql://x/y").database_url == (
        "postgresql+psycopg://x/y"
    )
    assert Settings(_env_file=None, database_url="sqlite:///a.db").database_url == "sqlite:///a.db"


def test_bootstrap_on_empty_database(tmp_path):
    url = f"sqlite:///{tmp_path / 'b.db'}"
    engine = create_engine(url)
    runtime.reset_bootstrap_flag()
    try:
        runtime.bootstrap(engine, Settings(_env_file=None, database_url=url))
        runtime.bootstrap(engine, Settings(_env_file=None, database_url=url))  # sin efecto
        assert "matches" in inspect(engine).get_table_names()
        with sessionmaker(engine)() as s:
            assert s.scalar(select(func.count(Competition.id))) > 20
    finally:
        runtime.reset_bootstrap_flag()


def test_sync_if_stale_respects_interval(engine, loaded):
    settings = Settings(_env_file=None, sync_on_request_interval_minutes=10)
    calls = []
    src = make_football_data(calls, competitions=("PL",))
    now = datetime.now(UTC)
    assert runtime.sync_if_stale(engine, settings, [src], now=now) is True
    first = len(calls)
    assert first > 0
    # Dentro del intervalo no vuelve a llamar a la API.
    assert runtime.sync_if_stale(engine, settings, [src], now=now + timedelta(minutes=5)) is False
    assert len(calls) == first
    # Pasado el intervalo, sí.
    assert runtime.sync_if_stale(engine, settings, [src], now=now + timedelta(minutes=11)) is True
    assert len(calls) > first
    assert loaded.scalar(select(func.count(Match.id))) > 0


def test_sync_if_stale_never_raises(engine, loaded):
    class Broken:
        name = "rota"
        attribution = ""

        def is_configured(self):
            return True

        def competition_codes(self):
            raise RuntimeError("boom")

    assert runtime.sync_if_stale(engine, Settings(_env_file=None), [Broken()]) is False


def _client(engine, settings, sources):
    factory = sessionmaker(bind=engine, expire_on_commit=False)

    def _session():
        with factory() as s:
            yield s

    app = create_app(settings, sources=sources)
    app.dependency_overrides[get_session] = _session
    app.dependency_overrides[get_settings] = lambda: settings
    return TestClient(app)


def test_matches_endpoint_syncs_on_request(engine, loaded):
    settings = Settings(_env_file=None, sync_on_request=True, rate_limit_per_minute=1000)
    calls = []
    with _client(engine, settings, [make_football_data(calls, competitions=("PL",))]) as c:
        c.get("/v1/matches", params={"date_from": "2026-10-14"})
        n = len(calls)
        assert n > 0
        c.get("/v1/matches", params={"date_from": "2026-10-14"})
        assert len(calls) == n  # segunda petición: datos frescos, sin llamar a la API
        # Endpoints que no son de partidos no sincronizan.
        c.get("/v1/competitions")
        assert len(calls) == n


@pytest.mark.parametrize(
    ("secret", "header", "status"),
    [(None, "Bearer x", 404), ("correcto", None, 401), ("correcto", "Bearer otro", 401)],
)
def test_cron_requires_secret(engine, loaded, secret, header, status):
    settings = Settings(_env_file=None, cron_secret=secret, rate_limit_per_minute=1000)
    with _client(engine, settings, [make_football_data(competitions=("PL",))]) as c:
        headers = {"Authorization": header} if header else {}
        assert c.get("/internal/cron/daily", headers=headers).status_code == status


def test_cron_runs_full_sync(engine, loaded):
    settings = Settings(_env_file=None, cron_secret="correcto", rate_limit_per_minute=1000)
    calls = []
    with _client(engine, settings, [make_football_data(calls, competitions=("PL", "WC"))]) as c:
        r = c.get("/internal/cron/daily", headers={"Authorization": "Bearer correcto"})
    assert r.status_code == 200
    body = r.json()
    assert body["runs"][0]["ok"] is True
    assert set(body["scorers"]["competitions"]) <= {"PL", "WC"}
    assert any(req.url.path.endswith("/competitions") for req in calls)
    assert loaded.scalar(select(func.count(SyncRun.id))) == 1


def test_vercel_entrypoint_exposes_app(monkeypatch, tmp_path):
    import runpy
    from pathlib import Path

    monkeypatch.setenv("OPENFOOT_DATABASE_URL", f"sqlite:///{tmp_path / 'v.db'}")
    get_settings.cache_clear()
    try:
        module = runpy.run_path(str(Path(__file__).parent.parent / "index.py"))
        assert module["app"].title == "OpenFoot API"
    finally:
        get_settings.cache_clear()

import json
from datetime import date
from pathlib import Path

import httpx
import pytest
from fastapi.testclient import TestClient
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from openfoot.adapters.base import RateLimiter
from openfoot.adapters.football_data import FootballDataSource
from openfoot.adapters.openligadb import OpenLigaDBSource
from openfoot.config import Settings, get_settings
from openfoot.db import Base, get_session
from openfoot.main import create_app
from openfoot.services.catalog import load_catalog
from openfoot.services.sync import sync_all

FIXTURES = Path(__file__).parent / "fixtures"
CATALOG = Path(__file__).parent.parent / "data" / "catalog.yaml"
TODAY = date(2026, 10, 14)


def fixture(name: str):
    return json.loads((FIXTURES / name).read_text(encoding="utf-8"))


@pytest.fixture
def engine():
    from sqlalchemy import create_engine

    eng = create_engine(
        "sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool
    )
    Base.metadata.create_all(eng)
    yield eng
    eng.dispose()


@pytest.fixture
def session(engine):
    factory = sessionmaker(bind=engine, expire_on_commit=False)
    with factory() as s:
        yield s


def no_wait_limiter():
    return RateLimiter(1000, sleep=lambda _: None)


def football_data_transport(calls: list | None = None):
    def handler(request: httpx.Request) -> httpx.Response:
        if calls is not None:
            calls.append(request)
        if request.headers.get("X-Auth-Token") != "test-token":
            return httpx.Response(403, json={"message": "forbidden"})
        path = request.url.path
        if path.endswith("/competitions"):
            return httpx.Response(200, json=fixture("football_data_competitions.json"))
        if path.endswith("/matches"):
            return httpx.Response(200, json=fixture("football_data_matches.json"))
        if path.endswith("/scorers"):
            return httpx.Response(200, json=fixture("football_data_scorers.json"))
        return httpx.Response(404)

    return httpx.MockTransport(handler)


def make_football_data(calls=None, token="test-token", competitions=("PL", "WC", "BL1")):
    return FootballDataSource(
        token=token,
        competitions=list(competitions),
        transport=football_data_transport(calls),
        limiter=no_wait_limiter(),
    )


def make_openligadb(now):
    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path.startswith("/getmatchdata/bl1/"):
            return httpx.Response(200, json=fixture("openligadb_bl1.json"))
        return httpx.Response(200, json=[])

    return OpenLigaDBSource(["bl1"], transport=httpx.MockTransport(handler), now=lambda: now)


@pytest.fixture
def loaded(session):
    load_catalog(session, CATALOG)
    return session


@pytest.fixture
def synced(loaded):
    sync_all(loaded, [make_football_data(competitions=("PL", "WC"))], today=TODAY)
    return loaded


@pytest.fixture
def settings():
    return Settings(database_url="sqlite://", rate_limit_per_minute=1000)


@pytest.fixture
def client(engine, synced, settings):
    factory = sessionmaker(bind=engine, expire_on_commit=False)

    def _session():
        with factory() as s:
            yield s

    app = create_app(settings, sources=[make_football_data()])
    app.dependency_overrides[get_session] = _session
    app.dependency_overrides[get_settings] = lambda: settings
    with TestClient(app) as c:
        yield c

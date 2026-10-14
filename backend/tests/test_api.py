from datetime import UTC, date, datetime, timedelta

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import select

from openfoot.config import Settings
from openfoot.main import create_app
from openfoot.models import Broadcaster, BroadcastRight, Competition, LinkCheck, Match
from openfoot.services.watch import NO_VERIFIED_MESSAGE


def test_health(client):
    assert client.get("/health").json() == {"status": "ok"}
    assert client.get("/").json()["docs"] == "/docs"
    missing = client.get("/no-existe")
    assert missing.status_code == 404
    assert missing.json() == {"detail": "Not Found", "path": "/no-existe"}


def test_security_headers(client):
    r = client.get("/health")
    assert r.headers["x-content-type-options"] == "nosniff"
    assert r.headers["referrer-policy"] == "no-referrer"


def test_competitions(client):
    data = client.get("/v1/competitions").json()
    codes = {c["code"] for c in data}
    assert {"CL", "PL", "ARG", "CLI", "WC"} <= codes
    arg = next(c for c in data if c["code"] == "ARG")
    assert arg["data_status"] == "unavailable" and arg["data_note"]
    assert next(c for c in data if c["code"] == "CL")["has_official_directory"] is True
    sa = client.get("/v1/competitions", params={"region": "south_america"}).json()
    assert all(c["region"] == "south_america" for c in sa)
    assert client.get("/v1/competitions", params={"region": "mars"}).status_code == 422


def test_matches_by_date_respects_timezone(client):
    # 1002 es el 15/10 a las 23:30 UTC: en Buenos Aires (UTC-3) sigue siendo el 15/10,
    # en Madrid (UTC+2) ya es el 16/10.
    ba = client.get(
        "/v1/matches", params={"date_from": "2026-10-15", "tz": "America/Argentina/Buenos_Aires"}
    ).json()
    assert [m["id"] for m in ba if m["home"]["tla"] == "BAR"]
    madrid = client.get(
        "/v1/matches", params={"date_from": "2026-10-15", "tz": "Europe/Madrid"}
    ).json()
    assert not [m for m in madrid if m["home"]["tla"] == "BAR"]


def test_match_fields_and_phase(client):
    data = client.get(
        "/v1/matches", params={"date_from": "2026-10-12", "date_to": "2026-10-16"}
    ).json()
    assert len(data) == 3
    live = next(m for m in data if m["status"] == "IN_PLAY")
    assert live["phase"] == "live"
    assert live["score"] == {"home": 1, "away": 0}
    assert live["competition"]["code"] == "PL"
    # Por defecto no se sirven URL de escudos (marcas registradas).
    assert live["home"]["crest_url"] is None
    finished = client.get(
        "/v1/matches",
        params={"date_from": "2026-10-12", "date_to": "2026-10-16", "phase": "finished"},
    ).json()
    assert [m["status"] for m in finished] == ["FINISHED"]


def test_matches_filters(client):
    params = {"date_from": "2026-10-12", "date_to": "2026-10-16"}
    pl = client.get("/v1/matches", params={**params, "competition": "PL"}).json()
    assert {m["competition"]["code"] for m in pl} == {"PL"}
    gb = client.get("/v1/matches", params={**params, "country": "gb"}).json()
    assert len(gb) == 2
    team_id = pl[0]["home"]["id"]
    by_team = client.get("/v1/matches", params={**params, "team_id": team_id}).json()
    assert all(team_id in (m["home"]["id"], m["away"]["id"]) for m in by_team)


@pytest.mark.parametrize(
    "params",
    [
        {"tz": "Mars/Base"},
        {"date_from": "2026-10-10", "date_to": "2026-10-01"},
        {"date_from": "2026-01-01", "date_to": "2026-12-31"},
        {"competition": "PL;DROP TABLE"},
        {"country": "1X"},
        {"limit": 10_000},
    ],
)
def test_matches_validation(client, params):
    assert client.get("/v1/matches", params=params).status_code == 422


def test_match_detail_and_404(client):
    mid = client.get("/v1/matches", params={"date_from": "2026-10-14"}).json()[0]["id"]
    detail = client.get(f"/v1/matches/{mid}").json()
    assert detail["events"] == []
    assert client.get("/v1/matches/999999").status_code == 404


def _pl_match(session) -> Match:
    return session.scalar(
        select(Match)
        .join(Match.competition)
        .where(Competition.code == "PL", Match.status == "IN_PLAY")
    )


def _add_right(
    session,
    slug,
    country="ES",
    status="verified",
    access="subscription",
    verified_at=None,
    valid_to=None,
):
    b = Broadcaster(
        slug=slug,
        name=slug.upper(),
        website_url=f"https://www.{slug}.example/",
        official_domains=[f"{slug}.example"],
        countries=[country],
    )
    session.add(b)
    session.flush()
    comp = session.scalar(select(Competition).where(Competition.code == "PL"))
    r = BroadcastRight(
        broadcaster_id=b.id,
        competition_id=comp.id,
        country_code=country,
        season_label="2026/27",
        access_type=access,
        watch_url=f"https://www.{slug}.example/futbol",
        source_type="organizer_directory",
        source_url="https://www.premierleague.com/x",
        status=status,
        verified_at=verified_at or datetime.now(UTC),
        verified_by="test",
        valid_to=valid_to,
    )
    session.add(r)
    session.commit()
    return r


def test_watch_no_verified_source(client):
    mid = client.get("/v1/matches", params={"date_from": "2026-10-14"}).json()[0]["id"]
    data = client.get(f"/v1/matches/{mid}/watch", params={"country": "AR"}).json()
    assert data["options"] == []
    assert data["message"] == NO_VERIFIED_MESSAGE
    # La Premier League tiene directorio oficial verificado como alternativa.
    assert data["official_directory"]["url"].startswith("https://www.premierleague.com/")
    assert "no emite" in data["disclaimer"]


def test_watch_only_verified_current_and_valid(client, synced):
    m = _pl_match(synced)
    _add_right(synced, "gratis", access="free")
    _add_right(synced, "pago")
    _add_right(synced, "pendiente", status="pending_review")
    _add_right(synced, "caducado", verified_at=datetime.now(UTC) - timedelta(days=90))
    _add_right(synced, "vencido", valid_to=date(2026, 6, 30))
    roto = _add_right(synced, "roto")
    synced.add(
        LinkCheck(
            target_type="right",
            target_id=roto.id,
            url=roto.watch_url,
            checked_at=datetime.now(UTC),
            outcome="broken",
            status_code=404,
        )
    )
    _add_right(synced, "otropais", country="MX")
    synced.commit()

    data = client.get(f"/v1/matches/{m.id}/watch", params={"country": "es"}).json()
    names = [o["broadcaster"]["slug"] for o in data["options"]]
    assert names == ["gratis", "pago"]  # gratuitas primero
    assert data["options"][0]["access_type"] == "free"
    assert data["options"][1]["source_url"] == "https://www.premierleague.com/x"
    assert data["message"] is None


def test_watch_country_validation(client):
    mid = client.get("/v1/matches", params={"date_from": "2026-10-14"}).json()[0]["id"]
    assert client.get(f"/v1/matches/{mid}/watch", params={"country": "ESP"}).status_code == 422
    assert client.get(f"/v1/matches/{mid}/watch", params={"country": "1!"}).status_code == 422


def test_providers(client):
    data = client.get("/v1/providers").json()
    dr = next(p for p in data if p["slug"] == "dr")
    assert dr["verified_rights"] == 1
    sky = next(p for p in data if p["slug"] == "sky-sports-uk")
    assert sky["verified_rights"] == 0
    assert {p["slug"] for p in client.get("/v1/providers", params={"country": "SE"}).json()} == {
        "svt",
        "tv4",
    }


@pytest.mark.parametrize(
    ("q", "kind", "label"),
    [
        ("atletico", "team", "Atlético Muestra"),
        ("Ejmplo Rovers", "team", "Ejemplo Rovers FC"),
        ("premier", "competition", "Premier League"),
        ("libertadores", "competition", "CONMEBOL Libertadores"),
        ("brasil", "country", "Brasil"),
    ],
)
def test_search_fuzzy(client, q, kind, label):
    hits = client.get("/v1/search", params={"q": q}).json()["hits"]
    assert any(h["kind"] == kind and h["label"] == label for h in hits[:3]), hits[:3]


def test_search_by_date(client):
    data = client.get("/v1/search", params={"q": "14/10/2026"}).json()
    assert len(data["matches_on_date"]) == 1


def test_sources_status(client):
    data = client.get("/v1/sources").json()
    assert data[0]["name"] == "football-data.org"
    assert data[0]["configured"] is True
    assert data[0]["last_sync_ok"] is True
    assert "Football-Data.org" in data[0]["attribution"]


def test_rate_limit(engine):
    app = create_app(Settings(database_url="sqlite://", rate_limit_per_minute=3), sources=[])
    with TestClient(app) as c:
        codes = [c.get("/health").status_code for _ in range(4)]
    assert codes == [200, 200, 200, 429]


def test_errors_do_not_leak_details(engine):
    app = create_app(Settings(database_url="sqlite://"), sources=[])

    @app.get("/boom")
    def boom():
        raise RuntimeError("secreto-interno")

    with TestClient(app, raise_server_exceptions=False) as c:
        r = c.get("/boom")
    assert r.status_code == 500
    assert "secreto" not in r.text


def test_rate_limiter_prunes_stale_clients():
    from openfoot.main import RateLimiter

    rl = RateLimiter(5)
    for i in range(50_001):
        rl.allow(f"10.0.{i // 256}.{i % 256}", now=0.0)
    rl.allow("nuevo", now=120.0)
    assert len(rl._hits) == 1


def test_ready_diagnostics(engine, monkeypatch, tmp_path):
    from openfoot import db

    monkeypatch.setattr(db, "_engine", None)
    url = f"sqlite:///{tmp_path / 'r.db'}"
    settings = Settings(_env_file=None, database_url=url, auto_bootstrap=True)
    monkeypatch.setattr(db, "get_settings", lambda: settings)
    from openfoot.services import runtime

    runtime.reset_bootstrap_flag()
    try:
        with TestClient(create_app(settings, sources=[])) as c:
            r = c.get("/health/ready")
        body = r.json()
        assert r.status_code == 200, body
        assert body["database"] == "sqlite"
        assert body["files"] == {
            "alembic.ini": True,
            "alembic/versions": True,
            "data/catalog.yaml": True,
        }
        assert body["connection"] == "ok" and body["bootstrap"] == "ok"
        assert "token" not in r.text.lower() or body["football_data_configured"] is False
    finally:
        runtime.reset_bootstrap_flag()
        monkeypatch.setattr(db, "_engine", None)

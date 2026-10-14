from datetime import UTC, datetime

from sqlalchemy import func, select

from openfoot.adapters.football_data import FootballDataSource
from openfoot.models import Match, Player, Season, SyncRun, Team
from openfoot.services.sync import claimed_codes, sync_all, sync_scorers
from tests.conftest import TODAY, fixture, make_football_data, make_openligadb


def test_sync_is_idempotent(loaded):
    src = make_football_data(competitions=("PL", "WC"))
    sync_all(loaded, [src], today=TODAY)
    sync_all(loaded, [src], today=TODAY)
    assert loaded.scalar(select(func.count(Match.id))) == 3
    assert loaded.scalar(select(func.count(Team.id))) == 4  # 3 equipos + "Por determinar"
    assert loaded.scalar(select(Season).limit(1)).current_matchday == 8
    runs = loaded.scalars(select(SyncRun)).all()
    assert all(r.ok for r in runs)


def test_schedule_change_keeps_previous_date(loaded, monkeypatch):
    src = make_football_data(competitions=("PL",))
    sync_all(loaded, [src], today=TODAY)
    data = fixture("football_data_matches.json")
    data["matches"][1]["utcDate"] = "2026-10-22T19:00:00Z"
    data["matches"][1]["status"] = "POSTPONED"
    monkeypatch.setattr(
        FootballDataSource,
        "_get",
        lambda self, path, params=None: data if path == "/matches" else {"competitions": []},
    )
    sync_all(loaded, [src], today=TODAY)
    m = loaded.scalar(select(Match).where(Match.status == "POSTPONED"))
    assert m.previous_utc_date == datetime(2026, 10, 15, 23, 30, tzinfo=UTC)
    assert m.utc_date == datetime(2026, 10, 22, 19, 0, tzinfo=UTC)


def test_unconfigured_source_is_skipped(loaded):
    src = FootballDataSource(token=None, competitions=["PL"])
    assert sync_all(loaded, [src], today=TODAY) == []


def test_primary_source_claims_shared_competition():
    now = datetime(2026, 10, 14, tzinfo=UTC)
    plan = claimed_codes([make_football_data(competitions=("BL1",)), make_openligadb(now)])
    assert plan == {"football-data.org": ["BL1"], "openligadb": []}
    plan = claimed_codes([FootballDataSource(None, ["BL1"]), make_openligadb(now)])
    assert plan == {"openligadb": ["BL1"]}


def test_openligadb_events_stored(loaded):
    now = datetime(2026, 10, 14, 19, 0, tzinfo=UTC)
    sync_all(loaded, [make_openligadb(now)], today=TODAY, days_back=5)
    m = loaded.scalar(select(Match).where(Match.status == "FINISHED"))
    assert len(m.events) == 3
    sync_all(loaded, [make_openligadb(now)], today=TODAY, days_back=5)
    loaded.refresh(m)
    assert len(m.events) == 3


def test_failed_source_records_error(loaded):
    import httpx

    src = FootballDataSource(
        token="x", competitions=["PL"], transport=httpx.MockTransport(lambda r: httpx.Response(500))
    )
    runs = sync_all(loaded, [src], today=TODAY)
    assert runs[0].ok is False and "500" in runs[0].detail


def test_scorers(loaded):
    assert sync_scorers(loaded, [make_football_data(competitions=("PL",))]) == 1
    assert loaded.scalar(select(Player)).team.tla == "ATM"

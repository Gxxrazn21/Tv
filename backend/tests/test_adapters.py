from datetime import UTC, date, datetime

import httpx
import pytest

from openfoot.adapters.base import RateLimiter, SourceError, SourceNotConfigured
from openfoot.adapters.football_data import FootballDataSource
from openfoot.adapters.openligadb import season_for
from tests.conftest import make_football_data, make_openligadb, no_wait_limiter


def test_football_data_sends_token_and_parses():
    calls = []
    src = make_football_data(calls)
    matches = src.fetch_matches(date(2026, 10, 12), date(2026, 10, 16))
    assert calls[0].headers["X-Auth-Token"] == "test-token"
    assert calls[0].url.params["competitions"] == "PL,WC,BL1"
    assert calls[0].url.params["dateFrom"] == "2026-10-12"
    live = next(m for m in matches if m.external_id == "1001")
    assert live.status == "IN_PLAY"
    assert (live.home_score, live.away_score) == (1, 0)
    assert live.utc_date == datetime(2026, 10, 14, 19, 0, tzinfo=UTC)
    assert live.home.tla == "ROV"
    tbd = next(m for m in matches if m.external_id == "1003")
    assert tbd.home.external_id == "tbd"


def test_football_data_splits_ranges_over_10_days():
    calls = []
    make_football_data(calls).fetch_matches(date(2026, 10, 1), date(2026, 10, 25))
    ranges = [(c.url.params["dateFrom"], c.url.params["dateTo"]) for c in calls]
    assert ranges == [
        ("2026-10-01", "2026-10-10"),
        ("2026-10-11", "2026-10-20"),
        ("2026-10-21", "2026-10-25"),
    ]


def test_football_data_filters_competitions_not_requested():
    comps = make_football_data().fetch_competitions()
    assert [c.code for c in comps] == ["PL"]
    assert comps[0].season_start == date(2026, 8, 15)


def test_football_data_without_token():
    src = FootballDataSource(token=None, competitions=["PL"])
    assert not src.is_configured()
    with pytest.raises(SourceNotConfigured):
        src.fetch_competitions()


@pytest.mark.parametrize("code", [401, 403, 429, 500])
def test_football_data_errors(code):
    src = FootballDataSource(
        token="t",
        competitions=["PL"],
        limiter=no_wait_limiter(),
        transport=httpx.MockTransport(lambda r: httpx.Response(code)),
    )
    with pytest.raises(SourceError):
        src.fetch_competitions()


def test_scorers():
    players = make_football_data().fetch_scorers("PL")
    assert players[0].name == "Jugador Prueba"
    assert players[0].team.name == "Atlético Muestra"


def test_openligadb_parsing_and_status():
    now = datetime(2026, 10, 14, 19, 0, tzinfo=UTC)
    src = make_openligadb(now)
    matches = {m.external_id: m for m in src.fetch_matches(date(2026, 9, 30), date(2026, 10, 21))}
    finished = matches["70001"]
    assert finished.status == "FINISHED"
    assert (finished.home_score, finished.away_score) == (2, 1)
    assert [e.kind for e in finished.events] == ["goal", "penalty_goal", "own_goal"]
    assert [e.team_side for e in finished.events] == ["away", "home", "home"]
    assert finished.venue == "Musterarena, Musterstadt"
    live = matches["70002"]
    assert live.status == "IN_PLAY"
    assert (live.home_score, live.away_score) == (1, 0)
    assert matches["70003"].status == "TIMED"
    assert matches["70003"].home_score is None
    # Partido antiguo sin cerrar en la fuente: no se inventa un estado.
    assert matches["70004"].status == "UNKNOWN"


def test_openligadb_date_filter():
    now = datetime(2026, 10, 14, 12, 0, tzinfo=UTC)
    ids = {
        m.external_id
        for m in make_openligadb(now).fetch_matches(date(2026, 10, 10), date(2026, 10, 14))
    }
    assert ids == {"70001", "70002"}


def test_season_for():
    assert season_for(date(2026, 10, 1)) == 2026
    assert season_for(date(2027, 3, 1)) == 2026


def test_rate_limiter_waits():
    t = [0.0]
    sleeps = []

    def sleep(s):
        sleeps.append(s)
        t[0] += s

    rl = RateLimiter(2, 60, clock=lambda: t[0], sleep=sleep)
    rl.acquire()
    rl.acquire()
    rl.acquire()
    assert sleeps and sleeps[0] == pytest.approx(60.01)

"""Adaptador para OpenLigaDB (fuente secundaria, sin clave, datos aportados por la comunidad).

Documentación: https://api.openligadb.de/index.html
Endpoint utilizado: GET /getmatchdata/{liga}/{temporada} (temporada = año de inicio).

OpenLigaDB no publica un campo de estado del partido. El estado se deriva así y se documenta:
- matchIsFinished = true            -> FINISHED
- inicio en el futuro               -> TIMED
- inicio pasado hace menos de 3 h   -> IN_PLAY (probable; la fuente puede ir con retraso)
- inicio pasado hace más de 3 h     -> UNKNOWN (no se inventa un resultado)
"""

from datetime import UTC, date, datetime, timedelta

import httpx

from openfoot.adapters.base import (
    NCompetition,
    NEvent,
    NMatch,
    NPlayer,
    NTeam,
    RateLimiter,
    SourceError,
)

LEAGUE_CODES = {"bl1": "BL1", "bl2": "BL2", "bl3": "BL3"}
FINAL_RESULT_TYPE = 2
LIVE_WINDOW = timedelta(hours=3)


def season_for(day: date) -> int:
    return day.year if day.month >= 7 else day.year - 1


class OpenLigaDBSource:
    name = "openligadb"
    attribution = "Datos de OpenLigaDB (https://www.openligadb.de), aportados por su comunidad"

    def __init__(
        self,
        leagues: list[str],
        base_url: str = "https://api.openligadb.de",
        enabled: bool = True,
        transport: httpx.BaseTransport | None = None,
        now=lambda: datetime.now(UTC),
    ) -> None:
        self._leagues = [lg for lg in leagues if lg in LEAGUE_CODES]
        self._enabled = enabled
        self._now = now
        # Sin límite publicado: se aplica uno prudente para no sobrecargar un servicio comunitario.
        self._limiter = RateLimiter(30)
        self._client = httpx.Client(base_url=base_url, timeout=20.0, transport=transport)

    def is_configured(self) -> bool:
        return self._enabled and bool(self._leagues)

    def competition_codes(self) -> list[str]:
        return [LEAGUE_CODES[lg] for lg in self._leagues]

    def _get(self, path: str):
        self._limiter.acquire()
        try:
            resp = self._client.get(path, headers={"Accept": "application/json"})
        except httpx.HTTPError as exc:
            raise SourceError(f"{self.name}: error de red ({type(exc).__name__})") from exc
        if resp.status_code >= 400:
            raise SourceError(f"{self.name}: respuesta HTTP {resp.status_code}")
        try:
            return resp.json()
        except ValueError as exc:
            raise SourceError(f"{self.name}: respuesta no es JSON") from exc

    def fetch_competitions(self) -> list[NCompetition]:
        # Los metadatos de estas ligas están en el catálogo local; no hace falta pedirlos.
        return []

    def fetch_scorers(self, competition_code: str) -> list[NPlayer]:
        return []

    def fetch_matches(self, date_from: date, date_to: date) -> list[NMatch]:
        seasons = sorted({season_for(date_from), season_for(date_to)})
        out: list[NMatch] = []
        for league in self._leagues:
            for season in seasons:
                data = self._get(f"/getmatchdata/{league}/{season}")
                if not isinstance(data, list):
                    raise SourceError(f"{self.name}: formato inesperado")
                for raw in data:
                    m = self._parse(raw, LEAGUE_CODES[league], season)
                    if m and date_from <= m.utc_date.date() <= date_to:
                        out.append(m)
        return out

    def _status(self, finished: bool, kickoff: datetime) -> str:
        if finished:
            return "FINISHED"
        now = self._now()
        if kickoff > now:
            return "TIMED"
        if now - kickoff < LIVE_WINDOW:
            return "IN_PLAY"
        return "UNKNOWN"

    def _parse(self, raw: dict, code: str, season: int) -> NMatch | None:
        utc_raw = raw.get("matchDateTimeUTC")
        if not utc_raw or raw.get("matchID") is None:
            return None
        kickoff = datetime.fromisoformat(utc_raw.replace("Z", "+00:00"))
        if kickoff.tzinfo is None:
            kickoff = kickoff.replace(tzinfo=UTC)
        t1, t2 = raw.get("team1") or {}, raw.get("team2") or {}
        goals = sorted(raw.get("goals") or [], key=lambda g: g.get("matchMinute") or 0)
        events: list[NEvent] = []
        prev_h, prev_a = 0, 0
        for g in goals:
            h, a = g.get("scoreTeam1"), g.get("scoreTeam2")
            side = None
            if isinstance(h, int) and isinstance(a, int):
                side = "home" if h > prev_h else "away" if a > prev_a else None
                prev_h, prev_a = h, a
            kind = (
                "own_goal"
                if g.get("isOwnGoal")
                else ("penalty_goal" if g.get("isPenalty") else "goal")
            )
            events.append(NEvent(g.get("matchMinute"), kind, side, g.get("goalGetterName"), h, a))
        home_score = away_score = None
        for r in raw.get("matchResults") or []:
            if r.get("resultTypeID") == FINAL_RESULT_TYPE:
                home_score, away_score = r.get("pointsTeam1"), r.get("pointsTeam2")
        finished = bool(raw.get("matchIsFinished"))
        if home_score is None and events and not finished:
            home_score, away_score = prev_h, prev_a
        status = self._status(finished, kickoff)
        if status in ("TIMED",):
            home_score = away_score = None
        loc = raw.get("location") or {}
        venue = ", ".join(x for x in (loc.get("locationStadium"), loc.get("locationCity")) if x)
        group = raw.get("group") or {}
        return NMatch(
            external_id=str(raw["matchID"]),
            competition_code=code,
            utc_date=kickoff,
            status=status,
            home=NTeam(
                str(t1.get("teamId")),
                t1.get("teamName") or "?",
                t1.get("shortName"),
                None,
                t1.get("teamIconUrl"),
                "Germany",
            ),
            away=NTeam(
                str(t2.get("teamId")),
                t2.get("teamName") or "?",
                t2.get("shortName"),
                None,
                t2.get("teamIconUrl"),
                "Germany",
            ),
            matchday=group.get("groupOrderID"),
            stage=group.get("groupName"),
            venue=venue or None,
            home_score=home_score,
            away_score=away_score,
            events=events,
            has_events=True,
        )

"""Adaptador para football-data.org API v4 (fuente principal).

Documentación: https://docs.football-data.org/general/v4/index.html
Autenticación: cabecera X-Auth-Token con la clave gratuita obtenida al registrarse.
Atribución exigida: "Football data provided by the Football-Data.org API".
"""

from datetime import date, datetime, timedelta

import httpx

from openfoot.adapters.base import (
    NCompetition,
    NMatch,
    NPlayer,
    NTeam,
    RateLimiter,
    SourceError,
    SourceNotConfigured,
)

# El endpoint /matches admite como máximo 10 días por consulta.
MAX_RANGE_DAYS = 10

KNOWN_STATUSES = {
    "SCHEDULED",
    "TIMED",
    "IN_PLAY",
    "PAUSED",
    "FINISHED",
    "POSTPONED",
    "SUSPENDED",
    "CANCELLED",
    "AWARDED",
}


def _parse_dt(value: str | None) -> datetime | None:
    if not value:
        return None
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def _parse_date(value: str | None) -> date | None:
    return date.fromisoformat(value) if value else None


def _team(raw: dict | None) -> NTeam:
    raw = raw or {}
    if raw.get("id") is None:
        # Eliminatorias con rival por decidir: la API devuelve id null.
        return NTeam(external_id="tbd", name="Por determinar")
    return NTeam(
        external_id=str(raw["id"]),
        name=raw.get("name") or raw.get("shortName") or "?",
        short_name=raw.get("shortName"),
        tla=raw.get("tla"),
        crest_url=raw.get("crest"),
    )


class FootballDataSource:
    name = "football-data.org"
    attribution = "Football data provided by the Football-Data.org API"

    def __init__(
        self,
        token: str | None,
        competitions: list[str],
        base_url: str = "https://api.football-data.org/v4",
        requests_per_minute: int = 8,
        transport: httpx.BaseTransport | None = None,
        limiter: RateLimiter | None = None,
    ) -> None:
        self._token = token
        self._competitions = competitions
        self._limiter = limiter or RateLimiter(requests_per_minute)
        self._client = httpx.Client(base_url=base_url, timeout=20.0, transport=transport)

    def is_configured(self) -> bool:
        return bool(self._token)

    def competition_codes(self) -> list[str]:
        return list(self._competitions)

    def _get(self, path: str, params: dict | None = None) -> dict:
        if not self._token:
            raise SourceNotConfigured("Falta OPENFOOT_FOOTBALL_DATA_TOKEN")
        self._limiter.acquire()
        try:
            resp = self._client.get(path, params=params, headers={"X-Auth-Token": self._token})
        except httpx.HTTPError as exc:
            raise SourceError(f"{self.name}: error de red ({type(exc).__name__})") from exc
        if resp.status_code == 429:
            raise SourceError(f"{self.name}: límite de solicitudes alcanzado")
        if resp.status_code in (401, 403):
            raise SourceError(
                f"{self.name}: acceso denegado ({resp.status_code}); la clave no es válida o la "
                "competición no está incluida en el plan"
            )
        if resp.status_code >= 400:
            raise SourceError(f"{self.name}: respuesta HTTP {resp.status_code}")
        try:
            return resp.json()
        except ValueError as exc:
            raise SourceError(f"{self.name}: respuesta no es JSON") from exc

    def fetch_competitions(self) -> list[NCompetition]:
        data = self._get("/competitions")
        wanted = set(self._competitions)
        out = []
        for c in data.get("competitions", []):
            if c.get("code") not in wanted:
                continue
            season = c.get("currentSeason") or {}
            area = c.get("area") or {}
            out.append(
                NCompetition(
                    external_id=str(c["id"]),
                    code=c["code"],
                    name=c.get("name") or c["code"],
                    area_name=area.get("name"),
                    area_code=area.get("code"),
                    kind={"LEAGUE": "league", "CUP": "cup"}.get(c.get("type") or "", None),
                    emblem_url=c.get("emblem"),
                    season_start=_parse_date(season.get("startDate")),
                    season_end=_parse_date(season.get("endDate")),
                    current_matchday=season.get("currentMatchday"),
                )
            )
        return out

    def fetch_matches(self, date_from: date, date_to: date) -> list[NMatch]:
        out: list[NMatch] = []
        start = date_from
        while start <= date_to:
            end = min(start + timedelta(days=MAX_RANGE_DAYS - 1), date_to)
            data = self._get(
                "/matches",
                {
                    "competitions": ",".join(self._competitions),
                    "dateFrom": start.isoformat(),
                    "dateTo": end.isoformat(),
                },
            )
            out.extend(self._parse_match(m) for m in data.get("matches", []))
            start = end + timedelta(days=1)
        return [m for m in out if m is not None]

    def _parse_match(self, m: dict) -> NMatch | None:
        utc = _parse_dt(m.get("utcDate"))
        comp = (m.get("competition") or {}).get("code")
        if utc is None or not comp:
            return None
        status = m.get("status") if m.get("status") in KNOWN_STATUSES else "SCHEDULED"
        full = ((m.get("score") or {}).get("fullTime")) or {}
        season = m.get("season") or {}
        return NMatch(
            external_id=str(m["id"]),
            competition_code=comp,
            utc_date=utc,
            status=status,
            home=_team(m.get("homeTeam")),
            away=_team(m.get("awayTeam")),
            matchday=m.get("matchday"),
            stage=m.get("stage"),
            group_name=m.get("group"),
            venue=m.get("venue"),
            home_score=full.get("home"),
            away_score=full.get("away"),
            source_updated_at=_parse_dt(m.get("lastUpdated")),
            season_start=_parse_date(season.get("startDate")),
        )

    def fetch_scorers(self, competition_code: str) -> list[NPlayer]:
        data = self._get(f"/competitions/{competition_code}/scorers", {"limit": 20})
        out = []
        for s in data.get("scorers", []):
            p = s.get("player") or {}
            if p.get("id") is None:
                continue
            out.append(
                NPlayer(
                    external_id=str(p["id"]),
                    name=p.get("name") or "?",
                    nationality=p.get("nationality"),
                    position=p.get("section") or p.get("position"),
                    team=_team(s.get("team")) if s.get("team") else None,
                )
            )
        return out

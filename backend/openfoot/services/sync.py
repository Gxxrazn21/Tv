"""Sincronización de fuentes externas hacia la base de datos (que actúa como caché)."""

import logging
from datetime import UTC, date, datetime, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from openfoot.adapters.base import DataSource, NCompetition, NMatch, NPlayer, NTeam, SourceError
from openfoot.models import (
    Competition,
    ExternalRef,
    Match,
    MatchEvent,
    Player,
    Season,
    SyncRun,
    Team,
)

log = logging.getLogger("openfoot.sync")


def _now() -> datetime:
    return datetime.now(UTC)


def _lookup(session: Session, source: str, entity_type: str, external_id: str) -> int | None:
    return session.scalar(
        select(ExternalRef.entity_id).where(
            ExternalRef.source == source,
            ExternalRef.entity_type == entity_type,
            ExternalRef.external_id == external_id,
        )
    )


def _link(session: Session, source: str, entity_type: str, external_id: str, entity_id: int):
    session.add(
        ExternalRef(
            source=source, entity_type=entity_type, external_id=external_id, entity_id=entity_id
        )
    )


def upsert_team(session: Session, source: str, t: NTeam) -> Team:
    if t.external_id == "tbd":
        team = session.scalar(select(Team).where(Team.name == "Por determinar", Team.tla.is_(None)))
        if team is None:
            team = Team(name="Por determinar")
            session.add(team)
            session.flush()
        return team
    team_id = _lookup(session, source, "team", t.external_id)
    team = session.get(Team, team_id) if team_id else None
    if team is None:
        team = Team(name=t.name)
        session.add(team)
        session.flush()
        _link(session, source, "team", t.external_id, team.id)
    team.name = t.name
    team.short_name = t.short_name or team.short_name
    team.tla = t.tla or team.tla
    team.crest_url = t.crest_url or team.crest_url
    team.country = t.country or team.country
    return team


def upsert_competition_meta(session: Session, source: str, c: NCompetition) -> None:
    comp = session.scalar(select(Competition).where(Competition.code == c.code))
    if comp is None:
        # Solo se actualizan competiciones del catálogo; no se crean desde la API.
        log.info("Competición %s no está en el catálogo; se ignora", c.code)
        return
    if _lookup(session, source, "competition", c.external_id) is None:
        _link(session, source, "competition", c.external_id, comp.id)
    comp.emblem_url = c.emblem_url or comp.emblem_url
    if c.season_start:
        season = session.scalar(
            select(Season).where(
                Season.competition_id == comp.id, Season.start_date == c.season_start
            )
        )
        if season is None:
            season = Season(competition_id=comp.id, start_date=c.season_start)
            session.add(season)
        season.end_date = c.season_end
        season.current_matchday = c.current_matchday


def upsert_match(session: Session, source: str, m: NMatch, fetched_at: datetime) -> Match | None:
    comp = session.scalar(select(Competition).where(Competition.code == m.competition_code))
    if comp is None:
        return None
    home = upsert_team(session, source, m.home)
    away = upsert_team(session, source, m.away)
    match_id = _lookup(session, source, "match", m.external_id)
    match = session.get(Match, match_id) if match_id else None
    if match is None:
        match = Match(
            competition_id=comp.id,
            utc_date=m.utc_date,
            status=m.status,
            home_team_id=home.id,
            away_team_id=away.id,
            source=source,
            fetched_at=fetched_at,
        )
        session.add(match)
        session.flush()
        _link(session, source, "match", m.external_id, match.id)
    elif match.utc_date != m.utc_date:
        # Cambio de horario o aplazamiento: se conserva la fecha anterior.
        match.previous_utc_date = match.utc_date
        match.utc_date = m.utc_date
    season_id = None
    if m.season_start:
        season_id = session.scalar(
            select(Season.id).where(
                Season.competition_id == comp.id, Season.start_date == m.season_start
            )
        )
    match.season_id = season_id or match.season_id
    match.status = m.status
    match.matchday = m.matchday
    match.stage = m.stage
    match.group_name = m.group_name
    match.venue = m.venue or match.venue
    match.home_team_id = home.id
    match.away_team_id = away.id
    match.home_score = m.home_score
    match.away_score = m.away_score
    match.source_updated_at = m.source_updated_at
    match.fetched_at = fetched_at
    if m.has_events:
        match.events.clear()
        for e in m.events:
            match.events.append(
                MatchEvent(
                    minute=e.minute,
                    kind=e.kind,
                    team_side=e.team_side,
                    player_name=e.player_name,
                    score_home=e.score_home,
                    score_away=e.score_away,
                )
            )
    return match


def upsert_player(session: Session, source: str, p: NPlayer) -> Player:
    pid = _lookup(session, source, "player", p.external_id)
    player = session.get(Player, pid) if pid else None
    if player is None:
        player = Player(name=p.name)
        session.add(player)
        session.flush()
        _link(session, source, "player", p.external_id, player.id)
    player.name = p.name
    player.nationality = p.nationality
    player.position = p.position
    if p.team:
        player.team_id = upsert_team(session, source, p.team).id
    return player


def claimed_codes(sources: list[DataSource]) -> dict[str, list[str]]:
    """Asigna cada competición a la primera fuente configurada que la cubre."""
    taken: set[str] = set()
    plan: dict[str, list[str]] = {}
    for src in sources:
        if not src.is_configured():
            continue
        mine = [c for c in src.competition_codes() if c not in taken]
        taken.update(mine)
        plan[src.name] = mine
    return plan


def sync_all(
    session: Session,
    sources: list[DataSource],
    *,
    days_back: int = 3,
    days_ahead: int = 7,
    include_meta: bool = True,
    today: date | None = None,
) -> list[SyncRun]:
    today = today or _now().date()
    plan = claimed_codes(sources)
    runs: list[SyncRun] = []
    for src in sources:
        if src.name not in plan:
            continue
        codes = set(plan[src.name])
        run = SyncRun(source=src.name, started_at=_now())
        session.add(run)
        try:
            fetched_at = _now()
            if include_meta:
                for c in src.fetch_competitions():
                    if c.code in codes:
                        upsert_competition_meta(session, src.name, c)
                session.flush()
            matches = src.fetch_matches(
                today - timedelta(days=days_back), today + timedelta(days=days_ahead)
            )
            count = 0
            for m in matches:
                if m.competition_code in codes and upsert_match(session, src.name, m, fetched_at):
                    count += 1
            run.matches_upserted = count
            run.ok = True
        except SourceError as exc:
            session.rollback()
            run = SyncRun(source=src.name, started_at=run.started_at, ok=False, detail=str(exc))
            session.add(run)
            log.warning("Fallo al sincronizar %s: %s", src.name, exc)
        run.finished_at = _now()
        session.commit()
        runs.append(run)
    return runs


def sync_scorers(session: Session, sources: list[DataSource]) -> int:
    plan = claimed_codes(sources)
    total = 0
    for src in sources:
        for code in plan.get(src.name, []):
            try:
                players = src.fetch_scorers(code)
            except SourceError as exc:
                log.warning("Goleadores %s/%s: %s", src.name, code, exc)
                continue
            for p in players:
                upsert_player(session, src.name, p)
                total += 1
            session.commit()
    return total

from datetime import date, datetime, time, timedelta
from typing import Annotated
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session, joinedload, selectinload

from openfoot import schemas as s
from openfoot.config import Settings, get_settings
from openfoot.db import get_session
from openfoot.models import (
    Broadcaster,
    BroadcastRight,
    Competition,
    LinkCheck,
    Match,
    OfficialDirectory,
    SyncRun,
)
from openfoot.services.runtime import bootstrap, sync_if_stale
from openfoot.services.search import parse_date_query, search
from openfoot.services.watch import resolve_watch

SessionDep = Annotated[Session, Depends(get_session)]
SettingsDep = Annotated[Settings, Depends(get_settings)]


def ensure_ready(session: SessionDep, settings: SettingsDep) -> None:
    """Con OPENFOOT_AUTO_BOOTSTRAP: migra y carga el catálogo en el primer uso."""
    if settings.auto_bootstrap:
        bootstrap(session.get_bind(), settings)


def ensure_fresh(request: Request, session: SessionDep, settings: SettingsDep) -> None:
    """Con OPENFOOT_SYNC_ON_REQUEST: sincroniza si los datos están desactualizados."""
    if settings.sync_on_request:
        sync_if_stale(session.get_bind(), settings, request.app.state.sources)


router = APIRouter(prefix="/v1", dependencies=[Depends(ensure_ready)])
FreshDep = Depends(ensure_fresh)

DISCLAIMER = (
    "OpenFoot no emite ni redistribuye señales. Enlaza a páginas de proveedores cuya relación "
    "con la competición y el territorio se ha verificado manualmente. La disponibilidad final, "
    "el precio y las restricciones dependen de cada proveedor. Que OpenFoot sea gratuito no "
    "significa que todos los proveedores lo sean."
)
MAX_RANGE_DAYS = 31
PHASE_STATUSES = {
    "live": ["IN_PLAY", "PAUSED"],
    "upcoming": ["SCHEDULED", "TIMED"],
    "finished": ["FINISHED", "AWARDED"],
    "postponed": ["POSTPONED", "SUSPENDED"],
    "cancelled": ["CANCELLED"],
    "unknown": ["UNKNOWN"],
}


def _zone(tz: str) -> ZoneInfo:
    try:
        return ZoneInfo(tz)
    except (ZoneInfoNotFoundError, ValueError) as exc:
        raise HTTPException(422, "Zona horaria IANA no válida") from exc


def _codes(raw: str | None) -> list[str]:
    if not raw:
        return []
    codes = [c.strip().upper() for c in raw.split(",") if c.strip()]
    if len(codes) > 30 or any(not c.isalnum() or len(c) > 20 for c in codes):
        raise HTTPException(422, "Lista de códigos no válida")
    return codes


def _country(raw: str) -> str:
    if len(raw) != 2 or not raw.isascii() or not raw.isalpha():
        raise HTTPException(422, "El país debe ser un código ISO 3166-1 alfa-2")
    return raw.upper()


def team_out(team, settings: Settings) -> s.TeamOut:
    return s.TeamOut(
        id=team.id,
        name=team.name,
        short_name=team.short_name,
        tla=team.tla,
        crest_url=team.crest_url if settings.serve_crest_urls else None,
    )


def comp_ref(c: Competition) -> s.CompetitionRef:
    return s.CompetitionRef(
        code=c.code, name=c.name, region=c.region, area_name=c.area_name, area_code=c.area_code
    )


def match_out(m: Match, settings: Settings) -> s.MatchOut:
    return s.MatchOut(
        id=m.id,
        competition=comp_ref(m.competition),
        utc_date=m.utc_date,
        previous_utc_date=m.previous_utc_date,
        status=m.status,
        phase=s.phase_of(m.status),
        matchday=m.matchday,
        stage=m.stage,
        group=m.group_name,
        venue=m.venue,
        home=team_out(m.home_team, settings),
        away=team_out(m.away_team, settings),
        score=s.Score(home=m.home_score, away=m.away_score),
        source=m.source,
        source_updated_at=m.source_updated_at,
        fetched_at=m.fetched_at,
    )


def check_out(c: LinkCheck | None) -> s.LinkCheckOut | None:
    if c is None:
        return None
    return s.LinkCheckOut(checked_at=c.checked_at, outcome=c.outcome, status_code=c.status_code)


def _match_query():
    return select(Match).options(
        joinedload(Match.competition), joinedload(Match.home_team), joinedload(Match.away_team)
    )


@router.get("/competitions", response_model=list[s.CompetitionOut])
def list_competitions(
    session: SessionDep,
    settings: SettingsDep,
    region: str | None = Query(None, pattern="^(europe|south_america|international)$"),
):
    q = select(Competition).order_by(Competition.featured.desc(), Competition.name)
    if region:
        q = q.where(Competition.region == region)
    with_dir = set(
        session.scalars(
            select(OfficialDirectory.competition_id).where(OfficialDirectory.status == "verified")
        )
    )
    return [
        s.CompetitionOut(
            **comp_ref(c).model_dump(),
            kind=c.kind,
            gender=c.gender,
            data_status=c.data_status,
            data_source=c.data_source,
            data_note=c.data_note,
            featured=c.featured,
            emblem_url=c.emblem_url if settings.serve_crest_urls else None,
            has_official_directory=c.id in with_dir,
        )
        for c in session.scalars(q)
    ]


@router.get("/matches", response_model=list[s.MatchOut], dependencies=[FreshDep])
def list_matches(
    session: SessionDep,
    settings: SettingsDep,
    date_from: date | None = None,
    date_to: date | None = None,
    tz: str = Query("UTC", max_length=64),
    competition: str | None = Query(None, max_length=400),
    country: str | None = Query(None, max_length=2),
    team_id: int | None = Query(None, ge=1),
    phase: str | None = Query(
        None, pattern="^(live|upcoming|finished|postponed|cancelled|unknown)$"
    ),
    limit: int = Query(200, ge=1, le=500),
    offset: int = Query(0, ge=0),
):
    zone = _zone(tz)
    today = datetime.now(zone).date()
    date_from = date_from or today
    date_to = date_to or date_from
    if date_to < date_from or (date_to - date_from).days > MAX_RANGE_DAYS:
        raise HTTPException(422, f"Rango de fechas no válido (máximo {MAX_RANGE_DAYS} días)")
    start = datetime.combine(date_from, time.min, zone)
    end = datetime.combine(date_to + timedelta(days=1), time.min, zone)
    q = _match_query().join(Match.competition).where(Match.utc_date >= start, Match.utc_date < end)
    codes = _codes(competition)
    if codes:
        q = q.where(Competition.code.in_(codes))
    if country:
        q = q.where(Competition.area_code == _country(country))
    if team_id:
        q = q.where(or_(Match.home_team_id == team_id, Match.away_team_id == team_id))
    if phase:
        q = q.where(Match.status.in_(PHASE_STATUSES[phase]))
    q = q.order_by(Match.utc_date, Match.id).limit(limit).offset(offset)
    return [match_out(m, settings) for m in session.scalars(q).unique()]


@router.get("/teams/{team_id}/matches", response_model=list[s.MatchOut], dependencies=[FreshDep])
def team_matches(
    team_id: int,
    session: SessionDep,
    settings: SettingsDep,
    upcoming: bool = True,
    limit: int = Query(10, ge=1, le=50),
):
    now = datetime.now(ZoneInfo("UTC"))
    q = _match_query().where(or_(Match.home_team_id == team_id, Match.away_team_id == team_id))
    if upcoming:
        q = q.where(Match.utc_date >= now - timedelta(hours=3)).order_by(Match.utc_date)
    else:
        q = q.where(Match.utc_date < now).order_by(Match.utc_date.desc())
    return [match_out(m, settings) for m in session.scalars(q.limit(limit)).unique()]


def _get_match(session: Session, match_id: int) -> Match:
    m = session.scalar(
        _match_query().options(selectinload(Match.events)).where(Match.id == match_id)
    )
    if m is None:
        raise HTTPException(404, "Partido no encontrado")
    return m


@router.get("/matches/{match_id}", response_model=s.MatchDetailOut, dependencies=[FreshDep])
def get_match(match_id: int, session: SessionDep, settings: SettingsDep):
    m = _get_match(session, match_id)
    base = match_out(m, settings).model_dump()
    return s.MatchDetailOut(
        **base,
        events=[
            s.EventOut(
                minute=e.minute,
                kind=e.kind,
                team_side=e.team_side,
                player_name=e.player_name,
                score_home=e.score_home,
                score_away=e.score_away,
            )
            for e in m.events
        ],
    )


@router.get("/matches/{match_id}/watch", response_model=s.WatchOut)
def watch(
    match_id: int,
    session: SessionDep,
    settings: SettingsDep,
    country: str = Query(..., min_length=2, max_length=2),
):
    country = _country(country)
    m = _get_match(session, match_id)
    res = resolve_watch(session, m, country, settings.verification_ttl_days)
    options = [
        s.WatchOptionOut(
            broadcaster=s.BroadcasterOut(
                slug=r.broadcaster.slug,
                name=r.broadcaster.name,
                website_url=r.broadcaster.website_url,
            ),
            access_type=r.access_type,
            price_note=r.price_note,
            territorial_notes=r.territorial_notes,
            coverage_note=r.coverage_note,
            watch_url=r.watch_url,
            embed_allowed=r.embed_allowed,
            season=r.season_label,
            source_type=r.source_type,
            source_url=r.source_url,
            verified_at=r.verified_at,
            verified_by=r.verified_by or "",
            last_check=check_out(chk),
        )
        for r, chk in res.rights
    ]
    directory = None
    if res.directory is not None:
        directory = s.DirectoryOut(
            organizer=res.directory.organizer,
            url=res.directory.url,
            verified_at=res.directory.verified_at,
            last_check=check_out(res.directory_check),
        )
    return s.WatchOut(
        match_id=m.id,
        country=country,
        options=options,
        official_directory=directory,
        message=res.message,
        disclaimer=DISCLAIMER,
    )


@router.get("/providers", response_model=list[s.ProviderOut])
def providers(session: SessionDep, country: str | None = Query(None, max_length=2)):
    counts = dict(
        session.execute(
            select(BroadcastRight.broadcaster_id, func.count())
            .where(BroadcastRight.status == "verified")
            .group_by(BroadcastRight.broadcaster_id)
        ).all()
    )
    out = []
    code = _country(country) if country else None
    for b in session.scalars(select(Broadcaster).order_by(Broadcaster.name)):
        if code and code not in b.countries:
            continue
        out.append(
            s.ProviderOut(
                slug=b.slug,
                name=b.name,
                website_url=b.website_url,
                countries=b.countries,
                official_domains=b.official_domains,
                verified_rights=counts.get(b.id, 0),
            )
        )
    return out


@router.get("/search", response_model=s.SearchOut)
def search_endpoint(
    session: SessionDep,
    settings: SettingsDep,
    q: str = Query(..., min_length=2, max_length=80),
    tz: str = Query("UTC", max_length=64),
    limit: int = Query(20, ge=1, le=50),
):
    on_date = parse_date_query(q)
    matches: list[s.MatchOut] = []
    if on_date:
        matches = list_matches(
            session,
            settings,
            date_from=on_date,
            date_to=on_date,
            tz=tz,
            competition=None,
            country=None,
            team_id=None,
            phase=None,
            limit=200,
            offset=0,
        )
    hits = [s.SearchHitOut(**h.__dict__) for h in search(session, q, limit)]
    return s.SearchOut(query=q, hits=hits, matches_on_date=matches)


@router.get("/sources", response_model=list[s.SourceStatusOut])
def sources(request: Request, session: SessionDep):
    out = []
    for src in request.app.state.sources:
        last = session.scalar(
            select(SyncRun)
            .where(SyncRun.source == src.name)
            .order_by(SyncRun.started_at.desc(), SyncRun.id.desc())
            .limit(1)
        )
        out.append(
            s.SourceStatusOut(
                name=src.name,
                configured=src.is_configured(),
                attribution=src.attribution,
                competitions=src.competition_codes(),
                last_sync_at=last.finished_at if last else None,
                last_sync_ok=last.ok if last else None,
                last_sync_detail=last.detail if last else None,
            )
        )
    return out

"""Búsqueda tolerante a errores ortográficos sobre equipos, jugadores, competiciones y países."""

import re
import unicodedata
from dataclasses import dataclass
from datetime import date

from rapidfuzz import fuzz, process
from sqlalchemy import select
from sqlalchemy.orm import Session

from openfoot.models import Competition, Player, Team

MIN_SCORE = 70.0
DATE_PATTERNS = (
    (re.compile(r"^(\d{4})-(\d{1,2})-(\d{1,2})$"), ("y", "m", "d")),
    (re.compile(r"^(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})$"), ("d", "m", "y")),
)


def fold(text: str) -> str:
    """Minúsculas y sin acentos, para comparar 'Atlético' con 'atletico'."""
    norm = unicodedata.normalize("NFKD", text)
    return "".join(c for c in norm if not unicodedata.combining(c)).casefold().strip()


def parse_date_query(q: str) -> date | None:
    q = q.strip()
    for pattern, order in DATE_PATTERNS:
        m = pattern.match(q)
        if m:
            parts = dict(zip(order, (int(x) for x in m.groups()), strict=True))
            try:
                return date(parts["y"], parts["m"], parts["d"])
            except ValueError:
                return None
    return None


@dataclass
class Hit:
    kind: str  # team|player|competition|country
    id: str
    label: str
    detail: str | None
    score: float


def search(session: Session, q: str, limit: int = 20) -> list[Hit]:
    query = fold(q)
    if len(query) < 2:
        return []
    # (tipo, id, texto con el que se compara, etiqueta mostrada, detalle)
    items: list[tuple[str, str, str, str, str | None]] = []
    for t in session.scalars(select(Team).where(Team.name != "Por determinar")):
        for alias in {t.name, t.short_name, t.tla} - {None}:
            items.append(("team", str(t.id), alias, t.name, t.country))
    for p in session.scalars(select(Player)):
        detail = p.team.name if p.team else p.nationality
        items.append(("player", str(p.id), p.name, p.name, detail))
    countries: dict[str, str] = {}
    for c in session.scalars(select(Competition)):
        items.append(("competition", c.code, c.name, c.name, c.area_name))
        if c.area_code:
            countries[c.area_code] = c.area_name
    for code, name in countries.items():
        items.append(("country", code, name, name, None))

    choices = [fold(i[2]) for i in items]
    matches = process.extract(
        query, choices, scorer=fuzz.WRatio, limit=limit * 3, score_cutoff=MIN_SCORE
    )
    best: dict[tuple[str, str], Hit] = {}
    for _, score, idx in matches:
        kind, id_, _text, label, detail = items[idx]
        # Coincidencia por prefijo: se prioriza sobre similitudes parciales.
        if choices[idx].startswith(query):
            score = max(score, 99.0)
        key = (kind, id_)
        if key not in best or best[key].score < score:
            best[key] = Hit(kind, id_, label, detail, round(float(score), 1))
    return sorted(best.values(), key=lambda h: (-h.score, h.label))[:limit]

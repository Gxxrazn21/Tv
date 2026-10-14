"""Herramienta de administración: `openfoot <comando>`.

La administración se hace por línea de comandos (no hay endpoints de administración expuestos
en la API pública), lo que reduce la superficie de ataque.
"""

import argparse
import logging
import sys
from datetime import UTC, datetime
from pathlib import Path

from sqlalchemy import select

from openfoot.config import get_settings
from openfoot.db import session_factory
from openfoot.models import BroadcastRight, LinkCheck, OfficialDirectory

ROOT = Path(__file__).resolve().parent.parent


def cmd_init_db(args) -> int:
    from alembic import command
    from alembic.config import Config

    cfg = Config(str(ROOT / "alembic.ini"))
    cfg.set_main_option("script_location", str(ROOT / "alembic"))
    command.upgrade(cfg, "head")
    print("Base de datos migrada a la última versión.")
    return 0


def cmd_load_catalog(args) -> int:
    from openfoot.services.catalog import load_catalog

    with session_factory()() as session:
        for path in args.paths:
            counts = load_catalog(session, Path(path))
            print(f"{path}: {counts}")
    return 0


def cmd_sync(args) -> int:
    from openfoot.adapters.registry import build_sources
    from openfoot.services.sync import sync_all, sync_scorers

    settings = get_settings()
    sources = build_sources(settings)
    with session_factory()() as session:
        runs = sync_all(session, sources, days_back=args.days_back, days_ahead=args.days_ahead)
        if not runs:
            print("Ninguna fuente configurada. Revisa OPENFOOT_FOOTBALL_DATA_TOKEN / OpenLigaDB.")
            return 1
        for r in runs:
            state = "OK" if r.ok else "ERROR"
            print(f"{r.source}: {state} · {r.matches_upserted} partidos · {r.detail or ''}")
        if args.scorers:
            print(f"Jugadores actualizados: {sync_scorers(session, sources)}")
    return 0 if all(r.ok for r in runs) else 2


def cmd_check_links(args) -> int:
    from openfoot.services.linkcheck import LinkChecker

    settings = get_settings()
    now = datetime.now(UTC)
    with (
        session_factory()() as session,
        LinkChecker(
            timeout=settings.link_check_timeout_seconds,
            max_redirects=settings.link_check_max_redirects,
            user_agent=settings.link_check_user_agent,
        ) as checker,
    ):
        targets = [
            ("right", r.id, r.watch_url, r.broadcaster.official_domains)
            for r in session.scalars(
                select(BroadcastRight).where(BroadcastRight.status != "rejected")
            )
        ]
        targets += [
            ("directory", d.id, d.url, d.official_domains)
            for d in session.scalars(select(OfficialDirectory))
        ]
        for kind, tid, url, domains in targets:
            res = checker.check(url, domains)
            session.add(
                LinkCheck(
                    target_type=kind,
                    target_id=tid,
                    url=url,
                    checked_at=now,
                    outcome=res.outcome,
                    status_code=res.status_code,
                    final_url=res.final_url,
                    redirect_chain=res.redirect_chain,
                    detail=res.detail,
                )
            )
            print(
                f"[{res.outcome:>16}] {kind}#{tid} {url} {res.status_code or ''} {res.detail or ''}"
            )
        session.commit()
    return 0


def _review_target(session, kind: str, target_id: int):
    model = BroadcastRight if kind == "right" else OfficialDirectory
    row = session.get(model, target_id)
    if row is None:
        raise SystemExit(f"No existe {kind}#{target_id}")
    return row


def cmd_review(args) -> int:
    settings = get_settings()
    now = datetime.now(UTC)
    with session_factory()() as session:
        if args.action == "list":
            for r in session.scalars(select(BroadcastRight).order_by(BroadcastRight.id)):
                expired = (
                    r.status == "verified"
                    and r.verified_at is not None
                    and (now - r.verified_at).days > settings.verification_ttl_days
                )
                flag = "CADUCADO" if expired else r.status
                print(
                    f"right#{r.id} [{flag}] {r.competition.code} {r.country_code} "
                    f"{r.broadcaster.name} ({r.season_label}) fuente={r.source_url}"
                )
                if r.review_note:
                    print(f"    nota: {r.review_note}")
            for d in session.scalars(select(OfficialDirectory)):
                print(f"directory#{d.id} [{d.status}] {d.competition.code} {d.url}")
            return 0
        row = _review_target(session, args.kind, args.id)
        if args.action == "approve":
            if not args.by:
                raise SystemExit("--by es obligatorio para aprobar")
            row.status = "verified"
            row.verified_at = now
            row.verified_by = args.by
            row.review_note = args.note or row.review_note
        else:
            row.status = "rejected"
            row.review_note = args.note or "Rechazado en revisión"
        session.commit()
        print(f"{args.kind}#{args.id} -> {row.status}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="openfoot", description="Administración de OpenFoot")
    sub = p.add_subparsers(dest="command", required=True)

    sub.add_parser("init-db", help="Aplica las migraciones").set_defaults(func=cmd_init_db)

    lc = sub.add_parser("load-catalog", help="Carga ficheros YAML del catálogo")
    lc.add_argument("paths", nargs="+")
    lc.set_defaults(func=cmd_load_catalog)

    sy = sub.add_parser("sync", help="Sincroniza partidos desde las fuentes configuradas")
    sy.add_argument("--days-back", type=int, default=get_settings().sync_days_back)
    sy.add_argument("--days-ahead", type=int, default=get_settings().sync_days_ahead)
    sy.add_argument("--scorers", action="store_true", help="Actualiza también goleadores")
    sy.set_defaults(func=cmd_sync)

    sub.add_parser("check-links", help="Comprueba los enlaces del catálogo").set_defaults(
        func=cmd_check_links
    )

    rv = sub.add_parser("review", help="Revisión manual de derechos y directorios")
    rv.add_argument("action", choices=["list", "approve", "reject"])
    rv.add_argument("kind", nargs="?", choices=["right", "directory"])
    rv.add_argument("id", nargs="?", type=int)
    rv.add_argument("--by", help="Quién verifica (obligatorio al aprobar)")
    rv.add_argument("--note", help="Nota de revisión o motivo del rechazo")
    rv.set_defaults(func=cmd_review)
    return p


def main(argv: list[str] | None = None) -> int:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s %(message)s")
    args = build_parser().parse_args(argv)
    if args.command == "review" and args.action != "list" and (not args.kind or not args.id):
        print("Indica el tipo (right|directory) y el id", file=sys.stderr)
        return 2
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())

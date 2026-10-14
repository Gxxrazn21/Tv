import logging
import threading
import time
from collections import defaultdict, deque
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from openfoot.adapters.registry import build_sources
from openfoot.api.routes import router
from openfoot.config import Settings, get_settings
from openfoot.db import session_factory

log = logging.getLogger("openfoot")


class RateLimiter:
    """Límite por cliente en memoria (ventana deslizante). Para varias réplicas, usar el proxy."""

    def __init__(self, per_minute: int):
        self.per_minute = per_minute
        self._hits: dict[str, deque[float]] = defaultdict(deque)
        self._lock = threading.Lock()

    def allow(self, key: str, now: float | None = None) -> tuple[bool, int]:
        now = time.monotonic() if now is None else now
        with self._lock:
            q = self._hits[key]
            while q and now - q[0] >= 60:
                q.popleft()
            if len(q) >= self.per_minute:
                return False, int(60 - (now - q[0])) + 1
            q.append(now)
            if len(self._hits) > 50_000:  # evita crecimiento ilimitado de memoria
                for k in [k for k, v in self._hits.items() if not v]:
                    del self._hits[k]
            return True, 0


def _scheduler_loop(app: FastAPI, settings: Settings, stop: threading.Event) -> None:
    from openfoot.services.sync import sync_all

    while not stop.is_set():
        try:
            with session_factory()() as session:
                sync_all(
                    session,
                    app.state.sources,
                    days_back=settings.sync_days_back,
                    days_ahead=settings.sync_days_ahead,
                )
        except Exception:  # noqa: BLE001 - el planificador no debe morir
            log.exception("Fallo en la sincronización programada")
        stop.wait(settings.sync_interval_minutes * 60)


def create_app(settings: Settings | None = None, sources=None) -> FastAPI:
    settings = settings or get_settings()

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        stop = threading.Event()
        thread = None
        if settings.scheduler_enabled:
            thread = threading.Thread(
                target=_scheduler_loop,
                args=(app, settings, stop),
                daemon=True,
                name="openfoot-sync",
            )
            thread.start()
        yield
        stop.set()

    app = FastAPI(
        title="OpenFoot API",
        version="0.1.0",
        description="Calendario de fútbol y catálogo verificado de transmisiones oficiales.",
        lifespan=lifespan,
    )
    app.state.sources = sources if sources is not None else build_sources(settings)
    limiter = RateLimiter(settings.rate_limit_per_minute)

    @app.middleware("http")
    async def guard(request: Request, call_next):
        key = request.client.host if request.client else "unknown"
        if settings.trust_forwarded_for:
            fwd = request.headers.get("x-forwarded-for")
            if fwd:
                key = fwd.split(",")[0].strip()[:64]
        ok, retry = limiter.allow(key)
        if not ok:
            return JSONResponse(
                {"detail": "Demasiadas solicitudes"},
                status_code=429,
                headers={"Retry-After": str(retry)},
            )
        response = await call_next(request)
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["Referrer-Policy"] = "no-referrer"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["Cache-Control"] = response.headers.get("Cache-Control", "no-store")
        return response

    @app.exception_handler(Exception)
    async def unhandled(request: Request, exc: Exception):
        # Se registra el tipo de error y la ruta, sin cabeceras ni parámetros del cliente.
        log.error("Error no controlado en %s: %s", request.url.path, type(exc).__name__)
        return JSONResponse({"detail": "Error interno"}, status_code=500)

    @app.get("/health")
    def health():
        return {"status": "ok"}

    app.include_router(router)
    return app


def app_factory() -> FastAPI:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
    return create_app()

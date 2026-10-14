"""Punto de entrada para Vercel (preset FastAPI): Vercel busca `app` en index.py.

Vercel enruta todas las peticiones a esta app por sí mismo; no hacen falta reescrituras.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from openfoot.main import app_factory  # noqa: E402

app = app_factory()

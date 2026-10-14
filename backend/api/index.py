"""Punto de entrada para Vercel (Python runtime). Expone la app ASGI como `app`."""

import sys
from pathlib import Path

# La raíz del proyecto (backend/) debe estar en el path para importar el paquete openfoot.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from openfoot.main import app_factory  # noqa: E402

app = app_factory()

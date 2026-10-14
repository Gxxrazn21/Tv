FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app

RUN useradd --create-home --uid 10001 openfoot
COPY pyproject.toml ./
COPY openfoot ./openfoot
COPY alembic ./alembic
COPY alembic.ini ./
COPY data ./data
RUN pip install --no-cache-dir .

USER openfoot
EXPOSE 8000
# Sin registro de accesos: no se guardan IP ni rutas de cada solicitud.
CMD ["sh", "-c", "openfoot init-db && openfoot load-catalog data/catalog.yaml && uvicorn --factory openfoot.main:app_factory --host 0.0.0.0 --port 8000 --no-access-log --proxy-headers"]

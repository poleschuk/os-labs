FROM python:3.12-alpine AS builder

WORKDIR /build
COPY requirements.txt .

RUN pip install --no-cache-dir --prefix=/install -r requirements.txt


FROM python:3.12-alpine

ARG LAB_LOGIN
ARG LAB_TOKEN
LABEL org.lab.login="${LAB_LOGIN}" \
      org.lab.token="${LAB_TOKEN}" \
      org.opencontainers.image.title="image-lab" \
      org.opencontainers.image.description="Prod Flask image for lab"


ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    ROCKET_SIZE=Normal

RUN addgroup -S app && adduser -S -G app -u 10001 app

WORKDIR /app


COPY --from=builder /install /usr/local

COPY --chown=app:app app/ /app/

USER app

EXPOSE 8000


HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8000/health >/dev/null || exit 1


CMD ["gunicorn", \
     "--bind", "0.0.0.0:8000", \
     "--workers", "2", \
     "--graceful-timeout", "20", \
     "--worker-tmp-dir", "/dev/shm", \
     "app:app"]
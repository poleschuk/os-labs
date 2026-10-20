# Отчёт по лабораторной №2

## https://hub.docker.com/repository/docker/wellingtontech/image-lab

## 1. Метаданные

| Поле | Значение |
|---|---|
| Docker ID (login) | `wellingtontech` |
| Тег образа | `833a301d` |
| Полное имя образа | `wellingtontech/image-lab:833a301d` |
| Ссылка на Docker Hub | https://hub.docker.com/repository/docker/wellingtontech/image-lab |
| Размер образа | `92.8 MB`
| Базовый образ | `python:3.12-alpine` |
| Runtime-сервер | `gunicorn` |

---

## 2. Dockerfile

```dockerfile
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
```

## 3. docker history 

```text
IMAGE          CREATED          CREATED BY                                      SIZE      COMMENT
48812e5ed8d5   12 minutes ago   CMD ["gunicorn" "--bind" "0.0.0.0:8000" "--wΓÇª   0B        buildkit.dockerfile.v0
<missing>      12 minutes ago   HEALTHCHECK {Test:[CMD-SHELL wget -qO- http:ΓÇª   0B        buildkit.dockerfile.v0
<missing>      12 minutes ago   EXPOSE [8000/tcp]                               0B        buildkit.dockerfile.v0
<missing>      12 minutes ago   USER app                                        0B        buildkit.dockerfile.v0
<missing>      12 minutes ago   COPY --chown=app:app app/ /app/ # buildkit      12.3kB    buildkit.dockerfile.v0
<missing>      12 minutes ago   COPY /install /usr/local # buildkit             7.62MB    buildkit.dockerfile.v0
<missing>      12 minutes ago   WORKDIR /app                                    8.19kB    buildkit.dockerfile.v0
<missing>      12 minutes ago   RUN |2 LAB_LOGIN=wellingtontech LAB_TOKEN=83ΓÇª   41kB      buildkit.dockerfile.v0
<missing>      12 minutes ago   ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERΓÇª   0B        buildkit.dockerfile.v0
<missing>      12 minutes ago   LABEL org.lab.login=wellingtontech org.lab.tΓÇª   0B        buildkit.dockerfile.v0
<missing>      12 minutes ago   ARG LAB_TOKEN=833a301d643da10e2584012c0de7abΓÇª   0B        buildkit.dockerfile.v0
<missing>      12 minutes ago   ARG LAB_LOGIN=wellingtontech                    0B        buildkit.dockerfile.v0
<missing>      2 weeks ago      CMD ["python3"]                                 0B        buildkit.dockerfile.v0
<missing>      2 weeks ago      RUN /bin/sh -c set -eux;  for src in idle3 pΓÇª   16.4kB    buildkit.dockerfile.v0
<missing>      2 weeks ago      RUN /bin/sh -c set -eux;   apk add --no-cachΓÇª   50.4MB    buildkit.dockerfile.v0
<missing>      2 weeks ago      ENV PYTHON_SHA256=c2c4321961fab0fb999d66e0ceΓÇª   0B        buildkit.dockerfile.v0
<missing>      2 weeks ago      ENV PYTHON_VERSION=3.12.15                      0B        buildkit.dockerfile.v0
<missing>      2 weeks ago      ENV GPG_KEY=7169605F62C751356D054A26A821E680ΓÇª   0B        buildkit.dockerfile.v0
<missing>      2 weeks ago      RUN /bin/sh -c set -eux;  apk add --no-cacheΓÇª   2.83MB    buildkit.dockerfile.v0
<missing>      2 weeks ago      ENV LANG=C.UTF-8                                0B        buildkit.dockerfile.v0
<missing>      2 weeks ago      ENV PATH=/usr/local/bin:/usr/local/sbin:/usrΓÇª   0B        buildkit.dockerfile.v0
<missing>      4 weeks ago      CMD ["/bin/sh"]                                 0B        buildkit.dockerfile.v0
<missing>      4 weeks ago      ADD alpine-minirootfs-3.24.2-x86_64.tar.gz /ΓÇª   9.08MB    buildkit.dockerfile.v0
```

## 4. Чем образ лучше «наивной» сборки

Наивная сборка — это один `FROM python:3.12`, `pip install -r requirements.txt`, `CMD python app.py`, запуск под root, без healthcheck. Мой образ отличается по восьми пунктам.

1. **Multi-stage + `--prefix=/install`.** В финальный образ попадают только установленные пакеты и код приложения, а не сам `pip`, кэш колёс и промежуточные файлы. Это уменьшает образ в 2–3 раза по сравнению с наивной сборкой.
2. **База `python:3.12-alpine` вместо `python:3.12`.** Alpine-база срезает размер с ~800 MB до ~90 MB, что даёт итоговый размер `92.8  MB` — с большим запасом укладывается в лимит 150 MB.
3. **Non-root пользователь `app` (UID 10001).** Даже если процесс Flask/gunicorn скомпрометирован, атакующий получит урезанные права внутри контейнера. Наивный образ обычно работает под root.
4. **`HEALTHCHECK` на `/health`.** Docker сам опрашивает эндпоинт и помечает контейнер как `unhealthy`, если тот «залип». Это даёт оркестратору сигнал на перезапуск, чего в наивной сборке нет вовсе.
5. **`exec`-форма `CMD` с gunicorn.** Gunicorn запускается как PID 1 и получает `SIGTERM` напрямую, выполняет graceful shutdown за ~1–2 секунды. Наивный `CMD python app.py` либо не обрабатывает сигнал, либо завершается по таймауту `docker stop` (10 с).
6. **Совместимость с `--read-only`.** `--worker-tmp-dir /dev/shm` уводит временные файлы gunicorn в `tmpfs`.
7. **Конфиг через `ENV` без пересборки.** `ROCKET_SIZE` читается на старте процесса — один и тот же образ подходит для dev/staging/prod с разными значениями, не нужно собирать отдельный образ на каждое окружение.
8. **`LABEL` через `--build-arg`.** Пара `org.lab.login` / `org.lab.token` позволяет однозначно идентифицировать сборку, а сами значения не хардкодятся в Dockerfile — образ пересобирается под другой seed одной командой без правки файла.

---

## Проверка на read-only

```text
/app $ ls
app.py
/app $ touch app.py
touch: app.py: Read-only file system
/app $
```

##  Healthcheck
```text
PS C:\Engineering\study\os\lab2> curl.exe -s http://localhost:8080/health;
{"status":"ok","uptime":1648.28}
PS C:\Engineering\study\os\lab2> curl.exe -s http://localhost:8080;       
Hello from Docker! Rocket=Big
PS C:\Engineering\study\os\lab2> 
```
## Read-Only docker run
```text
PS C:\Engineering\study\os\lab2> docker stop lab                                                                                         
lab
PS C:\Engineering\study\os\lab2> docker run -d --rm --name lab --read-only -e ROCKET_SIZE=Big -p 8080:8000 "${LOGIN}/image-lab:${PREFIX}"

2747a627614c8b3f21095271c7867092fc3f59e916fcae5247f19e518f1af464                                                     
PS C:\Engineering\study\os\lab2> curl.exe -s http://localhost:8080/health;
{"status":"ok","uptime":29.83}
PS C:\Engineering\study\os\lab2> curl.exe -s http://localhost:8080/;      
Hello from Docker! Rocket=Big
PS C:\Engineering\study\os\lab2> 
```
## Gunicorn логи запуск и остановка

```text
PS C:\Engineering\study\os> docker logs -f lab
[2026-10-20 17:10:33 +0000] [1] [INFO] Starting gunicorn 22.0.0
[2026-10-20 17:10:33 +0000] [1] [INFO] Listening at: http://0.0.0.0:8000 (1)
[2026-10-20 17:10:33 +0000] [1] [INFO] Using worker: sync
[2026-10-20 17:10:33 +0000] [7] [INFO] Booting worker with pid: 7
[2026-10-20 17:10:33 +0000] [8] [INFO] Booting worker with pid: 8
[2026-10-20 17:10:54 +0000] [1] [INFO] Handling signal: term
Shutting down...
Shutting down...
[2026-10-20 17:10:54 +0000] [7] [INFO] Worker exiting (pid: 7)
[2026-10-20 17:10:54 +0000] [8] [INFO] Worker exiting (pid: 8)
[2026-10-20 17:10:55 +0000] [1] [INFO] Shutting down: Master
```
---
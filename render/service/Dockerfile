# Render service image: fluidsynth + the nagma_core/nagma_render packages.
# Build context is the repo root:  docker build -f render/service/Dockerfile .
FROM python:3.11-slim

# fluidsynth for sampling; libsndfile for soundfile I/O.
RUN apt-get update && apt-get install -y --no-install-recommends \
        fluidsynth libsndfile1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Contracts + both Python packages. app/ and assets (except soundfonts) excluded.
COPY contracts/ ./contracts/
COPY core/ ./core/
COPY render/ ./render/
COPY assets/soundfonts/ ./assets/soundfonts/

RUN pip install --no-cache-dir -e ./core -e "./render[service]"

# Point the service at the bundled soundfont; override at deploy time.
ENV NAGMA_SOUNDFONT=/app/assets/soundfonts/harmonium.sf2
ENV NAGMA_CACHE_DIR=/data/cache
VOLUME ["/data/cache"]
EXPOSE 8000

CMD ["uvicorn", "nagma_render.service.app:app", "--host", "0.0.0.0", "--port", "8000"]

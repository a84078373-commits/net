FROM python:3.12-slim

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    SMARTCARE_DB=/var/data/smartcare.sqlite3 \
    SMARTCARE_SPEED_ENABLED=1 \
    SMARTCARE_PUBLIC_ORIGIN=https://net-71nf.onrender.com \
    SMARTCARE_CORS=https://net-71nf.onrender.com,http://localhost:8080,http://127.0.0.1:8080

RUN mkdir -p /var/data

COPY backend/requirements.txt /app/backend/requirements.txt
RUN pip install --no-cache-dir -r /app/backend/requirements.txt

COPY backend /app/backend

EXPOSE 10000
CMD ["sh", "-c", "gunicorn -b 0.0.0.0:${PORT:-10000} -w 1 --threads 8 --timeout 120 backend.flask_app:app"]

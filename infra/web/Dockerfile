FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8000

# 2 workers is plenty for a classroom; sqlite is the shared state on a mounted volume.
CMD ["gunicorn", "-w", "2", "-b", "0.0.0.0:8000", "app:app"]

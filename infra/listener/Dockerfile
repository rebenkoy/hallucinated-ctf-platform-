FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 80
# one process (shared in-memory HITS deque) but many threads: each open Listener tab holds
# a websocket thread while beacons keep landing. Bump threads if a big class runs out.
CMD ["gunicorn", "-w", "1", "--threads", "32", "-b", "0.0.0.0:80", "app:app"]

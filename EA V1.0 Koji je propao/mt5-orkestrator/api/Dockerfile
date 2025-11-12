FROM python:3.11-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Simple healthcheck
HEALTHCHECK CMD python -c "import socket; s=socket.socket(); s.connect(('127.0.0.1',8000))" || exit 1

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]

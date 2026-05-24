FROM python:3.11-slim

WORKDIR /app

# System dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies first (better layer caching)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Install Azure Blob Storage SDK for artifact download at startup
RUN pip install --no-cache-dir azure-storage-blob

# Copy application source
COPY src/ ./src/
COPY scripts/ ./scripts/
COPY conftest.py .

# Create directories that artifacts will be downloaded into
RUN mkdir -p data/processed mlruns/production

# Expose port
EXPOSE 8000

# Startup: download artifacts from Azure Blob, then launch API server
CMD ["sh", "-c", "python scripts/download_artifacts.py && uvicorn src.serving.serve:app --host 0.0.0.0 --port 8000 --workers 1"]

"""
download_artifacts.py
---------------------
Downloads ML model + FAISS artifacts from Azure Blob Storage to local paths
expected by model_loader.py.  Called once at container startup.

Env vars required (set in Azure App Service Configuration):
  AZURE_STORAGE_CONNECTION_STRING  — full connection string from Azure portal
  AZURE_BLOB_CONTAINER             — blob container name (default: cip-artifacts)

If AZURE_STORAGE_CONNECTION_STRING is not set the script exits silently,
allowing local development to work without any cloud dependency.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Artifact blobs  →  local destination paths
ARTIFACT_MAP = {
    "model/model.pkl":          ROOT / "mlruns" / "production" / "model.pkl",
    "faiss/faiss_index.bin":    ROOT / "data" / "processed" / "faiss_index.bin",
    "faiss/faiss_metadata.json": ROOT / "data" / "processed" / "faiss_metadata.json",
    "faiss/feature_manifest.json": ROOT / "data" / "processed" / "feature_manifest.json",
}


def main() -> None:
    conn_str = os.getenv("AZURE_STORAGE_CONNECTION_STRING", "")
    if not conn_str:
        print("[download_artifacts] AZURE_STORAGE_CONNECTION_STRING not set — skipping download (local mode).")
        return

    container = os.getenv("AZURE_BLOB_CONTAINER", "cip-artifacts")

    try:
        from azure.storage.blob import BlobServiceClient
    except ImportError:
        print("[download_artifacts] azure-storage-blob not installed. Run: pip install azure-storage-blob")
        sys.exit(1)

    client = BlobServiceClient.from_connection_string(conn_str)
    container_client = client.get_container_client(container)

    for blob_name, local_path in ARTIFACT_MAP.items():
        local_path.parent.mkdir(parents=True, exist_ok=True)
        if local_path.exists():
            print(f"[download_artifacts] Already exists, skipping: {local_path.name}")
            continue
        print(f"[download_artifacts] Downloading {blob_name} → {local_path} ...")
        blob_client = container_client.get_blob_client(blob_name)
        with open(local_path, "wb") as f:
            data = blob_client.download_blob()
            data.readinto(f)
        print(f"[download_artifacts] ✓ {local_path.name} ({local_path.stat().st_size // 1024} KB)")

    print("[download_artifacts] All artifacts ready.")


if __name__ == "__main__":
    main()

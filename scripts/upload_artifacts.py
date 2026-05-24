"""
upload_artifacts.py
-------------------
One-time script: uploads your locally-trained model + FAISS artifacts
to Azure Blob Storage so the App Service container can download them at startup.

Usage:
  python scripts/upload_artifacts.py

Env vars required:
  AZURE_STORAGE_CONNECTION_STRING  — from Azure portal → Storage Account → Access keys
  AZURE_BLOB_CONTAINER             — container name (default: cip-artifacts)
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def find_model_pkl() -> Path | None:
    """Find the most recently modified model.pkl in mlruns/."""
    mlruns = ROOT / "mlruns"
    if not mlruns.exists():
        return None
    candidates = (
        list(mlruns.glob("**/model/model.pkl")) +
        list(mlruns.glob("**/models/m-*/artifacts/model.pkl")) +
        list(mlruns.glob("*/models/m-*/artifacts/model.pkl"))
    )
    if not candidates:
        return None
    return max(candidates, key=lambda p: p.stat().st_mtime)


UPLOAD_MAP: dict[str, Path] = {
    "faiss/faiss_index.bin":        ROOT / "data" / "processed" / "faiss_index.bin",
    "faiss/faiss_metadata.json":    ROOT / "data" / "processed" / "faiss_metadata.json",
    "faiss/feature_manifest.json":  ROOT / "data" / "processed" / "feature_manifest.json",
}


def main() -> None:
    conn_str = os.getenv("AZURE_STORAGE_CONNECTION_STRING", "")
    if not conn_str:
        print("ERROR: AZURE_STORAGE_CONNECTION_STRING env var not set.")
        print("  Set it to the connection string from Azure Portal → Storage Account → Access keys")
        sys.exit(1)

    try:
        from azure.storage.blob import BlobServiceClient, ContainerClient
    except ImportError:
        print("ERROR: Run  pip install azure-storage-blob  first.")
        sys.exit(1)

    container = os.getenv("AZURE_BLOB_CONTAINER", "cip-artifacts")
    client = BlobServiceClient.from_connection_string(conn_str)

    # Create container if it doesn't exist
    try:
        client.create_container(container)
        print(f"[upload] Created container: {container}")
    except Exception:
        print(f"[upload] Container '{container}' already exists — OK")

    container_client: ContainerClient = client.get_container_client(container)

    # Find and add model.pkl dynamically
    model_path = find_model_pkl()
    if model_path:
        UPLOAD_MAP["model/model.pkl"] = model_path
        print(f"[upload] Found model: {model_path}")
    else:
        print("WARNING: model.pkl not found. Run train.py first.")

    # Upload all artifacts
    for blob_name, local_path in UPLOAD_MAP.items():
        if not local_path.exists():
            print(f"WARNING: Skipping missing file: {local_path}")
            continue
        size_kb = local_path.stat().st_size // 1024
        print(f"[upload] Uploading {local_path.name} ({size_kb} KB) → {blob_name} ...")
        with open(local_path, "rb") as f:
            container_client.upload_blob(blob_name, f, overwrite=True)
        print(f"[upload] ✓ {blob_name}")

    print("\n[upload] All artifacts uploaded successfully!")
    print(f"  Container: {container}")
    print("  Set AZURE_STORAGE_CONNECTION_STRING in your App Service Configuration.")


if __name__ == "__main__":
    main()

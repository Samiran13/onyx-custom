#!/usr/bin/env python3
import json
import subprocess
import os
from pathlib import Path

# Change only if your Postgres container name is different
POSTGRES_CONTAINER = "onyx-relational_db-1"
USE_SUDO = True  # set False if your docker doesn't require sudo


def run_postgres_query():
    """
    Runs SELECT query inside the Postgres container via docker exec.
    Returns raw JSON text and parsed list of rows.
    """
    query = r"""
    SELECT 
        id,
        semantic_id,
        chunk_count,
        from_ingestion_api,
        hidden,
        boost,
        link,
        doc_updated_at
    FROM document
    ORDER BY doc_updated_at DESC;
    """

    # Build command
    base_cmd = []
    if USE_SUDO:
        base_cmd.append("sudo")

    base_cmd += [
        "docker", "exec", "-i",
        POSTGRES_CONTAINER,
        "psql",
        "-U", "postgres",
        "-d", "postgres",
        "-t", "-A", "-F", "|",
        "-c", query
    ]

    # Run
    result = subprocess.run(
        base_cmd,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )

    raw_output = result.stdout.strip()
    rows = []

    if raw_output:
        for line in raw_output.split("\n"):
            fields = line.split("|")
            if len(fields) < 8:
                continue
            rows.append({
                "id": fields[0],
                "semantic_id": fields[1],
                "chunk_count": int(fields[2]) if fields[2] else None,
                "from_ingestion_api": fields[3] == "t",
                "hidden": fields[4] == "t",
                "boost": int(fields[5]) if fields[5] else None,
                "link": fields[6],
                "doc_updated_at": fields[7],
            })

    return raw_output, rows


def save_json(raw_text: str, rows: list):
    """
    Saves both raw SQL output + parsed JSON.
    """
    os.makedirs("outputs", exist_ok=True)

    raw_path = Path("outputs/postgres_raw.json")
    pretty_path = Path("outputs/postgres_pretty.json")

    # Save raw form
    # raw_path.write_text(raw_text)
    # print(f"💾 Saved raw Postgres output → {raw_path}")

    # Save pretty JSON
    pretty_path.write_text(json.dumps(rows, indent=2))
    print(f"💾 Saved pretty JSON → {pretty_path}")

    return pretty_path


def main():
    print("=== Fetching Postgres `document` table entries ===")

    try:
        raw_text, rows = run_postgres_query()
    except Exception as e:
        print("❌ ERROR running Postgres query")
        print(e)
        return

    save_json(raw_text, rows)

    print(f"\nFound {len(rows)} documents.")
    print("Top 3 documents:")
    for doc in rows[:3]:
        print(json.dumps(doc, indent=2))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
import json
import subprocess
import sys
import os
from pathlib import Path


DOCKER_CONTAINER = "onyx-index-1"
USE_SUDO = True  # change to False if sudo is not required


def run_docker_curl(semantic_identifier: str, hits: int = 400) -> dict:
    """
    Execute a Vespa query inside the onyx-index-1 container and return parsed JSON.
    """
    base_cmd = []
    if USE_SUDO:
        base_cmd.append("sudo")
    base_cmd += [
        "docker",
        "exec",
        DOCKER_CONTAINER,
        "curl",
        "-s",
        "http://localhost:8081/search/",
        "--data-urlencode",
        f'yql=select * from sources danswer_index where semantic_identifier contains "{semantic_identifier}";',
        "--data-urlencode",
        f"hits={hits}",
        "--data-urlencode",
        "format=json",
    ]

    result = subprocess.run(
        base_cmd,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    try:
        json_data = json.loads(result.stdout)
    except Exception as e:
        print("❌ ERROR: Unable to decode JSON response from Vespa.")
        print("Output:", result.stdout[:500])
        raise e

    return json_data, result.stdout


def save_json_files(semantic_identifier: str, raw_text: str, json_data: dict):
    """
    Save both raw JSON and pretty JSON to outputs/<filename>.json
    """
    os.makedirs("outputs", exist_ok=True)

    safe_name = semantic_identifier.replace(" ", "_").replace("/", "_")

    raw_path = Path(f"outputs/{safe_name}.raw.json")
    pretty_path = Path(f"outputs/{safe_name}.pretty.json")

    # # Save raw JSON
    # raw_path.write_text(raw_text)
    # print(f"💾 Saved raw JSON → {raw_path}")

    # Save pretty JSON
    pretty_path.write_text(json.dumps(json_data, indent=2))
    print(f"💾 Saved pretty JSON → {pretty_path}")

    return raw_path, pretty_path


def summarize_chunks(semantic_identifier: str):
    print(f"=== Checking chunks for semantic_identifier: '{semantic_identifier}' ===")

    # 1. Call Vespa
    json_data, raw_text = run_docker_curl(semantic_identifier)

    # 2. Save raw + pretty JSON
    save_json_files(semantic_identifier, raw_text, json_data)

    root = json_data.get("root", {})
    errors = root.get("errors")
    if errors:
        print("❌ Vespa returned error(s):")
        for err in errors:
            print(f"  [{err.get('code')}] {err.get('summary')}: {err.get('message')}")
        return

    children = root.get("children", [])
    total_count = root.get("fields", {}).get("totalCount", len(children))

    print(f"Total hits: {len(children)}  |  totalCount: {total_count}")

    if not children:
        print("⚠️ No chunks found.")
        return

    # Gather chunk details
    chunk_ids = set()
    content_lengths = []
    examples = {}

    for child in children:
        fields = child.get("fields", {})
        cid = fields.get("chunk_id")
        if cid is not None:
            chunk_ids.add(cid)
            if cid not in examples:
                examples[cid] = fields
            content_lengths.append(len(fields.get("content", "")))

    chunk_ids = sorted(chunk_ids)

    print("\nLogical chunks:")
    print(f"  Unique chunk_ids: {len(chunk_ids)}")
    print(f"  Range: {chunk_ids[0]} → {chunk_ids[-1]}")
    if chunk_ids == list(range(chunk_ids[0], chunk_ids[-1] + 1)):
        print("  ✔ No gaps — all chunks present.")
    else:
        print("  ❌ Missing chunk IDs!")

    print("\nChunk content lengths:")
    print(f"  Min: {min(content_lengths)} chars")
    print(f"  Max: {max(content_lengths)} chars")
    print(f"  Avg: {sum(content_lengths)/len(content_lengths):.1f} chars")

    # Sample chunk
    first_cid = chunk_ids[0]
    sample = examples[first_cid]

    print("\nSample chunk metadata:")
    print(json.dumps(sample, indent=2)[:1000])

    print("\nDone.")


def main():
    if len(sys.argv) < 2:
        print("Usage: ./check_vespa_chunks.py \"filename.pdf\"")
        sys.exit(1)

    semantic_identifier = sys.argv[1].strip()
    summarize_chunks(semantic_identifier)


if __name__ == "__main__":
    main()

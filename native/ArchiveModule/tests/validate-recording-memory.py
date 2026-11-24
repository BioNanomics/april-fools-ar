#!/usr/bin/env python3
"""Bound save/reopen memory with synthetic metadata and a 160 MiB sidecar.

Requires macOS Swift and FFmpeg. Stops a failing child at 256 MiB RSS rather
than letting the original autorelease regression exhaust the host's memory.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import time


REPOSITORY = Path(__file__).resolve().parents[3]
MAX_RSS_KIB = 256 * 1024
SOURCES = (
    "native/ArchiveModule/SessionMP4Writer.swift",
    "native/ArchiveModule/SavedRecordingStore.swift",
    "native/ArchiveModule/VideoOrientation.swift",
    "native/ArchiveModule/tests/ValidateSavedRecording.swift",
)


def digest_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def prepare(executable, sessions, source, recordings, work, label):
    peak = 0
    stdout, stderr = work / (label + ".json"), work / (label + ".stderr")
    with stdout.open("w") as output, stderr.open("w") as errors:
        child = subprocess.Popen([str(executable), "--prepare", str(sessions),
                                  str(source), str(recordings)], stdout=output, stderr=errors)
        try:
            deadline = time.monotonic() + 45
            while child.poll() is None:
                sample = subprocess.run(["ps", "-o", "rss=", "-p", str(child.pid)],
                                        capture_output=True, text=True, check=False)
                if sample.stdout.strip():
                    peak = max(peak, int(sample.stdout.strip()))
                if peak > MAX_RSS_KIB:
                    raise AssertionError(f"{label}: RSS exceeded 256 MiB ({peak / 1024:.1f} MiB)")
                if time.monotonic() > deadline:
                    raise AssertionError(f"{label}: preparation exceeded 45 seconds")
                time.sleep(0.05)
            if child.returncode != 0:
                raise AssertionError(f"{label} failed: {stderr.read_text()}")
        finally:
            if child.poll() is None:
                child.kill()
            child.wait()
    assert peak > 0, "Memory sampler did not observe the export process"
    print(f"PASS: {label}, sampled peak RSS {peak / 1024:.1f} MiB (<256 MiB)")
    return json.loads(stdout.read_text())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-ref", help="Compile a Git revision to demonstrate the regression")
    parser.add_argument("--keep", type=Path, help="Retain fixtures in this NEW directory")
    arguments = parser.parse_args()
    work = arguments.keep or Path(tempfile.mkdtemp(prefix="april-recording-memory-"))
    if arguments.keep:
        work.mkdir(parents=True, exist_ok=False)
    work = work.resolve()
    try:
        spec = importlib.util.spec_from_file_location("mp4_fixtures", Path(__file__).with_name("validate-mp4.py"))
        fixtures = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(fixtures)
        sessions = work / "sessions"
        sessions.mkdir()
        source, _, _, manifest = fixtures.fixture(sessions, faststart=False)
        # Dense floating-point metadata exercises Foundation's scalar serializer;
        # the sparse sidecar separately exercises bounded streaming and hashing.
        values = [0.38682788610458374 + index / 1000 for index in range(512)]
        events = source / "events.jsonl"
        with events.open("w") as output:
            for index in range(500):
                record = {"type": "aprilTagDetections", "frameId": f"frame-{index}",
                          "timestamp": 12000.125 + index / 30, "analysisSucceeded": True,
                          "detections": [{"id": 4, "debug": {"samples": values}}]}
                output.write(json.dumps(record, separators=(",", ":")) + "\n")
        sidecar = source / "streaming-sidecar.bin"
        with sidecar.open("wb") as output:
            output.truncate(160 * 1024 * 1024)
        inventory = manifest["fileInventory"]
        inventory[:] = [entry for entry in inventory if entry["path"] != events.name]
        for path in (events, sidecar):
            inventory.append({"path": path.name, "bytes": path.stat().st_size,
                              "sha256": digest_file(path)})
        manifest_path = source / "manifest.json"
        manifest_path.write_text(json.dumps(manifest))
        original_manifest = digest_file(manifest_path)

        sources = []
        for relative in SOURCES:
            if arguments.source_ref:
                path = work / Path(relative).name
                path.write_text(fixtures.run(["git", "show", f"{arguments.source_ref}:{relative}"], cwd=REPOSITORY))
            else:
                path = REPOSITORY / relative
            sources.append(path)
        executable = work / "validate-saved-recording"
        fixtures.run(["swiftc", "-O", *sources, "-o", executable])
        recordings = work / "recordings"
        first = prepare(executable, sessions, source, recordings, work, "save")
        second = prepare(executable, sessions, source, recordings, work, "reopen")
        assert Path(first["path"]).resolve() == Path(second["path"]).resolve()
        assert (first["inode"], first["modified"]) == (second["inode"], second["modified"]), "Reopening rewrote the saved recording"
        assert Path(first["path"]).stat().st_size > sidecar.stat().st_size
        assert digest_file(manifest_path) == original_manifest, "Saving changed the source manifest"
        for path in (events, sidecar):
            expected = next(entry for entry in inventory if entry["path"] == path.name)
            assert digest_file(path) == expected["sha256"], "Saving changed source bytes"
        assert not list(recordings.glob("*.pending")), "Saving left unfinished stages"
        print("PASS: save and fresh-process reopen preserve sources and reuse the artifact within the memory budget.")
    finally:
        if not arguments.keep:
            shutil.rmtree(work)


if __name__ == "__main__":
    main()

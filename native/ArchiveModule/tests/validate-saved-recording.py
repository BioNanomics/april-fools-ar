#!/usr/bin/env python3
"""Run the Foundation saved-recording lifecycle tests without any iOS device."""
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import uuid

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("mp4_validation", HERE / "validate-mp4.py")
mp4 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mp4)

with tempfile.TemporaryDirectory(prefix="afar-saved-recording-") as temporary:
    work = Path(temporary)
    sessions = work / "sessions"
    sessions.mkdir()
    source, *_ = mp4.fixture(sessions, faststart=False)
    # Exercise lazy migration of a portrait capture that predates native
    # playback-transform metadata, while retaining the sensor-space movie.
    frame_path = source / "frames.jsonl"
    frames = [json.loads(line) for line in frame_path.read_text().splitlines()]
    frames[0].update(imageWidth=64, imageHeight=48, interfaceOrientation=1,
                     displayTransform=[0, 1.25, -0.75, 0, 0.8, -0.1])
    frame_path.write_text("".join(json.dumps(frame) + "\n" for frame in frames))
    manifest_path = source / "manifest.json"
    manifest = json.loads(manifest_path.read_text())
    entry = next(value for value in manifest["fileInventory"] if value["path"] == "frames.jsonl")
    entry.update(bytes=frame_path.stat().st_size, sha256=mp4.digest(frame_path.read_bytes()))
    manifest_path.write_text(json.dumps(manifest))
    executable = work / "ValidateSavedRecording"
    subprocess.run(["swiftc", "-O", str(HERE.parent / "SessionMP4Writer.swift"),
                    str(HERE.parent / "SavedRecordingStore.swift"),
                    str(HERE.parent / "VideoOrientation.swift"),
                    str(HERE / "ValidateSavedRecording.swift"), "-o", str(executable)], check=True)
    subprocess.run([str(executable), str(sessions), str(source), str(work / "recordings")], check=True)
    movie = work / "recordings" / (source.name + ".mp4")
    rotation = json.loads(mp4.run(["ffprobe", "-v", "error", "-select_streams", "v:0",
                                  "-show_entries", "stream_side_data=rotation", "-of", "json", movie]))
    assert rotation["streams"][0]["side_data_list"][0]["rotation"] == -90
    print("SavedRecordingStore: legacy portrait orientation inferred and retained")
    concurrent_source = sessions / str(uuid.uuid4()).upper()
    shutil.copytree(source, concurrent_source)
    processes = [subprocess.Popen([str(executable), "--prepare", str(sessions),
                                  str(concurrent_source), str(work / "recordings")],
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                 for _ in range(4)]
    outputs = []
    for process in processes:
        stdout, stderr = process.communicate(timeout=30)
        assert process.returncode == 0, stderr
        outputs.append(json.loads(stdout))
    assert all(value == outputs[0] for value in outputs), "Concurrent processes rewrote the recording"
    print("SavedRecordingStore: cross-process publication reused one artifact")

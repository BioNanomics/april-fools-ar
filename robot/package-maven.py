#!/usr/bin/env python3
"""Package already-built CMake outputs using the WPILib 2027 vendor zip layout."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import zipfile

ROOT = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(__doc__)
parser.add_argument('--release-build', type=Path, required=True)
parser.add_argument('--debug-build', type=Path, required=True)
parser.add_argument('--repository', type=Path, default=ROOT / 'robot/build/maven')
args = parser.parse_args()
version = '0.1.0'
group = 'com.aprilfools.spatial'
repo = args.repository.resolve()
base = repo / group.replace('.', '/')

def artifact(name):
    directory = base / name / version
    directory.mkdir(parents=True, exist_ok=True)
    (directory / f'{name}-{version}.pom').write_text(
        f'<project><modelVersion>4.0.0</modelVersion><groupId>{group}</groupId>'
        f'<artifactId>{name}</artifactId><version>{version}</version></project>\n')
    return directory

def archive(directory, name, classifier, paths):
    target = directory / f'{name}-{version}-{classifier}.zip'
    with zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED) as out:
        for source, entry in paths:
            if not source.is_file():
                raise SystemExit(f'Missing built artifact: {source}')
            out.write(source, entry)
        for name in ('LICENSE.md', 'NOTICE.md', 'REVISION'):
            out.write(ROOT / 'third_party/apriltag' / name, 'apriltag-' + name)

cpp, jni, java = 'af-spatial-core-cpp', 'af-spatial-core-jni', 'af-spatial-core-java'
cpp_dir, jni_dir, java_dir = artifact(cpp), artifact(jni), artifact(java)
archive(cpp_dir, cpp, 'headers', [(p, p.name) for p in sorted((ROOT / 'native/SpatialCore/include').glob('afsc*.h'))]
        + [(ROOT / 'native/AprilTag/AFTagCore.h', 'AFTagCore.h')])
for debug, build in ((False, args.release_build), (True, args.debug_build)):
    classifier = 'linuxsystemcore' + ('debug' if debug else '')
    # NativeUtils resolves the Systemcore platform under linux/systemcore.
    # Both spellings support consumers whose debug naming policy adds 'd'.
    paths = [(build / 'libaf_spatial_core.a', 'linux/systemcore/static/libaf_spatial_core.a')]
    if debug:
        paths.append((build / 'libaf_spatial_core.a', 'linux/systemcore/static/libaf_spatial_cored.a'))
    archive(cpp_dir, cpp, 'linuxsystemcorestatic' + ('debug' if debug else ''), paths)
    archive(jni_dir, jni, classifier, [(build / 'libaf_spatial_core_jni.so',
                                      'linux/systemcore/shared/libaf_spatial_core_jni.so')])
source_jar = args.release_build / 'af-spatial-core.jar'
if not source_jar.is_file():
    raise SystemExit(f'Missing Java artifact: {source_jar}')
shutil.copyfile(source_jar, java_dir / f'{java}-{version}.jar')
for path in repo.rglob('*'):
    if path.is_file() and path.suffix in ('.zip', '.jar', '.pom'):
        path.with_name(path.name + '.sha256').write_text(hashlib.sha256(path.read_bytes()).hexdigest() + '\n')
print(repo)

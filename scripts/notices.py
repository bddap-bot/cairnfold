#!/usr/bin/env python3
"""Collect upstream text verbatim and compare it against the finished shipping archive."""
import pathlib
import re
import sys
import tarfile
import zipfile


def extract(source, destination, ndk_version=None):
    destination = pathlib.Path(destination)
    found_ndk = False
    with tarfile.open(source) as archive:
        for member in archive:
            if ndk_version and member.name.endswith("/config.gradle"):
                config = archive.extractfile(member).read().decode()
                match = re.search(r"ndkVersion\s*:\s*'([^']+)'", config)
                if match:
                    assert match[1] == ndk_version, "update Android NDK runtime notices"
                    found_ndk = True
            path = pathlib.PurePosixPath(member.name)
            if not member.isfile() or not re.match(
                r"(?i)(license|copying|copyright|notice|authors|readme)([._-]|$)", path.name
            ):
                continue
            relative = pathlib.Path(*path.parts[1:])
            if ".." in relative.parts:
                raise ValueError("unsafe upstream path")
            target = destination / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(archive.extractfile(member).read())
    assert not ndk_version or found_ndk, "upstream NDK version not found"
    if not any(destination.rglob("LICENSE*")):
        raise ValueError("upstream archive lacks licenses")


def check(package, expected):
    expected = pathlib.Path(expected)
    assert (expected / "godot/COPYRIGHT.txt").is_file(), "missing Godot component inventory"
    assert (expected / "LICENSE-MIT").is_file(), "missing project license"
    files = {p.relative_to(expected).as_posix(): p.read_bytes()
             for p in expected.rglob("*") if p.is_file()}
    remaining = set(files)
    if zipfile.is_zipfile(package):
        assert (expected / "android/DEPENDENCIES.txt").is_file(), "missing Android dependency notices"
        with zipfile.ZipFile(package) as archive:
            for name, data in files.items():
                assert archive.read("assets/notices/" + name) == data, f"changed notice: {name}"
                remaining.remove(name)
    else:
        prefix = "cairnfold/notices/"
        with tarfile.open(package, "r|gz") as archive:
            for member in archive:
                name = member.name.removeprefix(prefix)
                if member.name.startswith(prefix) and name in remaining and member.isfile():
                    assert archive.extractfile(member).read() == files[name], f"changed notice: {name}"
                    remaining.remove(name)
    assert not remaining, f"missing notices: {sorted(remaining)}"
    print(f"notices: {len(files)} files match upstream in {pathlib.Path(package).name}")


if __name__ == "__main__":
    {"extract": extract, "check": check}[sys.argv[1]](*sys.argv[2:])

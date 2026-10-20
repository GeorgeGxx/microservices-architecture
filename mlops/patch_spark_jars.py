"""Apply compatible security patch releases to the pinned Spark runtime jars."""

from __future__ import annotations

import os
import shutil
import urllib.error
import urllib.request
import zipfile
from pathlib import Path


MAVEN_CENTRAL = "https://repo.maven.apache.org/maven2"
PATCHES = {
    "4.2.13.Final": ("4.2.17.Final", "io/netty"),  # CVE-2026-75595 in Netty
}


def replace_jar_family(
    jars_dir: Path, old_version: str, new_version: str, group_path: str
) -> int:
    replaced = 0
    marker = f"-{old_version}"

    for old_jar in sorted(jars_dir.glob("*.jar")):
        if marker not in old_jar.name:
            continue

        artifact_id, suffix = old_jar.name.split(marker, maxsplit=1)
        if artifact_id == "netty-all":
            # Netty 4.2.17 is published as component jars and its netty-all artifact
            # is only a POM, so remove Spark's old empty aggregator JAR.
            old_jar.unlink()
            replaced += 1
            continue

        new_name = f"{artifact_id}-{new_version}{suffix}"
        new_jar = old_jar.with_name(new_name)
        download_url = (
            f"{MAVEN_CENTRAL}/{group_path}/{artifact_id}/{new_version}/{new_name}"
        )
        temporary_jar = new_jar.with_suffix(new_jar.suffix + ".download")

        try:
            urllib.request.urlretrieve(download_url, temporary_jar)
            if not zipfile.is_zipfile(temporary_jar):
                raise RuntimeError(f"Downloaded artifact is not a valid JAR: {download_url}")
            os.replace(temporary_jar, new_jar)
        except urllib.error.HTTPError as error:
            temporary_jar.unlink(missing_ok=True)
            raise RuntimeError(f"Could not fetch patched Spark dependency: {download_url}") from error
        except Exception:
            temporary_jar.unlink(missing_ok=True)
            raise

        old_jar.unlink()
        replaced += 1

    return replaced


def remove_unused_derby(jars_dir: Path) -> int:
    # The MLOps pipelines use Spark's built-in in-memory catalog and Parquet files;
    # they do not use Hive or its embedded Derby metastore.
    jars = sorted(jars_dir.glob("derby*.jar"))
    if not jars:
        raise SystemExit("Expected the bundled Derby jars so they can be removed")
    for jar in jars:
        jar.unlink()
    return len(jars)


def remove_unused_connect_repl(jars_dir: Path) -> None:
    # This image runs local Spark jobs and never uses the Spark Connect REPL/client.
    # Its bundled client jar carries a separate copy of Netty's vulnerable metadata.
    connect_repl_dir = jars_dir / "connect-repl"
    if not connect_repl_dir.is_dir():
        raise SystemExit(f"Expected optional Spark Connect REPL directory: {connect_repl_dir}")
    shutil.rmtree(connect_repl_dir)


def main() -> None:
    jars_dir = Path("/usr/local/lib/python3.12/site-packages/pyspark/jars")
    if not jars_dir.is_dir():
        raise SystemExit(f"PySpark jars directory not found: {jars_dir}")

    for old_version, (new_version, group_path) in PATCHES.items():
        replaced = replace_jar_family(jars_dir, old_version, new_version, group_path)
        if replaced == 0:
            raise SystemExit(f"No Spark jars found for expected version {old_version}")
        print(f"Updated {replaced} Spark jar(s): {old_version} -> {new_version}")

    removed_derby = remove_unused_derby(jars_dir)
    print(f"Removed {removed_derby} unused Derby jar(s); MLOps workloads do not use Hive")

    remove_unused_connect_repl(jars_dir)
    print("Removed optional Spark Connect REPL/client jars; MLOps uses local Spark sessions")


if __name__ == "__main__":
    main()

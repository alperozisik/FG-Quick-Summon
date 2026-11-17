"""Build the Fantasy Grounds package and matching token from tracked project files."""

from argparse import ArgumentParser
from hashlib import sha256
from pathlib import Path
from shutil import copyfile
from xml.etree import ElementTree
from zipfile import ZipFile, ZipInfo


ROOT = Path(__file__).resolve().parent
RUNTIME_SUFFIXES = {".lua", ".png", ".xml"}


def runtime_files():
    files = {"extension.xml", "LICENSE"}
    for folder in ("campaign", "graphics", "scripts"):
        files.update(
            path.relative_to(ROOT).as_posix()
            for path in (ROOT / folder).rglob("*")
            if path.is_file() and path.suffix in RUNTIME_SUFFIXES
        )
    return sorted(files)


def validate_manifest(files, expected_tag):
    manifest = ElementTree.parse(ROOT / "extension.xml").getroot()
    version = manifest.findtext("properties/version")
    if not version or (expected_tag and expected_tag != f"v{version}"):
        raise ValueError(f"Release tag {expected_tag!r} does not match extension version {version!r}.")
    announcement = manifest.find("announcement")
    if announcement is None or announcement.get("text") != f"Quick Summon v{version} loaded.":
        raise ValueError("The load announcement must match the extension version.")

    for name in files:
        if name.endswith(".xml"):
            for element in ElementTree.parse(ROOT / name).iter():
                for attribute in ("file", "source"):
                    value = element.get(attribute)
                    if value and value not in files:
                        raise ValueError(f"{name} references a file missing from the package: {value}")
    return version


def build(output, expected_tag):
    files = runtime_files()
    version = validate_manifest(files, expected_tag)
    output.mkdir(parents=True, exist_ok=True)
    extension = output / "QuickSummon.ext"
    staged = extension.with_suffix(".ext.tmp")
    try:
        with ZipFile(staged, "w") as archive:
            for name in files:
                info = ZipInfo(name)
                info.create_system = 3
                info.external_attr = 0o100644 << 16
                data = (ROOT / name).read_bytes()
                if name == "LICENSE" or Path(name).suffix in {".lua", ".xml"}:
                    data = data.replace(b"\r\n", b"\n")
                archive.writestr(info, data)
        with ZipFile(staged) as archive:
            failure = archive.testzip()
            if failure:
                raise RuntimeError(f"Invalid archive entry: {failure}")
        staged.replace(extension)
    finally:
        staged.unlink(missing_ok=True)

    token = output / "Spiritual_Weapon.png"
    copyfile(ROOT / "art" / "spiritual_weapon.png", token)
    checksums = "".join(
        f"{sha256(asset.read_bytes()).hexdigest()}  {asset.name}\n"
        for asset in (extension, token)
    )
    (output / "SHA256SUMS.txt").write_bytes(checksums.encode("ascii"))
    print(f"Built Quick Summon {version} in {output}")


if __name__ == "__main__":
    parser = ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "release")
    parser.add_argument("--tag", help="Verify that this Git tag matches the manifest version.")
    args = parser.parse_args()
    build(args.output, args.tag)

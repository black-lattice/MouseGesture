"""Extract one release's notes from CHANGELOG.md using its version tag."""
import re
import sys
from pathlib import Path


def extract_notes(changelog: str, tag: str) -> str:
    version = tag.removeprefix("v")
    headings = list(re.finditer(r"^##[ \t]+([^\s]+)[^\n]*$", changelog, re.MULTILINE))
    matches = [index for index, heading in enumerate(headings) if heading.group(1) == version]
    if len(matches) != 1:
        raise ValueError(f"更新记录必须包含且仅包含一个 {tag} 版本章节")
    index = matches[0]
    heading = headings[index]
    end = headings[index + 1].start() if index + 1 < len(headings) else len(changelog)
    if not changelog[heading.end():end].strip():
        raise ValueError(f"{tag} 的更新记录不能为空")
    return changelog[heading.start():end].strip() + "\n"


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("用法：python3 scripts/release-notes.py v版本号")
    try:
        changelog = Path(__file__).resolve().parent.parent / "CHANGELOG.md"
        print(extract_notes(changelog.read_text(encoding="utf-8"), sys.argv[1]), end="")
    except (OSError, ValueError) as error:
        sys.exit(str(error))

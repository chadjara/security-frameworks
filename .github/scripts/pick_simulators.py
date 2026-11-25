#!/usr/bin/env python3
"""Print GitHub Actions outputs naming an available iPhone and iPad simulator on the newest iOS runtime.

Output lines: iphone=<udid>, iphone_name=<name>, ipad=<udid>, ipad_name=<name>, runtime=<id>
"""

import json
import os
import re
import subprocess
import sys

IPHONE_PREFERENCE = [r"^iPhone \d+ Pro$", r"^iPhone \d+$", r"^iPhone"]
IPAD_PREFERENCE = [r"^iPad Pro 13-inch", r"^iPad Pro .*12\.9", r"^iPad Air 13-inch", r"^iPad Pro", r"^iPad Air", r"^iPad"]
# The App Store workflow needs the largest iPhone (6.9-inch screenshots): IPHONE_PATTERN="^iPhone \d+ Pro Max$".
if os.environ.get("IPHONE_PATTERN"):
    IPHONE_PREFERENCE = [os.environ["IPHONE_PATTERN"]]


def runtime_version(runtime_id: str) -> tuple:
    m = re.search(r"iOS-(\d+)-(\d+)(?:-(\d+))?$", runtime_id)
    return tuple(int(x or 0) for x in m.groups()) if m else (0,)


def pick(devices: list[dict], patterns: list[str]) -> dict | None:
    for pattern in patterns:
        matches = [d for d in devices if re.search(pattern, d["name"])]
        if matches:
            # Highest model number wins within a pattern.
            return sorted(matches, key=lambda d: [int(n) for n in re.findall(r"\d+", d["name"])] or [0])[-1]
    return None


def main() -> int:
    data = json.loads(subprocess.run(["xcrun", "simctl", "list", "devices", "available", "--json"],
                                     check=True, capture_output=True, text=True).stdout)
    runtimes = sorted((r for r in data["devices"] if ".iOS-" in r and data["devices"][r]), key=runtime_version)
    if not runtimes:
        print("No iOS simulator runtimes available", file=sys.stderr)
        return 1
    for runtime in reversed(runtimes):
        devices = [d for d in data["devices"][runtime] if d.get("isAvailable", True)]
        iphone, ipad = pick(devices, IPHONE_PREFERENCE), pick(devices, IPAD_PREFERENCE)
        if iphone and ipad:
            print(f"iphone={iphone['udid']}")
            print(f"iphone_name={iphone['name']}")
            print(f"ipad={ipad['udid']}")
            print(f"ipad_name={ipad['name']}")
            print(f"runtime={runtime}")
            print(f"Using {iphone['name']} and {ipad['name']} on {runtime}", file=sys.stderr)
            return 0
    print("No runtime has both an iPhone and an iPad simulator", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())

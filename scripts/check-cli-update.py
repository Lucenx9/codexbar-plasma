#!/usr/bin/env python3
"""Read the selected CLI version and optionally check official releases."""
import argparse
import json
from lib.cli_release import check


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--command", required=True)
    parser.add_argument("--local-only", action="store_true")
    args = parser.parse_args()
    print(json.dumps(check(args.command, args.local_only)))


if __name__ == "__main__":
    main()

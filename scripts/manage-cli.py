#!/usr/bin/env python3
"""Install or update only the widget's explicitly selected private CLI copy."""
import argparse
import json
import signal
import subprocess
import tarfile
from lib.managed_cli import failure_status, run


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--action", choices=("status", "install", "update", "automatic", "rollback"), required=True)
    parser.add_argument("--command", default="")
    args = parser.parse_args()
    signal.alarm(600)
    try:
        result = run(args.action, args.command)
    except (OSError, ValueError, tarfile.TarError, subprocess.SubprocessError) as error:
        result = {"status": failure_status(error)}
    print(json.dumps(result))


if __name__ == "__main__":
    main()

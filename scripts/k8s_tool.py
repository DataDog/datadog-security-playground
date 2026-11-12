#!/usr/bin/env python3
"""Shared helpers for the Kubernetes attack scenarios (Python implementations).

Python twin of scripts/tool.sh: colored step narration, wait-for-confirmation
mode, a subprocess wrapper with --dry-run support, and Kubernetes helpers built
around the pod UID — the join key between the audit plane and the eBPF plane.

Usage from a scenario directory:

    sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "scripts"))
    from k8s_tool import Runner

Flags (same spirit as tool.sh):
    -w, --wait     Wait for Enter between steps
    -s, --silent   No narration, just execution
    -n, --namespace   Target namespace (default: playground)
        --dry-run  Print every command without executing anything (validation mode)
"""

import argparse
import json
import shlex
import subprocess
import sys

# Colors
RED = "\033[0;31m"
GREEN = "\033[0;32m"
YELLOW = "\033[1;33m"
BLUE = "\033[1;34m"
PURPLE = "\033[1;35m"
CYAN = "\033[0;36m"
WHITE = "\033[1;37m"
NC = "\033[0m"

DEFAULT_NAMESPACE = "playground"


class Runner:
    def __init__(self, wait=False, silent=False, dry_run=False, namespace=DEFAULT_NAMESPACE):
        self.wait = wait
        self.silent = silent
        self.dry_run = dry_run
        self.namespace = namespace
        self.step_no = 0

    # ------------------------------------------------------------------ cli
    @classmethod
    def from_args(cls, description):
        parser = argparse.ArgumentParser(description=description)
        parser.add_argument("-w", "--wait", action="store_true",
                            help="Wait for user confirmation between steps")
        parser.add_argument("-s", "--silent", action="store_true",
                            help="Execute without narration")
        parser.add_argument("-n", "--namespace", default=DEFAULT_NAMESPACE,
                            help=f"Target namespace (default: {DEFAULT_NAMESPACE})")
        parser.add_argument("--dry-run", action="store_true",
                            help="Print every command without executing anything")
        args = parser.parse_args()
        return cls(wait=args.wait, silent=args.silent, dry_run=args.dry_run,
                   namespace=args.namespace)

    # ------------------------------------------------------------ narration
    def banner(self, title, warning=None, body=None):
        if self.silent:
            return
        print(f"{WHITE}# {title}{NC}\n")
        if warning:
            print(f"{YELLOW}⚠️  WARNING: {warning}{NC}\n")
        if body:
            print(f"{PURPLE}{body}{NC}\n")

    def step(self, title, body=None):
        if self.silent:
            return
        if self.step_no == 0:
            print(f"{BLUE}# Attack steps{NC}\n")
        self.step_no += 1
        print(f"{GREEN}## Step {self.step_no} — {title}{NC}\n")
        if body:
            print(f"{PURPLE}{body}{NC}\n")

    def note(self, text):
        if not self.silent:
            print(f"{YELLOW}{text}{NC}\n")

    def done(self, text):
        print(f"{GREEN}{text}{NC}\n")

    def confirm(self):
        if not self.wait:
            return
        try:
            input(f"\n{YELLOW}Press Enter to continue, or Ctrl+C to exit...{NC}\n\n")
        except EOFError:
            pass

    # ------------------------------------------------------------ execution
    def run(self, cmd, capture=False, check=True, input=None):
        """Print and run a command given as an argv list. Honors --dry-run.

        `input` (str) is piped to the command's stdin — used to drive peirates'
        interactive menu commands non-interactively via kubectl exec -i.
        """
        printable = " ".join(shlex.quote(str(c)) for c in cmd)
        if not self.silent:
            print(f"{CYAN}```\n{YELLOW}{printable}{NC}\n{CYAN}```{NC}\n")
        if self.dry_run:
            return None
        proc = subprocess.run([str(c) for c in cmd], capture_output=capture, text=True,
                              input=input)
        if check and proc.returncode != 0:
            stderr = (proc.stderr or "").strip() if capture else "(see output above)"
            raise RuntimeError(f"command failed ({proc.returncode}): {printable}\n{stderr}")
        return proc

    def kubectl(self, *args, **kwargs):
        return self.run(["kubectl", "-n", self.namespace] + [str(a) for a in args], **kwargs)

    # ----------------------------------------------------------- kubernetes
    def find_pod(self, selector):
        """First pod name matching a label selector, or a placeholder in dry-run."""
        if self.dry_run:
            return "<pod-name>"
        proc = self.kubectl("get", "pods", "-l", selector, "-o", "json", capture=True)
        items = json.loads(proc.stdout).get("items", [])
        if not items:
            raise RuntimeError(f"no pod matches selector '{selector}' in namespace "
                               f"'{self.namespace}'. Is the playground deployed?")
        return items[0]["metadata"]["name"]

    def pod_uid(self, pod):
        """The pod UID — the join key between the audit and eBPF planes."""
        if self.dry_run:
            return "<pod-uid>"
        proc = self.kubectl("get", "pod", pod, "-o", "json", capture=True)
        return json.loads(proc.stdout)["metadata"]["uid"]

    def join_key(self, label, value):
        """Highlight a join key so it can be grepped on both planes later."""
        print(f"{BLUE}Join key — {label}: {CYAN}{value}{NC}\n")

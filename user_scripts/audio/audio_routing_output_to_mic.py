#!/usr/bin/env python3
"""Route application audio output to a virtual microphone via PipeWire.

Architecture: Arch Linux / Wayland / Hyprland
Target Ecosystem: PipeWire 1.4+ / WirePlumber
Language: Python 3.14
"""

import sys
import json
import time
import atexit
import signal
import subprocess

TARGET_APP = sys.argv[1] if len(sys.argv) > 1 else "mpv"
VIRT_NODE_NAME = "Virtual_Mic_Tx"
VIRT_MODULE_ID = None

APP_MATCH_KEYS = frozenset({
    "application.name",
    "application.process.binary",
    "node.name",
})


def cleanup() -> None:
    """Destroy the virtual node module, guarded against re-entrant invocation."""
    global VIRT_MODULE_ID
    mod_id = VIRT_MODULE_ID
    VIRT_MODULE_ID = None
    if mod_id:
        print(f"\n:: Tearing down virtual node module (ID: {mod_id})...")
        try:
            subprocess.run(
                ["pactl", "unload-module", mod_id],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=5,
            )
        except (subprocess.TimeoutExpired, OSError):
            pass


def handle_signal(signum, frame) -> None:
    """SIGTERM/SIGHUP handler — cleanup then exit."""
    cleanup()
    sys.exit(0)


atexit.register(cleanup)
signal.signal(signal.SIGTERM, handle_signal)
signal.signal(signal.SIGHUP, handle_signal)


def get_pw_graph(*, fatal: bool = True) -> list[dict]:
    """Capture and parse the live PipeWire object graph."""
    try:
        out = subprocess.check_output(["pw-dump"], text=True, timeout=5)
        return json.loads(out)
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, json.JSONDecodeError, OSError) as e:
        if fatal:
            print(f"Fatal: Failed to query PipeWire daemon: {e}", file=sys.stderr)
            sys.exit(1)
        return []


def extract_channel(props: dict) -> str:
    """Extract audio channel identifier from port properties."""
    ch = props.get("audio.channel")
    if isinstance(ch, str) and ch:
        return ch.upper()
    name = props.get("port.name")
    if isinstance(name, str):
        upper = name.upper()
        if "FL" in upper:
            return "FL"
        if "FR" in upper:
            return "FR"
    return ""


def matches_target(props: dict) -> bool:
    """Check if node properties match the target application."""
    target_lower = TARGET_APP.lower()
    for key in APP_MATCH_KEYS:
        val = props.get(key)
        if isinstance(val, str) and target_lower in val.lower():
            return True
    return False


def find_nodes(graph: list[dict]) -> tuple[set[int], int | None]:
    """Locate ALL target application streams and the virtual node."""
    target_ids: set[int] = set()
    virt_id = None
    for obj in graph:
        if obj.get("type") != "PipeWire:Interface:Node":
            continue
        props = obj.get("info", {}).get("props", {})
        if props.get("node.name") == VIRT_NODE_NAME:
            virt_id = obj["id"]
        elif props.get("media.class") == "Stream/Output/Audio":
            if matches_target(props):
                target_ids.add(obj["id"])
    return target_ids, virt_id


def get_virt_input_ports(graph: list[dict], virt_id: int) -> list[tuple[str, int]]:
    """Get all input ports for the virtual node."""
    ports: list[tuple[str, int]] = []
    for obj in graph:
        if obj.get("type") != "PipeWire:Interface:Port":
            continue
        info = obj.get("info", {})
        props = info.get("props", {})
        raw_parent = props.get("node.id")
        if raw_parent is None:
            continue
        try:
            parent = int(raw_parent)
        except (ValueError, TypeError):
            continue
        if parent != virt_id:
            continue
        if str(info.get("direction", "")).lower() != "input":
            continue
        channel = extract_channel(props)
        ports.append((channel, obj["id"]))
    return ports


def get_desired_links(
    graph: list[dict], target_ids: set[int], virt_id: int,
) -> set[tuple[int, int]]:
    """Compute all required port links using channel-aware pairing with sorted fallback."""
    virt_in_list = get_virt_input_ports(graph, virt_id)
    target_outs: dict[int, list[tuple[str, int]]] = {t_id: [] for t_id in target_ids}

    for obj in graph:
        if obj.get("type") != "PipeWire:Interface:Port":
            continue
        info = obj.get("info", {})
        props = info.get("props", {})
        raw_parent = props.get("node.id")
        if raw_parent is None:
            continue
        try:
            parent = int(raw_parent)
        except (ValueError, TypeError):
            continue
        if parent not in target_ids:
            continue
        if str(info.get("direction", "")).lower() != "output":
            continue
        channel = extract_channel(props)
        target_outs[parent].append((channel, obj["id"]))

    virt_ch_map: dict[str, int] = {ch: pid for ch, pid in virt_in_list if ch}
    virt_sorted: list[int] = sorted(pid for _, pid in virt_in_list)

    desired: set[tuple[int, int]] = set()
    for t_id, t_ports in target_outs.items():
        if not t_ports:
            continue
        if len(t_ports) == 1:
            only_port = t_ports[0][1]
            for _, v_port in virt_in_list:
                desired.add((only_port, v_port))
            continue
        t_ch_map: dict[str, int] = {ch: pid for ch, pid in t_ports if ch}
        common_channels = set(t_ch_map) & set(virt_ch_map)
        if common_channels:
            for ch in common_channels:
                desired.add((t_ch_map[ch], virt_ch_map[ch]))
        else:
            t_sorted = sorted(pid for _, pid in t_ports)
            v_fb = virt_sorted[:]
            if len(v_fb) == 1:
                v_fb *= 2
            if len(t_sorted) >= 2 and len(v_fb) >= 2:
                desired.add((t_sorted[0], v_fb[0]))
                desired.add((t_sorted[1], v_fb[1]))
    return desired


def get_graph_links(graph: list[dict]) -> tuple[set[tuple[int, int]], set[tuple[int, int]]]:
    """Extract link pairs from the graph, separated by health.

    Returns:
        healthy: non-error link pairs (init, active, paused all qualify)
        errored: error-state link pairs
    """
    healthy: set[tuple[int, int]] = set()
    errored: set[tuple[int, int]] = set()
    for obj in graph:
        if obj.get("type") != "PipeWire:Interface:Link":
            continue
        info = obj.get("info", {})
        out_p = info.get("output-port-id")
        in_p = info.get("input-port-id")
        if out_p is None or in_p is None:
            continue
        try:
            pair = (int(out_p), int(in_p))
        except (ValueError, TypeError):
            continue
        if str(info.get("state", "")).lower() == "error":
            errored.add(pair)
        else:
            healthy.add(pair)
    return healthy, errored


def attempt_link(out_port: int, in_port: int) -> str:
    """Attempt to create a pw-link. Returns stderr output (empty on clean exit)."""
    try:
        result = subprocess.run(
            ["pw-link", str(out_port), str(in_port)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
            timeout=5,
        )
        return result.stderr.strip()
    except (subprocess.TimeoutExpired, OSError) as e:
        return str(e)


def destroy_link(out_port: int, in_port: int) -> None:
    """Destroy a link between two ports."""
    try:
        subprocess.run(
            ["pw-link", "-d", str(out_port), str(in_port)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=5,
        )
    except (subprocess.TimeoutExpired, OSError):
        pass


def cleanup_stale_modules() -> bool:
    """Remove any orphaned Virtual_Mic_Tx modules from prior crashed runs.

    Returns True if any modules were removed.
    """
    try:
        out = subprocess.check_output(
            ["pactl", "list", "modules", "short"], text=True, timeout=5,
        )
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, OSError):
        return False

    removed = False
    for line in out.splitlines():
        fields = line.split("\t")
        if len(fields) < 2:
            continue
        mod_id, mod_name = fields[0], fields[1]
        args = fields[2] if len(fields) > 2 else ""
        if mod_name == "module-null-sink" and VIRT_NODE_NAME in args:
            print(f":: Removing stale virtual node module (ID: {mod_id})...")
            try:
                subprocess.run(
                    ["pactl", "unload-module", mod_id],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    timeout=5,
                )
                removed = True
            except (subprocess.TimeoutExpired, OSError):
                pass
    return removed


def main() -> None:
    global VIRT_MODULE_ID
    print(f":: Initializing Virtual Audio Node routing for [{TARGET_APP}]...")

    # 0. Clean up stale modules from prior crashes
    if cleanup_stale_modules():
        time.sleep(0.5)

    # 1. Create virtual source node
    try:
        out = subprocess.check_output(
            [
                "pactl", "load-module", "module-null-sink",
                "media.class=Audio/Source/Virtual",
                f"sink_name={VIRT_NODE_NAME}",
                "channel_map=front-left,front-right",
            ],
            text=True,
            timeout=10,
        )
        VIRT_MODULE_ID = out.strip()
        print(f":: Virtual node instantiated. (Module ID: {VIRT_MODULE_ID})")
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
        print("Fatal: Failed to load virtual node via pipewire-pulse.", file=sys.stderr)
        sys.exit(1)

    # 2. Wait for virtual node AND its input ports to materialize
    virt_node_id = None
    port_count = 0
    ports_ready = False
    for _ in range(50):
        graph = get_pw_graph()
        _, virt_node_id = find_nodes(graph)
        if virt_node_id is not None:
            ports = get_virt_input_ports(graph, virt_node_id)
            port_count = len(ports)
            if port_count >= 2:
                ports_ready = True
                break
        time.sleep(0.1)

    if virt_node_id is None:
        print("Fatal: Virtual node did not appear in PipeWire graph.", file=sys.stderr)
        sys.exit(1)
    if not ports_ready:
        print(
            f"Fatal: Virtual node input ports did not materialize (got {port_count}, need 2).",
            file=sys.stderr,
        )
        sys.exit(1)

    print(f":: Virtual node confirmed. (Node ID: {virt_node_id}, Input ports: {port_count})")
    print(f":: Monitoring for '{TARGET_APP}' streams... Press Ctrl+C to stop.\n")

    # 3. Continuous multi-stream monitoring loop
    linked = False
    prev_target_ids: set[int] = set()

    try:
        while True:
            graph = get_pw_graph(fatal=False)
            if not graph:
                time.sleep(1)
                continue

            target_ids, fresh_virt_id = find_nodes(graph)

            # Virtual node sanity check
            if fresh_virt_id is None:
                if linked:
                    print("Warning: Virtual node vanished from graph.", file=sys.stderr)
                    linked = False
                prev_target_ids = set()
                time.sleep(1)
                continue

            virt_node_id = fresh_virt_id

            # Log per-stream changes
            for nid in sorted(target_ids - prev_target_ids):
                print(f":: Stream detected: '{TARGET_APP}' (Node ID: {nid})")
            for gid in sorted(prev_target_ids - target_ids):
                print(f":: Stream ended: '{TARGET_APP}' (Node ID: {gid})")
            prev_target_ids = target_ids.copy()

            # No target streams active
            if not target_ids:
                if linked:
                    print(f":: No '{TARGET_APP}' streams found. Waiting for playback...")
                    linked = False
                time.sleep(1)
                continue

            # Compute topology delta
            desired = get_desired_links(graph, target_ids, virt_node_id)
            healthy, errored = get_graph_links(graph)

            # Destroy error-state links that overlap with our desired set
            stale = desired & errored
            for pair in stale:
                destroy_link(*pair)

            # Determine which links need creation
            missing = desired - healthy

            if missing:
                # Attempt all link creations, capture stderr per link
                link_errors: dict[tuple[int, int], str] = {}
                for pair in missing:
                    err = attempt_link(*pair)
                    if err:
                        link_errors[pair] = err

                # Verify actual graph state — pw-link exit code is unreliable
                # for links whose source node is idle (link enters 'init' state
                # but IS created; pw-link reports failure anyway)
                time.sleep(0.15)
                verify_graph = get_pw_graph(fatal=False)
                if verify_graph:
                    verified, _ = get_graph_links(verify_graph)
                    confirmed = missing & verified
                    truly_failed = missing - verified

                    if confirmed:
                        linked = True
                        print(
                            f":: Routing updated: {len(confirmed)} link(s) verified "
                            f"for {len(target_ids)} stream(s) -> '{VIRT_NODE_NAME}'"
                        )
                    if truly_failed:
                        print(
                            f"Warning: {len(truly_failed)} link(s) could not be created.",
                            file=sys.stderr,
                        )
                        for pair in truly_failed:
                            detail = link_errors.get(pair, "unknown reason")
                            print(
                                f"  Port {pair[0]} -> Port {pair[1]}: {detail}",
                                file=sys.stderr,
                            )
                else:
                    # Graph unreachable for verification — assume success
                    linked = True
            elif not linked:
                linked = True
                print(f":: Routing active -> '{VIRT_NODE_NAME}' (topology verified)")

            time.sleep(1)

    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()

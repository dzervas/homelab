#!/usr/bin/env python3
import os
import json
import asyncio
import requests
import kr8s

OUTPUT_PATH = os.getenv("OUTPUT_PATH", "/data/extra-records.json")
INGRESS_CLASS = os.getenv("INGRESS_CLASS", "traefik")
GATEWAY_CLASS = os.getenv("GATEWAY_CLASS", INGRESS_CLASS)
KUBE_MASTER_DOMAIN = os.getenv("KUBE_MASTER_DOMAIN", "kube.vpn.dzerv.art")
HS_BASE = os.environ["HEADSCALE_URL"].rstrip("/")
HS_KEY = os.environ["HEADSCALE_API_KEY"]


def atomic_write(path: str, obj) -> None:
    s = json.dumps(obj, sort_keys=True, indent=2) + "\n"
    with open(path, "w", encoding="utf-8") as f:
        f.write(s)
        f.flush()
        os.fsync(f.fileno())


def headscale_node_v4_map() -> dict[str, str]:
    r = requests.get(
        f"{HS_BASE}/api/v1/node",
        headers={"Authorization": f"Bearer {HS_KEY}"},
        timeout=10,
    )
    r.raise_for_status()

    out = {}
    for n in r.json().get("nodes", []):
        name = (n.get("name") or "").strip()
        ips = n.get("ipAddresses") or []
        v4 = next((ip for ip in ips if "." in ip), None)
        if name and v4:
            out[name] = v4

    print("Headscale node map:", out)
    return out


def ingress_hosts(ingress) -> list[str]:
    rules = (ingress.spec or {}).get("rules") or []
    return sorted({r.get("host", "").strip().rstrip(".") for r in rules})


def backend_services(ingress) -> list[tuple[str, str]]:
    namespace = ingress.metadata.namespace
    spec = ingress.spec or {}
    out = set()
    for rule in spec.get("rules") or []:
        for p in (rule.get("http") or {}).get("paths") or []:
            service = ((p.get("backend") or {}).get("service") or {}).get("name")
            if service:
                out.add((namespace, service))

    db = ((spec.get("defaultBackend") or {}).get("service") or {}).get("name")
    if db:
        out.add((namespace, db))
    return sorted(out)


def httproute_hosts(httproute) -> list[str]:
    hostnames = (httproute.spec or {}).get("hostnames") or []
    return sorted({h.strip().rstrip(".") for h in hostnames if h.strip()})


def httproute_backend_services(httproute) -> list[tuple[str, str]]:
    namespace = httproute.metadata.namespace
    spec = httproute.spec or {}
    out = set()
    for rule in spec.get("rules") or []:
        for ref in (rule.get("backendRefs") or []):
            svc_name = ref.get("name")
            svc_namespace = ref.get("namespace") or namespace
            if svc_name:
                out.add((svc_namespace, svc_name))
    return sorted(out)


async def httproute_matches_gateway_class(httproute, gateway_class: str) -> bool:
    spec = httproute.spec or {}
    for ref in spec.get("parentRefs") or []:
        ref_namespace = ref.get("namespace") or httproute.metadata.namespace
        ref_name = ref.get("name")
        if not ref_name:
            continue
        async for gw in kr8s.asyncio.get("Gateway", ref_name, namespace=ref_namespace):
            if (gw.spec or {}).get("gatewayClassName") == gateway_class:
                return True
    return False


async def service_selector(namespace: str, name: str) -> dict:
    service = None
    async for s in kr8s.asyncio.get("Service", name, namespace=namespace):
        service = s
        break
    if service is None:
        return {}
    return (service.spec or {}).get("selector") or {}


async def pick_ready_pod_node(namespace: str, selector: dict) -> str | None:
    if not selector:
        return None

    sel = ",".join([f"{k}={v}" for k, v in selector.items()])
    print(f"Looking for ready pod with selector {sel}")
    async for pod in kr8s.asyncio.get("Pod", namespace=namespace, label_selector=sel):
        if (pod.status or {}).get("phase") != "Running":
            continue

        print(
            f"Found ready pod {pod.metadata.name} for service {namespace} with selector {sel}"
        )
        return (pod.spec or {}).get("nodeName")
    return None


async def build_pod_mapping() -> dict[str, set[str]]:
    print("Building pod to ingress/httproute mapping...")
    mapping: dict[str, set[str]] = {}

    async for ingress in kr8s.asyncio.get("Ingress", namespace="all"):
        ingressClass = (ingress.spec or {}).get("ingressClassName") or ""
        if ingressClass != INGRESS_CLASS:
            continue

        resource_key = f"ingress:{ingress.metadata.namespace}/{ingress.metadata.name}"
        hosts = ingress_hosts(ingress)
        if not hosts:
            continue

        for namespace, service in backend_services(ingress):
            selector = await service_selector(namespace, service)
            if not selector:
                continue

            sel = ",".join([f"{k}={v}" for k, v in selector.items()])
            async for pod in kr8s.asyncio.get(
                "Pod", namespace=namespace, label_selector=sel
            ):
                pod_key = f"{pod.metadata.namespace}/{pod.metadata.name}"
                if pod_key not in mapping:
                    mapping[pod_key] = set()
                mapping[pod_key].add(resource_key)

    async for httproute in kr8s.asyncio.get("HTTPRoute", namespace="all"):
        if not await httproute_matches_gateway_class(httproute, GATEWAY_CLASS):
            continue

        resource_key = f"httproute:{httproute.metadata.namespace}/{httproute.metadata.name}"
        hosts = httproute_hosts(httproute)
        if not hosts:
            continue

        for namespace, service in httproute_backend_services(httproute):
            selector = await service_selector(namespace, service)
            if not selector:
                continue

            sel = ",".join([f"{k}={v}" for k, v in selector.items()])
            async for pod in kr8s.asyncio.get(
                "Pod", namespace=namespace, label_selector=sel
            ):
                pod_key = f"{pod.metadata.namespace}/{pod.metadata.name}"
                if pod_key not in mapping:
                    mapping[pod_key] = set()
                mapping[pod_key].add(resource_key)

    print(
        f"Built mapping: {len(mapping)} pods -> {sum(len(s) for s in mapping.values())} resource references"
    )
    return mapping


async def get_first_master_node() -> str | None:
    masters: list[str] = []
    async for node in kr8s.asyncio.get(
        "Node", label_selector="node-role.kubernetes.io/control-plane"
    ):
        conditions = (node.status or {}).get("conditions") or []
        ready = next(
            (
                c
                for c in conditions
                if c.get("type") == "Ready" and c.get("status") == "True"
            ),
            None,
        )
        if ready:
            masters.append(node.metadata.name)

    if not masters:
        return None

    masters.sort()
    masters.reverse()
    return masters[0]


async def rebuild_records(pod_mapping: dict[str, set[str]]) -> None:
    node_v4 = headscale_node_v4_map()
    records = []

    resources_to_process: set[str] = set()
    for resource_set in pod_mapping.values():
        resources_to_process.update(resource_set)

    for resource_key in resources_to_process:
        resource_type, ns_name = resource_key.split(":", 1)
        namespace, name = ns_name.split("/", 1)
        try:
            if resource_type == "ingress":
                resource = None
                async for ing in kr8s.asyncio.get("Ingress", name, namespace=namespace):
                    resource = ing
                    break
                if resource is None:
                    continue
                hosts = ingress_hosts(resource)
                services = backend_services(resource)
            elif resource_type == "httproute":
                resource = None
                async for rt in kr8s.asyncio.get("HTTPRoute", name, namespace=namespace):
                    resource = rt
                    break
                if resource is None:
                    continue
                hosts = httproute_hosts(resource)
                services = httproute_backend_services(resource)
            else:
                continue
        except Exception as e:
            print(f"Failed to get {resource_key}: {e}")
            continue

        if not hosts:
            continue

        target_node = None
        svc_namespace = None
        service = None
        for svc_namespace, service in services:
            print(f"Processing service {svc_namespace}/{service} with hosts {hosts}")
            service_res = await service_selector(svc_namespace, service)
            node = await pick_ready_pod_node(svc_namespace, service_res)
            if node:
                target_node = node
                print(
                    f"Found ready node {target_node} for service {svc_namespace}/{service}"
                )
                break

        if not target_node:
            if svc_namespace and service:
                print(
                    f"No ready node found for service {svc_namespace}/{service}, skipping"
                )
            else:
                print("No backend services found, skipping")
            continue

        target_ip = node_v4.get(target_node)
        if not target_ip:
            print(f"No IP found for node {target_node}, skipping")
            continue

        for h in hosts:
            records.append({"name": h, "type": "A", "value": target_ip})

    master_node = await get_first_master_node()
    if master_node:
        master_ip = node_v4.get(master_node)
        if master_ip:
            records.append({"name": KUBE_MASTER_DOMAIN, "type": "A", "value": master_ip})

    records.sort(key=lambda r: (r["name"], r["value"]))
    atomic_write(OUTPUT_PATH, records)
    print(f"Wrote {len(records)} DNS records to {OUTPUT_PATH}")


async def watch_ingresses(queue: asyncio.Queue) -> None:
    print("Starting ingress watcher...")
    async for event_type, ingress in kr8s.asyncio.watch("Ingress", namespace="all"):
        ingressClass = (ingress.spec or {}).get("ingressClassName") or ""
        if ingressClass != INGRESS_CLASS:
            continue
        print(
            f"Ingress event: {event_type} {ingress.metadata.namespace}/{ingress.metadata.name}"
        )
        await queue.put("ingress")


async def watch_httproutes(queue: asyncio.Queue) -> None:
    print("Starting HTTPRoute watcher...")
    async for event_type, httproute in kr8s.asyncio.watch("HTTPRoute", namespace="all"):
        print(
            f"HTTPRoute event: {event_type} {httproute.metadata.namespace}/{httproute.metadata.name}"
        )
        await queue.put("ingress")


async def watch_nodes(queue: asyncio.Queue) -> None:
    print("Starting node watcher...")
    async for event_type, node in kr8s.asyncio.watch(
        "Node", label_selector="node-role.kubernetes.io/control-plane"
    ):
        print(f"Node event: {event_type} {node.metadata.name}")
        await queue.put("node")


async def watch_pods(queue: asyncio.Queue) -> None:
    print("Starting pod watcher...")
    async for event_type, pod in kr8s.asyncio.watch("Pod", namespace="all"):
        pod_key = f"{pod.metadata.namespace}/{pod.metadata.name}"
        print(f"Pod event: {event_type} {pod_key}")
        await queue.put("pod")


async def process_updates(
    queue: asyncio.Queue, pod_mapping: dict[str, set[str]]
) -> None:
    print("Starting update processor...")
    while True:
        msg_type = await queue.get()
        print(f"Processing update: {msg_type}")

        if msg_type == "ingress" or msg_type == "full":
            pod_mapping.clear()
            pod_mapping.update(await build_pod_mapping())
        elif msg_type == "pod" or msg_type == "node":
            pass

        await rebuild_records(pod_mapping)
        queue.task_done()


async def periodic_reconcile(queue: asyncio.Queue) -> None:
    print("Starting periodic reconciler (10 min interval)...")
    while True:
        await asyncio.sleep(600)
        print("Periodic reconcile triggered")
        await queue.put("full")


async def main() -> None:
    print("Starting DNS Operator")
    queue: asyncio.Queue = asyncio.Queue()
    pod_mapping: dict[str, set[str]] = {}

    await asyncio.gather(
        watch_ingresses(queue),
        watch_httproutes(queue),
        watch_nodes(queue),
        watch_pods(queue),
        process_updates(queue, pod_mapping),
        periodic_reconcile(queue),
    )


if __name__ == "__main__":
    asyncio.run(main())

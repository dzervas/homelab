#!/usr/bin/env python3
import os, json, time
import requests
import kr8s

OUTPUT_PATH   = os.getenv("OUTPUT_PATH", "/data/extra-records.json")
INGRESS_CLASS = os.getenv("INGRESS_CLASS", "traefik")
DOMAIN_SUFFIX = os.getenv("DOMAIN_SUFFIX", "")  # optional: ".vpn.example.com"
HS_BASE	   = os.environ["HEADSCALE_URL"].rstrip("/")
HS_KEY		= os.environ["HEADSCALE_API_KEY"]

def want_host(h: str) -> bool:
	if not h: return False
	h = h.strip().rstrip(".").lower()
	return (not DOMAIN_SUFFIX) or h.endswith(DOMAIN_SUFFIX.lower())

def atomic_write(path: str, obj) -> None:
	s = json.dumps(obj, sort_keys=True, indent=2) + "\n"
	tmp = path + ".tmp"
	with open(tmp, "w", encoding="utf-8") as f:
		f.write(s)
		f.flush()
		os.fsync(f.fileno())
	os.replace(tmp, path)

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
		ips  = n.get("ipAddresses") or []
		v4 = next((ip for ip in ips if "." in ip), None)
		if name and v4:
			out[name] = v4

	print("Headscale node map:", out)

	return out

def ingress_hosts(ingress) -> list[str]:
	rules = (ingress.spec or {}).get("rules") or []
	return sorted({r.get("host","").strip().rstrip(".") for r in rules if want_host(r.get("host",""))})

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

def service_selector(namespace: str, name: str) -> dict:
	service = kr8s.get("Service", name, namespace=namespace)
	service = next(service)
	return (service.spec or {}).get("selector") or {}

def pick_ready_pod_node(namespace: str, selector: dict) -> str | None:
	if not selector:
		return None

	sel = ",".join([f"{k}={v}" for k, v in selector.items()])
	print(f"Looking for ready pod with selector {sel}")
	for pod in kr8s.get("Pod", namespace=namespace, label_selector=sel):
		# cheap readiness check: phase + Ready condition
		if (pod.status or {}).get("phase") != "Running":
			continue

		print(f"Found ready pod {pod.metadata.name} for service {namespace} with selector {sel}")
		return (pod.spec or {}).get("nodeName")
	return None

def reconcile():
	node_v4 = headscale_node_v4_map()

	records = []
	for ingress in kr8s.get("Ingress", namespace="all"):
		ingressClass = (ingress.spec or {}).get("ingressClassName") or ""
		if ingressClass != INGRESS_CLASS:
			continue

		hosts = ingress_hosts(ingress)
		if not hosts:
			continue

		target_node = None
		for namespace, service in backend_services(ingress):
			print(f"Processing service {namespace}/{service} with hosts {hosts}")
			service_res = service_selector(namespace, service)
			node = pick_ready_pod_node(namespace, service_res)
			if node:
				target_node = node
				print(f"Found ready node {target_node} for service {namespace}/{service}")
				break

		if not target_node:
			print(f"No ready node found for service {namespace}/{service}, skipping")
			continue

		target_ip = node_v4.get(target_node)
		if not target_ip:
			print(f"No IP found for node {target_node}, skipping")
			continue

		for h in hosts:
			records.append({"name": h, "type": "A", "value": target_ip})

	records.sort(key=lambda r: (r["name"], r["value"]))
	atomic_write(OUTPUT_PATH, records)

def main():
	print("Starting DNS Operator")

	# print("Initial reconciliation")
	# reconcile()

	for _ in kr8s.watch("Ingress"):
		time.sleep(0.2)  # debounce bursts
		print("Watch event received, reconciling")
		reconcile()

if __name__ == "__main__":
	main()

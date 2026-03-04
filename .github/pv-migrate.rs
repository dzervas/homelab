#!/usr/bin/env rust-script
//! ```cargo
//! [dependencies]
//! kube = { version = "3", features = ["runtime", "client", "derive"] }
//! k8s-openapi = { version = "0.27", features = ["latest", "schemars"] }
//! schemars = "1"
//! tokio = { version = "1", features = ["full"] }
//! ```

use std::env;
use kube::{Config, Client, Api};
use kube::api::ListParams;
use kube::config::KubeConfigOptions;
use k8s_openapi::api::core::v1::Pod;

const NEW_STORAGE_CLASS: &str = "linstor-ha";
const OLD_STORAGE_CLASS: &str = "linstor";

#[tokio::main]
async fn main() {
	let args: Vec<String> = env::args().collect();

	let namespace = args.get(1).expect("Namespace argument is required");
	let pvc_name = args.get(2).expect("PVC name argument is required");

	let _new_storage_class = env::var("NEW_SC").unwrap_or_else(|_| {
		println!("NEW_SC environment variable not set, defaulting to '{NEW_STORAGE_CLASS}'");
		NEW_STORAGE_CLASS.to_string()
	});
	let _old_storage_class = env::var("OLD_SC").unwrap_or_else(|_| {
		println!("OLD_SC environment variable not set, defaulting to '{OLD_STORAGE_CLASS}'");
		OLD_STORAGE_CLASS.to_string()
	});

	let kubeconfig = KubeConfigOptions {
		context: Some("gr".to_string()),
		cluster: Some("gr".to_string()),
		user: Some("gr".to_string()),
	};
	let config = Config::from_kubeconfig(&kubeconfig).await.expect("Failed to load kubeconfig");
	let client = Client::try_from(config).expect("Failed to create Kubernetes client");

	let workloads = find_workloads_using_pvc(client, namespace, pvc_name).await;
	println!("Workloads using PVC '{pvc_name}': {:?}", workloads);
}

async fn find_workloads_using_pvc(client: Client, namespace: &str, pvc_name: &str) -> Vec<String> {
	let pods = Api::<Pod>::namespaced(client, namespace);
	let lp = ListParams::default();
	let mut affected_pods = Vec::new();

	for pod in pods.list(&lp).await.expect("Failed to list pods").items {
		let pod_spec = match pod.spec.as_ref() {
			Some(spec) => spec,
			None => continue,
		};
		let Some(volumes) = pod_spec.volumes.as_ref() else {
			continue;
		};

		let mut affected = false;
		for volume in volumes {
			let Some(pvc) = &volume.persistent_volume_claim  else {
				continue;
			};
			println!("PVC: {:?}", pvc);
			if pvc.claim_name == pvc_name {
				affected = true;
				affected_pods.push(pod.metadata.name.clone().unwrap());
				break;
			}
		}

		if !affected {
			continue;
		}

		println!("Pod '{}' is using PVC '{}'", pod.metadata.name.clone().unwrap(), pvc_name);

		println!("WorkloadRef for pod '{}': {:?}", pod.metadata.name.clone().unwrap(), pod.metadata.owner_references);
	}

	affected_pods
}

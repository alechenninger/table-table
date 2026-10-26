# kubectl table samples

Raw stdout captured from a temporary kind cluster on 2026-10-24. Spacing and
values are preserved exactly as printed by kubectl.

- `kubectl-pods-wide.txt`: `kubectl get pods --all-namespaces -o wide`.
  Includes running system pods and demo workloads captured while their images
  were pulling, multiple namespaces, multiword headers, and `<none>` values.
- `kubectl-services.txt`: `kubectl -n table-demo get services`.
  Includes ClusterIP, NodePort, headless, and LoadBalancer services, with `None`,
  `<none>`, `<pending>`, and port mappings.

The demo workloads were two nginx frontend replicas and one Redis cache replica.
The temporary cluster was removed after capture.

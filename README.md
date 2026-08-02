# Bridge the Gap: Cross-Cloud Workload Identity (AWS to Azure)

Proof-of-concept: a service in AWS calls a service in Azure with no static credentials. Authentication relies entirely on SPIFFE identities issued by SPIRE, and mutual TLS is used for every hop. An OPA-based authorization layer restricts what the AWS service is allowed to do once authenticated.

## Architecture

_(Architecture diagram, Mermaid flowchart, added separately.)_

Both clusters run a full Istio control plane and SPIRE deployment, but the actual Service A → Service B call is **not** proxied by Envoy. That's a deliberate architecture decision, explained under "Why application-level mTLS" below.

## Identities Issued

| Workload | Trust domain | SPIFFE ID | Issued via |
|---|---|---|---|
| Service A (AWS) | `aws.bridgethegap.local` | `spiffe://aws.bridgethegap.local/ns/workloads/sa/service-a` | k8s node attestation (`k8s_psat`) plus k8s workload attestor matching namespace/ServiceAccount/pod label |
| Service B (Azure) | `azure.bridgethegap.local` | `spiffe://azure.bridgethegap.local/ns/workloads/sa/service-b` | same mechanism, Azure SPIRE server |
| Istio sidecars (both clusters) | respective trust domain | `spiffe://<domain>/ns/<namespace>/sa/<service-account>` | `ClusterSPIFFEID` `istio-sidecar-reg`, matches pods labeled `spiffe.io/spire-managed-identity: "true"` |
| Istio ingress gateway (Azure) | `azure.bridgethegap.local` | `spiffe://azure.bridgethegap.local/ns/istio-system/sa/istio-ingressgateway` | `ClusterSPIFFEID` `istio-ingressgateway-reg` (not used in the Service A to B call path; part of the standard mesh install) |

All identities are X.509-SVIDs with short TTLs, rotated automatically by SPIRE. Nothing here is a static secret. No API key, password, or long-lived token is stored anywhere in either cluster or in the application code.

**Proof from SPIRE itself** (registration entries: what SPIRE is actually configured to issue, not just what the application logs claim):

![AWS SPIRE registration entries](docs/images/02a-spire-entries-aws.png)

![Azure SPIRE registration entries, part 1](docs/images/02b-spire-entries-azure.png)

![Azure SPIRE registration entries, part 2](docs/images/02c-spire-entries-azure-cont.png)

Both sides show `FederatesWith: <the other cloud's trust domain>` on every entry. That's SPIRE's own record of the federation relationship, not something asserted only in application code.

## Trust Relationship Between Environments

**Proof of automatic, periodic bundle refresh** (not a one-time static exchange; this is what makes the trust relationship dynamic rather than a shared secret):

![SPIRE bundle refresh log evidence, ~75s interval](docs/images/02d-bundle-refresh-evidence.png)

Each cloud runs its own independent SPIRE server with its own trust domain and root CA. The two clouds aren't naturally aware of each other. Trust between them is established through **SPIRE Federation**:

1. Each SPIRE server exposes a federation bundle endpoint (`spire-server-federation-lb`, a Kubernetes `LoadBalancer` Service), which serves that server's current trust bundle (its root CA certificates) over an mTLS-protected endpoint.
2. A `ClusterFederatedTrustDomain` resource on each side points at the other cloud's bundle endpoint.
3. Bootstrapping this relationship required one manual, trust-on-first-use exchange (`spire-server bundle set` / `bundle show`). That's the one moment a human had to vouch for the initial trust, standard practice for federation setup and similar to exchanging root certificates between two independent PKIs.
4. After bootstrap, each SPIRE server automatically re-fetches and refreshes the peer's bundle on its own (observed interval: about 75 seconds), so certificate rotation on either side never breaks trust. No manual re-exchange is ever needed again.

The practical effect: Service B's SPIRE server trusts AWS's root CA (and can therefore validate Service A's certificate), and Service A's SPIRE server trusts Azure's root CA, entirely through this dynamic bundle exchange, never through a shared static secret.

## How Authentication Works

**1. Node attestation.** Every SPIRE agent proves to its SPIRE server that it's running on a legitimate node in the cluster, using the `k8s_psat` (Kubernetes Projected Service Account Token) attestor. The node presents a token bound to the Kubernetes API server, which SPIRE validates against the cluster's own token review API. This ties node identity to something Kubernetes itself vouches for, not to network location (IP/hostname), which is spoofable and ephemeral in cloud environments.

**2. Workload attestation.** Once an agent is trusted, it attests the workloads running on it using the k8s workload attestor. For every pod requesting an identity, SPIRE inspects the pod's actual namespace, ServiceAccount, and labels (via the container runtime / kubelet) and matches them against the selectors declared in a `ClusterSPIFFEID` resource. Only pods matching `spiffe.io/spire-managed-identity: "true"` in the `workloads` namespace, with the expected ServiceAccount, receive an SVID for `service-a` or `service-b`. A pod can't claim an identity it doesn't structurally match. There's no shared secret a compromised pod could steal and reuse elsewhere.

**3. SVID issuance.** SPIRE issues each workload a short-lived X.509-SVID over the SPIFFE Workload API (a Unix domain socket, `csi.spiffe.io`, mounted read-only into the pod). The workload never sees or handles a static key it could leak. It fetches short-lived key material on demand and SPIRE rotates it automatically.

**4. Mutual TLS at the application layer.** Both Service A and Service B use `go-spiffe/v2` directly. Service A opens an mTLS client via `tlsconfig.MTLSClientConfig`, Service B serves via `tlsconfig.MTLSServerConfig`. Each side requires the peer's certificate to resolve to one exact expected SPIFFE ID (`tlsconfig.AuthorizeID`), not merely "any SPIFFE identity" (`AuthorizeAny`, which would be a serious authorization gap). Both directions are mutually authenticated: Service B only accepts connections from `spiffe://aws.bridgethegap.local/ns/workloads/sa/service-a`, and Service A only trusts a server presenting `spiffe://azure.bridgethegap.local/ns/workloads/sa/service-b`.

**5. Authorization (OPA).** Passing the mTLS handshake only proves identity. It doesn't decide what a caller may do. Service B extracts the caller's verified SPIFFE ID from the TLS peer certificate and asks an OPA sidecar (bound to `localhost:8181`, unreachable outside the pod) to evaluate a Rego policy against `{spiffe_id, path, method}`. The policy is a default-deny allow-list: only `GET /hello` from `service-a`'s exact identity is permitted, `/admin` is denied regardless of caller. The application fails closed if OPA is unreachable.

### Why application-level mTLS, not an Istio-native mesh hop

The initial plan was to let Envoy terminate mTLS for this call, using Istio's SPIFFE integration end-to-end. In practice, Istio's SDS-based certificate distribution (via istio-agent) only requests and serves its own fixed trust bundle vocabulary (`default`/`ROOTCA`) and doesn't automatically merge an additional SPIFFE-federated trust domain's CA into Envoy's validation context. That's a genuine integration gap between vanilla Istio sidecar injection and SPIFFE Federation, not a misconfiguration on our side. Fixing it properly would require a custom `EnvoyFilter` with a statically pre-combined CA bundle, which is real production engineering but goes beyond this project's stated scope ("mutual TLS authentication between services", not "Envoy must terminate every hop"). We deliberately descoped that path and instead terminate SPIFFE mTLS natively in the application via `go-spiffe`, which satisfies every stated completion criterion without the added complexity. Istio and its sidecars remain fully deployed and functioning for identity issuance to the mesh's own components. They just aren't the enforcement point for this specific cross-cloud hop.

## Proof: Successful Authenticated Call

**The real certificate served by Service B**, extracted directly from the network, not from application code or logs. Note the SPIFFE URI in the Subject Alternative Name and a validity window of about four hours, not months or years:

![Real SVID certificate: SPIFFE SAN + short validity](docs/images/03-real-svid-certificate.png)

Both services also log their own verified SPIFFE identity on startup:

```
Service A identity: spiffe://aws.bridgethegap.local/ns/workloads/sa/service-a
Service B identity: spiffe://azure.bridgethegap.local/ns/workloads/sa/service-b
```

Calling through Service A's test endpoint (which triggers the outbound mTLS call to Service B): `/hello` succeeds, and the restricted `/admin` path is denied by the OPA policy for the same authenticated identity.

![/hello succeeds (200), /admin denied (403)](docs/images/04-hello-success.png)

OPA's decision log for those same two requests, showing the actual input evaluated (caller identity, path, method) and the resulting decision:

![OPA decision log: result=true for /hello, result=false for /admin](docs/images/05-opa-decision-logs.png)

**Negative test (completion criterion #4):** a client presenting no certificate at all is rejected during the TLS handshake itself, before any HTTP request is even processed. `curl` fails with `SSL routines::tlsv13 alert certificate required`. Identity isn't optional here. The connection can't be established at all without it, let alone reach the authorization layer.

![Negative test: no client certificate, TLS alert "certificate required"](docs/images/06-negative-test-no-identity.png)

## Bonus Challenge 1: Workload Attestation

Already covered in detail under "How Authentication Works", steps 1 and 2. In summary: **node attestation** uses `k8s_psat`, and **workload attestation** uses the k8s workload attestor matching namespace, ServiceAccount, and pod labels, driven declaratively by `ClusterSPIFFEID` resources (managed in Terraform, see `terraform/aws/spire.tf` and `terraform/azure/spire.tf`).

This mechanism was chosen over cloud-metadata-based attestation (like AWS/Azure instance identity documents) because it's Kubernetes-native and portable across both clouds with the same logic. The same attestation model applies whether the cluster runs on AWS or Azure, which matters directly for a cross-cloud project. It also ties identity to attributes Kubernetes RBAC already governs (namespace, ServiceAccount), rather than to network-layer facts (IP, hostname) that are ephemeral and, in a compromised-node scenario, potentially attacker-influenced.

## Bonus Challenge 2: Authorization Policy

Implemented and verified (see "Proof" above). `/hello` is allowed for `service-a`'s exact SPIFFE identity, `/admin` is denied unconditionally. Enforcement is via an **OPA sidecar** (Policy Decision Point) plus a Go middleware in Service B (Policy Enforcement Point), rather than an Istio `AuthorizationPolicy`. That's a direct consequence of the architecture decision above: Envoy doesn't terminate this port's mTLS, so it can't see the HTTP path to apply an `AuthorizationPolicy` against. That enforcement point would be a structural no-op given how this hop is secured. OPA was chosen specifically because the assignment names it as a valid alternative mechanism to Istio-native authorization.

## Bonus Challenge 3: Observability

**Not implemented.** Kiali visualizes mesh traffic by observing what Envoy proxies. Because the authenticated Service A to Service B call deliberately bypasses Envoy interception (`traffic.sidecar.istio.io/excludeInboundPorts`) so the application can terminate SPIFFE mTLS natively, Kiali wouldn't show this specific hop even if deployed. It would only show mTLS between other in-mesh components (sidecar-to-istiod, ingress gateway), which isn't the interesting call for this project. Attempting it would have produced a dashboard that looked like it demonstrated something it didn't. Left out rather than built as a hollow checkbox.

## Challenges Encountered

- **SPIRE Federation bootstrap** required understanding the distinction between the one-time manual trust-on-first-use bundle exchange and the ongoing automatic refresh. Easy to conflate the two at first.
- **Infrastructure drift into raw `kubectl`**: the `ClusterSPIFFEID` registrations were initially applied by hand outside Terraform. Caught and brought under IaC (`terraform import` on Azure, fresh resources on AWS) so the whole platform layer stays declarative.
- **Cross-trust-domain mTLS validation gap in Istio/SPIFFE Federation**: extensively debugged (`remote error: tls: unknown certificate`), root-caused to Istio's SDS proxy not merging federated CA bundles into Envoy's validation context. Explored a full `EnvoyFilter` plus static combined-bundle fix, then deliberately stepped back from it as over-engineering relative to the actual assignment scope, landing on application-level SPIFFE mTLS instead.
- **Docker image architecture mismatch**: Docker Desktop on Apple Silicon builds `arm64` images by default, but both EKS and AKS nodes run `amd64`, causing `ErrImagePull: no match for platform in manifest`. Fixed by building explicitly with `--platform linux/amd64`.
- **Terraform drift on Azure**: an externally-injected `created-on` tag (very likely a subscription-level Azure Policy) and an undeclared `default_node_pool.upgrade_settings` block both caused `terraform plan` to show phantom changes on every run. Fixed with a scoped `lifecycle { ignore_changes }` for the tag and by declaring the block's actual default values. `terraform plan` now reports "No changes" on both clouds.
- **Azure Load Balancer health probes** initially looked like suspicious repeated TLS handshake failures in Service B's logs. Confirmed via node/pod IP correlation that they were the LB's own bare-TCP health check hitting a TLS-only port. Benign, not a security signal.

## Infrastructure Teardown

Not yet performed. Infrastructure is still up for demonstration purposes. To tear down:

```bash
cd terraform/azure && terraform destroy
cd terraform/aws && terraform destroy
```

Run Azure before AWS if both are torn down in the same session. There's no hard dependency between the two clouds, but Azure's federation bundle endpoint should stop being queried before AWS's SPIRE server is removed, to avoid noisy federation errors during teardown. Cosmetic, not a correctness issue.

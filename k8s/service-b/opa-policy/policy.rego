package servicetb.authz

import future.keywords.if

default allow := false

# Explicit allow-list: only service-a's SPIFFE identity, only GET /hello.
# Everything else (wrong identity, wrong path, wrong method) falls through
# to the default deny above.
allow if {
	input.method == "GET"
	input.path == "/hello"
	input.spiffe_id == "spiffe://aws.bridgethegap.local/ns/workloads/sa/service-a"
}

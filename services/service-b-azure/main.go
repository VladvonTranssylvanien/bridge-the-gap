package main

import (
	"bytes"
	"context"
	"crypto/x509"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"time"

	"github.com/spiffe/go-spiffe/v2/spiffeid"
	"github.com/spiffe/go-spiffe/v2/spiffetls/tlsconfig"
	"github.com/spiffe/go-spiffe/v2/svid/x509svid"
	"github.com/spiffe/go-spiffe/v2/workloadapi"
)

const opaURL = "http://localhost:8181/v1/data/servicetb/authz/allow"

var opaClient = &http.Client{Timeout: 2 * time.Second}

// opaInput mirrors the `input` document evaluated by policy.rego.
type opaInput struct {
	SpiffeID string `json:"spiffe_id"`
	Path     string `json:"path"`
	Method   string `json:"method"`
}

type opaResponse struct {
	Result bool `json:"result"`
}

// callerSPIFFEID extracts and re-validates the caller's identity from the
// already-verified mTLS peer certificate. The TLS handshake (tlsconfig.AuthorizeID
// below) already proved the certificate chains to a trusted SPIRE-issued SVID;
// this just reads the SPIFFE URI back out of it for the policy decision.
func callerSPIFFEID(cert *x509.Certificate) (spiffeid.ID, error) {
	id, err := x509svid.IDFromCert(cert)
	if err != nil {
		return spiffeid.ID{}, fmt.Errorf("no SPIFFE ID in peer certificate: %w", err)
	}
	return id, nil
}

// askOPA is the Policy Enforcement Point's call to the Policy Decision Point.
// Service B does not decide authorization itself; it asks OPA and enforces
// whatever OPA returns. Fails closed: any error talking to OPA is a deny.
func askOPA(spiffeID, path, method string) bool {
	body, _ := json.Marshal(map[string]opaInput{"input": {SpiffeID: spiffeID, Path: path, Method: method}})
	resp, err := opaClient.Post(opaURL, "application/json", bytes.NewReader(body))
	if err != nil {
		log.Printf("OPA request failed, denying by default: %v", err)
		return false
	}
	defer resp.Body.Close()

	var decision opaResponse
	if err := json.NewDecoder(resp.Body).Decode(&decision); err != nil {
		log.Printf("OPA response unreadable, denying by default: %v", err)
		return false
	}
	return decision.Result
}

// withAuthz is the enforcement middleware (PEP). It is the only place in
// this service that makes an authorization decision, and it does so by
// delegating to OPA (PDP) rather than encoding rules inline.
func withAuthz(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if len(r.TLS.PeerCertificates) == 0 {
			http.Error(w, "forbidden: no client certificate presented", http.StatusForbidden)
			return
		}
		callerID, err := callerSPIFFEID(r.TLS.PeerCertificates[0])
		if err != nil {
			http.Error(w, "forbidden: unable to determine caller identity", http.StatusForbidden)
			return
		}

		allowed := askOPA(callerID.String(), r.URL.Path, r.Method)
		log.Printf("authz decision: caller=%s path=%s method=%s allow=%v", callerID.String(), r.URL.Path, r.Method, allowed)
		if !allowed {
			http.Error(w, "forbidden: denied by policy", http.StatusForbidden)
			return
		}
		next(w, r)
	}
}

func helloHandler(w http.ResponseWriter, r *http.Request) {
	fmt.Fprintln(w, "hello from azure service")
}

func adminHandler(w http.ResponseWriter, r *http.Request) {
	// Reachable only if OPA's policy allows it. Current policy.rego never
	// allows this path, so this handler's own logic doesn't matter for the
	// authorization demo, but it no longer duplicates the authz decision.
	fmt.Fprintln(w, "admin action executed")
}

func main() {
	ctx := context.Background()

	source, err := workloadapi.NewX509Source(ctx)
	if err != nil {
		log.Fatalf("unable to create X509Source: %v", err)
	}
	defer source.Close()

	svid, err := source.GetX509SVID()
	if err != nil {
		log.Fatalf("unable to fetch own SVID: %v", err)
	}
	log.Printf("Service B identity: %s", svid.ID.String())

	clientID := spiffeid.RequireFromString("spiffe://aws.bridgethegap.local/ns/workloads/sa/service-a")

	tlsConfig := tlsconfig.MTLSServerConfig(source, source, tlsconfig.AuthorizeID(clientID))

	mux := http.NewServeMux()
	mux.HandleFunc("/hello", withAuthz(helloHandler))
	mux.HandleFunc("/admin", withAuthz(adminHandler))

	server := &http.Server{
		Addr:      ":8080",
		Handler:   mux,
		TLSConfig: tlsConfig,
	}

	log.Println("Service B (mTLS) listening on :8080")
	log.Fatal(server.ListenAndServeTLS("", ""))
}

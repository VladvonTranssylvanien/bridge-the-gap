package main

import (
	"context"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/spiffe/go-spiffe/v2/spiffeid"
	"github.com/spiffe/go-spiffe/v2/spiffetls/tlsconfig"
	"github.com/spiffe/go-spiffe/v2/workloadapi"
)

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func main() {
	serviceBBaseURL := getEnv("SERVICE_B_BASE_URL", "https://20.103.67.78:8080")
	serviceBIDStr := getEnv("SERVICE_B_SPIFFE_ID", "spiffe://azure.bridgethegap.local/ns/workloads/sa/service-b")

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
	log.Printf("Service A identity: %s", svid.ID.String())

	expectedServiceBID, err := spiffeid.FromString(serviceBIDStr)
	if err != nil {
		log.Fatalf("invalid SERVICE_B_SPIFFE_ID %q: %v", serviceBIDStr, err)
	}

	tlsConfig := tlsconfig.MTLSClientConfig(source, source, tlsconfig.AuthorizeID(expectedServiceBID))
	client := &http.Client{
		Transport: &http.Transport{TLSClientConfig: tlsConfig},
		Timeout:   10 * time.Second,
	}

	callServiceB := func(path string) (int, string, error) {
		url := strings.TrimSuffix(serviceBBaseURL, "/") + path
		resp, err := client.Get(url)
		if err != nil {
			return 0, "", err
		}
		defer resp.Body.Close()
		body, err := io.ReadAll(resp.Body)
		if err != nil {
			return resp.StatusCode, "", err
		}
		return resp.StatusCode, string(body), nil
	}

	http.HandleFunc("/call-service-b", func(w http.ResponseWriter, r *http.Request) {
		status, body, err := callServiceB("/hello")
		if err != nil {
			http.Error(w, fmt.Sprintf("call to service-b failed: %v", err), http.StatusBadGateway)
			return
		}
		fmt.Fprintf(w, "service-b responded (status %d): %s\n", status, body)
	})

	http.HandleFunc("/call-service-b-admin", func(w http.ResponseWriter, r *http.Request) {
		status, body, err := callServiceB("/admin")
		if err != nil {
			http.Error(w, fmt.Sprintf("call to service-b failed: %v", err), http.StatusBadGateway)
			return
		}
		fmt.Fprintf(w, "service-b responded (status %d): %s\n", status, body)
	})

	http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintln(w, "ok")
	})

	log.Println("Service A listening on :8080")
	log.Fatal(http.ListenAndServe(":8080", nil))
}

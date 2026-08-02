package main

import (
	"context"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
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
	serviceBURL := getEnv("SERVICE_B_URL", "https://20.103.67.78:8080/hello")
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

	http.HandleFunc("/call-service-b", func(w http.ResponseWriter, r *http.Request) {
		resp, err := client.Get(serviceBURL)
		if err != nil {
			log.Printf("call to service-b failed: %v", err)
			http.Error(w, fmt.Sprintf("call to service-b failed: %v", err), http.StatusBadGateway)
			return
		}
		defer resp.Body.Close()

		body, err := io.ReadAll(resp.Body)
		if err != nil {
			http.Error(w, fmt.Sprintf("failed to read response: %v", err), http.StatusInternalServerError)
			return
		}

		fmt.Fprintf(w, "service-b responded (status %d): %s\n", resp.StatusCode, string(body))
	})

	http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintln(w, "ok")
	})

	log.Println("Service A listening on :8080")
	log.Fatal(http.ListenAndServe(":8080", nil))
}

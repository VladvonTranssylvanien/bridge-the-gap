package main

import (
	"fmt"
	"log"
	"net/http"
)

func helloHandler(w http.ResponseWriter, r *http.Request) {
	fmt.Fprintln(w, "hello from azure service")
}

func main() {
	http.HandleFunc("/hello", helloHandler)
	log.Println("Service B listening on :8080")
	log.Fatal(http.ListenAndServe(":8080", nil))
}

package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
)

func main() {
	msg := os.Getenv("DEMO_MESSAGE")
	if msg == "" {
		msg = "secure-gitops-platform"
	}

	http.HandleFunc("/", func(w http.ResponseWriter, _ *http.Request) {
		_, _ = fmt.Fprintf(w, "ok:%s", msg)
	})

	http.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})

	addr := ":8080"
	log.Printf("listening on %s", addr)
	log.Fatal(http.ListenAndServe(addr, nil))
}

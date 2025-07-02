package main

import (
	"log"
	"os"

	"github.com/grandcat/zeroconf"
)

func StartmDNSService(shutdown chan struct{}) {
	// Get the hostname to use as the instance name
	host, err := os.Hostname()
	if err != nil {
		log.Printf("Failed to get hostname for mDNS, using default 'op25-pi': %v", err)
		host = "op25-pi"
	}

	// Register the service using zeroconf
	server, err := zeroconf.Register(
		host,               // Unique instance name (e.g., "OP25-Pi.local")
		"_op25mch._tcp",    // Service type for our app
		"local.",           // Domain for local network
		9000,               // The port our HTTP server is running on
		[]string{"txtv=0"}, // Optional TXT records
		nil,                // Network interfaces (nil for all)
	)
	if err != nil {
		log.Fatalf("Failed to start mDNS service: %v", err)
	}

	log.Printf("mDNS service started. Broadcasting as %s._op25mch._tcp.local.", host)

	// Keep the service alive until a shutdown signal is received
	<-shutdown

	log.Println("Shutting down mDNS service...")
	server.Shutdown()
	log.Println("mDNS service shut down.")
}
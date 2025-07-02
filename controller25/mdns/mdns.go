package mdns

import (
    "log"
    "os"

    "github.com/grandcat/zeroconf"
)

func StartmDNSService(shutdown chan struct{}) {
    host, err := os.Hostname()
    if err != nil {
        log.Printf("Failed to get hostname for mDNS, using default 'op25-pi': %v", err)
        host = "op25-pi"
    }

    server, err := zeroconf.Register(
        host,
        "_op25mch._tcp",
        "local.",
        9000,
        []string{"txtv=0"},
        nil,
    )
    if err != nil {
        log.Fatalf("Failed to start mDNS service: %v", err)
    }

    log.Printf("mDNS service started. Broadcasting as %s._op25mch._tcp.local.", host)

    <-shutdown

    log.Println("Shutting down mDNS service...")
    server.Shutdown()
    log.Println("mDNS service shut down.")
}
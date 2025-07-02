package main

import (
    "log"
    "net/http"
    "os"
    "os/signal"
    "syscall"

    "controller25/audio"
    "controller25/config"
    "controller25/health"
    "controller25/log"
    "controller25/mdns"
)

func main() {
    log.Println("Starting controller25 server...")
    log.Println("Loading configuration...")

    cfg := config.MustLoadConfig("config.ini")
    log.Printf("Configuration loaded. OP25 path: %s", cfg.Op25RxPath)

    log.Println("Changing working directory...")
    config.MustChdir(cfg.Op25RxPath)
    log.Println("Working directory changed")

    log.Println("Starting OP25 process...")
    op25Cmd, stdoutPipe, stderrPipe := config.StartOp25ProcessUDP()

    // Create broadcasters
    audioBroadcaster := audio.NewBroadcaster("127.0.0.1:23456")
    logBroadcaster := logstream.NewBroadcaster(stdoutPipe, stderrPipe)

    // Start broadcasters
    go audioBroadcaster.Start()
    go logBroadcaster.Start()

    // Start mDNS Service
    mdnsShutdown := make(chan struct{})
    go mdns.StartmDNSService(mdnsShutdown)

    // Setup HTTP handlers
    http.HandleFunc("/audio.wav", audioBroadcaster.ServeWAV)
    http.HandleFunc("/stream", logBroadcaster.ServeSSE)
    http.HandleFunc("/health", health.ServeHealth)

    // Channel for shutdown
    done := make(chan struct{})

    // Goroutine for graceful shutdown
    go func() {
        sigChan := make(chan os.Signal, 1)
        signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
        <-sigChan

        log.Println("Shutting down...")

        // Shutdown mDNS
        close(mdnsShutdown)

        // Shutdown audio broadcaster
        audioBroadcaster.Shutdown()

        // Terminate OP25 process
        if op25Cmd.Process != nil {
            log.Println("Terminating OP25 process...")
            syscall.Kill(-op25Cmd.Process.Pid, syscall.SIGKILL)
            op25Cmd.Wait()
            log.Println("OP25 process terminated")
        }

        close(done)
    }()

    log.Println("Starting HTTP server on :9000")
    server := &http.Server{Addr: ":9000"}
    go func() {
        if err := server.ListenAndServe(); err != http.ErrServerClosed {
            log.Fatalf("HTTP server failed: %v", err)
        }
    }()

    <-done
    log.Println("Server shutdown complete")
}
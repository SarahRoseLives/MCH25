package main

import (
    "encoding/json"
    "io"
    "log"
    "net/http"
    "os"
    "os/exec"
    "os/signal"
    "sync"
    "syscall"

    "controller25/audio"
    "controller25/config"
    "controller25/health"
    "controller25/log"
    "controller25/mdns"
)

type Op25State struct {
    cmdObj     *exec.Cmd
    stdoutPipe io.ReadCloser
    stderrPipe io.ReadCloser
    running    bool
    flags      []string
    mu         sync.Mutex
}

var op25 Op25State

// API request/response types
type Op25StartRequest struct {
    Flags []string `json:"flags"`
}
type Op25StartResponse struct {
    Started bool   `json:"started"`
    Error   string `json:"error,omitempty"`
}
type Op25StatusResponse struct {
    Running bool     `json:"running"`
    Flags   []string `json:"flags"`
}

// Trunk API types
type TrunkReadResponse struct {
    SysName        string `json:"sysname"`
    ControlChannel string `json:"control_channel"`
    Error          string `json:"error,omitempty"`
}
type TrunkWriteRequest struct {
    SysName        string `json:"sysname"`
    ControlChannel string `json:"control_channel"`
}
type TrunkWriteResponse struct {
    Success bool   `json:"success"`
    Error   string `json:"error,omitempty"`
}

func stopOp25(audioBroadcaster **audio.Broadcaster, logBroadcaster **logstream.Broadcaster) {
    if op25.cmdObj != nil && op25.cmdObj.Process != nil {
        log.Println("Terminating OP25 process...")
        syscall.Kill(-op25.cmdObj.Process.Pid, syscall.SIGKILL)
        op25.cmdObj.Wait()
        log.Println("OP25 process terminated")
    }
    op25.running = false
    op25.flags = nil
    op25.cmdObj = nil
    op25.stdoutPipe = nil
    op25.stderrPipe = nil
    if *audioBroadcaster != nil {
        (*audioBroadcaster).Shutdown()
        *audioBroadcaster = nil
    }
    if *logBroadcaster != nil {
        *logBroadcaster = nil
    }
}

func main() {
    log.Println("Starting controller25 server...")
    log.Println("Loading configuration...")

    cfg := config.MustLoadConfig("config.ini")
    log.Printf("Configuration loaded. OP25 path: %s", cfg.Op25RxPath)

    log.Println("Changing working directory...")
    config.MustChdir(cfg.Op25RxPath)
    log.Println("Working directory changed")

    // Do NOT auto-start OP25 on first run!
    // Instead, wait for API request to /api/op25/start

    // Audio and log broadcasters are initialized when OP25 starts
    var (
        audioBroadcaster *audio.Broadcaster
        logBroadcaster   *logstream.Broadcaster
    )

    // Start mDNS Service
    mdnsShutdown := make(chan struct{})
    go mdns.StartmDNSService(mdnsShutdown)

    // Setup HTTP handlers
    http.HandleFunc("/audio.wav", func(w http.ResponseWriter, r *http.Request) {
        if audioBroadcaster == nil {
            http.Error(w, "Audio not broadcasting (OP25 not started)", http.StatusServiceUnavailable)
            return
        }
        audioBroadcaster.ServeWAV(w, r)
    })
    http.HandleFunc("/stream", func(w http.ResponseWriter, r *http.Request) {
        if logBroadcaster == nil {
            http.Error(w, "Logs not broadcasting (OP25 not started)", http.StatusServiceUnavailable)
            return
        }
        logBroadcaster.ServeSSE(w, r)
    })
    http.HandleFunc("/health", health.ServeHealth)

    http.HandleFunc("/api/op25/start", func(w http.ResponseWriter, r *http.Request) {
        if r.Method != http.MethodPost {
            http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
            return
        }
        var req Op25StartRequest
        if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
            http.Error(w, "Invalid request body", http.StatusBadRequest)
            return
        }

        op25.mu.Lock()
        defer op25.mu.Unlock()
        // If already running, shut down and restart
        if op25.running {
            stopOp25(&audioBroadcaster, &logBroadcaster)
        }

        // Start OP25 with specified flags
        op25Cmd, stdoutPipe, stderrPipe, err := config.StartOp25ProcessUDPWithFlags(req.Flags)
        if err != nil {
            resp := Op25StartResponse{Started: false, Error: err.Error()}
            _ = json.NewEncoder(w).Encode(resp)
            return
        }

        op25.cmdObj = op25Cmd
        op25.stdoutPipe = stdoutPipe
        op25.stderrPipe = stderrPipe
        op25.running = true
        op25.flags = req.Flags

        // Start broadcasters
        audioBroadcaster = audio.NewBroadcaster("127.0.0.1:23456")
        logBroadcaster = logstream.NewBroadcaster(stdoutPipe, stderrPipe)
        go audioBroadcaster.Start()
        go logBroadcaster.Start()

        resp := Op25StartResponse{Started: true}
        _ = json.NewEncoder(w).Encode(resp)
    })

    http.HandleFunc("/api/op25/stop", func(w http.ResponseWriter, r *http.Request) {
        if r.Method != http.MethodPost {
            http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
            return
        }
        op25.mu.Lock()
        defer op25.mu.Unlock()
        if !op25.running || op25.cmdObj == nil {
            w.WriteHeader(http.StatusConflict)
            _ = json.NewEncoder(w).Encode(Op25StartResponse{Started: false, Error: "OP25 not running"})
            return
        }
        stopOp25(&audioBroadcaster, &logBroadcaster)
        _ = json.NewEncoder(w).Encode(Op25StartResponse{Started: false})
    })

    http.HandleFunc("/api/op25/status", func(w http.ResponseWriter, r *http.Request) {
        op25.mu.Lock()
        defer op25.mu.Unlock()
        _ = json.NewEncoder(w).Encode(Op25StatusResponse{
            Running: op25.running,
            Flags:   op25.flags,
        })
    })

    // Trunk file read endpoint
    http.HandleFunc("/api/trunk/read", func(w http.ResponseWriter, r *http.Request) {
        if r.Method != http.MethodGet {
            http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
            return
        }
        sys, err := config.ReadTrunkSystem(config.TrunkFileName)
        if err != nil {
            _ = json.NewEncoder(w).Encode(TrunkReadResponse{Error: err.Error()})
            return
        }
        _ = json.NewEncoder(w).Encode(TrunkReadResponse{
            SysName:        sys.SysName,
            ControlChannel: sys.ControlChannel,
        })
    })

    // Trunk file write endpoint
    http.HandleFunc("/api/trunk/write", func(w http.ResponseWriter, r *http.Request) {
        if r.Method != http.MethodPost {
            http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
            return
        }
        var req TrunkWriteRequest
        if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
            _ = json.NewEncoder(w).Encode(TrunkWriteResponse{Success: false, Error: "Invalid request body"})
            return
        }
        sys := &config.TrunkSystem{
            SysName:        req.SysName,
            ControlChannel: req.ControlChannel,
        }
        err := config.WriteTrunkSystem(config.TrunkFileName, sys)
        if err != nil {
            _ = json.NewEncoder(w).Encode(TrunkWriteResponse{Success: false, Error: err.Error()})
            return
        }
        _ = json.NewEncoder(w).Encode(TrunkWriteResponse{Success: true})
    })

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

        // Shutdown audio broadcaster and OP25 process
        op25.mu.Lock()
        stopOp25(&audioBroadcaster, &logBroadcaster)
        op25.mu.Unlock()

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
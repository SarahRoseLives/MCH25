package main

import (
    "bufio"
    "fmt"
    "io"
    "log"
    "net/http"
    "sync"
    "time"
)

type LogBroadcaster struct {
    mu       sync.Mutex
    clients  map[chan string]struct{}
    stdout   io.Reader
    stderr   io.Reader
    history  []string
    maxLines int
    startTime time.Time
}

func NewLogBroadcaster(stdout, stderr io.Reader) *LogBroadcaster {
    lb := &LogBroadcaster{
        clients:  make(map[chan string]struct{}),
        stdout:   stdout,
        stderr:   stderr,
        history:  make([]string, 0),
        maxLines: 1000,
        startTime: time.Now(),
    }

    // Add initial startup message
    lb.broadcast(fmt.Sprintf("[system] OP25 process starting at %s", lb.startTime.Format(time.RFC3339)))
    return lb
}

func (b *LogBroadcaster) Start() {
    // Add system messages before starting pipes
    b.broadcast("[system] Starting log broadcaster")
    b.broadcast("[system] Setting up stdout and stderr pipes")

    if b.stdout != nil {
        go b.readPipe(b.stdout, "[stdout]")
    } else {
        msg := "[system] Warning: nil stdout pipe, skipping stdout log streaming"
        log.Print(msg)
        b.broadcast(msg)
    }
    if b.stderr != nil {
        go b.readPipe(b.stderr, "[stderr]")
    } else {
        msg := "[system] Warning: nil stderr pipe, skipping stderr log streaming"
        log.Print(msg)
        b.broadcast(msg)
    }
}

func (b *LogBroadcaster) readPipe(pipe io.Reader, prefix string) {
    if pipe == nil {
        msg := fmt.Sprintf("[system] Error: readPipe called with nil pipe for %s", prefix)
        log.Print(msg)
        b.broadcast(msg)
        return
    }

    // Add pipe startup message
    b.broadcast(fmt.Sprintf("[system] Starting to read from %s pipe", prefix))

    scanner := bufio.NewScanner(pipe)
    for scanner.Scan() {
        line := fmt.Sprintf("%s %s", prefix, scanner.Text())
        b.broadcast(line)
    }

    if err := scanner.Err(); err != nil {
        msg := fmt.Sprintf("[system] Error reading pipe %s: %v", prefix, err)
        log.Print(msg)
        b.broadcast(msg)
    }

    // Add pipe closed message
    b.broadcast(fmt.Sprintf("[system] %s pipe closed", prefix))
}

func (b *LogBroadcaster) broadcast(line string) {
    log.Println(line) // Also log to console for debugging

    b.mu.Lock()
    defer b.mu.Unlock()

    // Add to history
    b.history = append(b.history, line)
    if len(b.history) > b.maxLines {
        b.history = b.history[len(b.history)-b.maxLines:]
    }

    // Send to clients
    for ch := range b.clients {
        select {
        case ch <- line:
        default:
            // Client is too slow, drop the connection
            delete(b.clients, ch)
            close(ch)
        }
    }
}

func (b *LogBroadcaster) ServeSSE(w http.ResponseWriter, r *http.Request) {
    w.Header().Set("Content-Type", "text/event-stream")
    w.Header().Set("Cache-Control", "no-cache")
    w.Header().Set("Connection", "keep-alive")
    w.Header().Set("Access-Control-Allow-Origin", "*")

    flusher, ok := w.(http.Flusher)
    if !ok {
        http.Error(w, "Streaming unsupported", http.StatusInternalServerError)
        return
    }

    // Create a buffered channel
    ch := make(chan string, 100)

    // Send history first
    b.mu.Lock()
    for _, line := range b.history {
        fmt.Fprintf(w, "data: %s\n\n", line)
    }
    flusher.Flush()

    // Register client
    b.clients[ch] = struct{}{}
    b.mu.Unlock()

    defer func() {
        b.mu.Lock()
        delete(b.clients, ch)
        b.mu.Unlock()
        close(ch)
    }()

    notify := r.Context().Done()
    for {
        select {
        case line := <-ch:
            fmt.Fprintf(w, "data: %s\n\n", line)
            flusher.Flush()
        case <-notify:
            return
        }
    }
}
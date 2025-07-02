package main

import (
    "encoding/binary"
    "log"
    "net"
    "net/http"
    "sync"
    "strings"
)

type AudioBroadcaster struct {
    udpAddr    string
    mu         sync.Mutex
    clients    map[chan []byte]struct{}
    quit       chan struct{}
    conn       *net.UDPConn
    sampleRate int
    channels   int
}

func NewAudioBroadcaster(udpAddr string) *AudioBroadcaster {
    return &AudioBroadcaster{
        udpAddr:    udpAddr,
        clients:    make(map[chan []byte]struct{}),
        quit:       make(chan struct{}),
        sampleRate: 8000,
        channels:   1,
    }
}

func (a *AudioBroadcaster) Start() {
    addr, err := net.ResolveUDPAddr("udp", a.udpAddr)
    if err != nil {
        log.Fatalf("Failed to resolve UDP address: %v", err)
    }

    conn, err := net.ListenUDP("udp", addr)
    if err != nil {
        log.Fatalf("Failed to listen on UDP: %v", err)
    }
    a.conn = conn

    // Set large buffer to prevent packet loss
    conn.SetReadBuffer(65536 * 10)

    log.Printf("Audio broadcaster started on %s (PCM S16_LE, %dHz, %d channel)",
        a.udpAddr, a.sampleRate, a.channels)

    // UDP reader goroutine
    go func() {
        defer conn.Close()

        // Buffer for 100ms of audio (8000 samples/sec * 2 bytes/sample * 0.1 sec)
        const frameSize = 8000 * 2 / 10
        buf := make([]byte, frameSize)

        for {
            select {
            case <-a.quit:
                return
            default:
                n, _, err := conn.ReadFromUDP(buf)
                if err != nil {
                    if !strings.Contains(err.Error(), "use of closed network connection") {
                        log.Printf("UDP read error: %v", err)
                    }
                    return
                }

                if n > 0 {
                    // Ensure we have complete 16-bit samples
                    if n%2 != 0 {
                        n-- // discard last byte if odd number
                    }

                    // Broadcast the raw PCM data
                    a.broadcast(buf[:n])
                }
            }
        }
    }()
}

func (a *AudioBroadcaster) broadcast(data []byte) {
    a.mu.Lock()
    defer a.mu.Unlock()

    for ch := range a.clients {
        select {
        case ch <- append([]byte{}, data...): // Send a copy of the data
        default:
            // Client buffer full, skip this data
        }
    }
}

func (a *AudioBroadcaster) ServeWAV(w http.ResponseWriter, r *http.Request) {
    w.Header().Set("Content-Type", "audio/wav")
    w.Header().Set("Cache-Control", "no-cache")
    w.Header().Set("Connection", "keep-alive")

    flusher, ok := w.(http.Flusher)
    if !ok {
        http.Error(w, "Streaming unsupported", http.StatusInternalServerError)
        return
    }

    // Write WAV header (for 16-bit PCM, mono, 8000Hz)
    header := makeWavHeader(a.sampleRate, a.channels)
    if _, err := w.Write(header); err != nil {
        return
    }
    flusher.Flush()

    // Create client channel
    ch := make(chan []byte, 100)
    a.mu.Lock()
    a.clients[ch] = struct{}{}
    a.mu.Unlock()

    defer func() {
        a.mu.Lock()
        delete(a.clients, ch)
        a.mu.Unlock()
        close(ch)
    }()

    // Stream audio data
    notify := r.Context().Done()
    for {
        select {
        case data := <-ch:
            if _, err := w.Write(data); err != nil {
                return
            }
            flusher.Flush()
        case <-notify:
            return
        }
    }
}

// Helper to create WAV header
func makeWavHeader(sampleRate, channels int) []byte {
    header := make([]byte, 44)
    copy(header[0:4], "RIFF")
    binary.LittleEndian.PutUint32(header[4:8], 0xFFFFFFFF) // Chunk size (unknown for streaming)
    copy(header[8:12], "WAVE")
    copy(header[12:16], "fmt ")
    binary.LittleEndian.PutUint32(header[16:20], 16) // Subchunk1Size (16 for PCM)
    binary.LittleEndian.PutUint16(header[20:22], 1)  // AudioFormat (PCM)
    binary.LittleEndian.PutUint16(header[22:24], uint16(channels))
    binary.LittleEndian.PutUint32(header[24:28], uint32(sampleRate))
    binary.LittleEndian.PutUint32(header[28:32], uint32(sampleRate*channels*2)) // ByteRate
    binary.LittleEndian.PutUint16(header[32:34], uint16(channels*2))            // BlockAlign
    binary.LittleEndian.PutUint16(header[34:36], 16)                            // BitsPerSample
    copy(header[36:40], "data")
    binary.LittleEndian.PutUint32(header[40:44], 0xFFFFFFFF) // Subchunk2Size (unknown for streaming)
    return header
}

func (a *AudioBroadcaster) Shutdown() {
    close(a.quit)
    if a.conn != nil {
        a.conn.Close()
    }
}
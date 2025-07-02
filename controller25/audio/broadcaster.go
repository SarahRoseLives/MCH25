package audio

import (
    "encoding/binary"
    "log"
    "net"
    "net/http"
    "strings"
    "sync"
)

type Broadcaster struct {
    udpAddr    string
    mu         sync.Mutex
    clients    map[chan []byte]struct{}
    quit       chan struct{}
    conn       *net.UDPConn
    SampleRate int
    Channels   int
}

func NewBroadcaster(udpAddr string) *Broadcaster {
    return &Broadcaster{
        udpAddr:    udpAddr,
        clients:    make(map[chan []byte]struct{}),
        quit:       make(chan struct{}),
        SampleRate: 8000,
        Channels:   1,
    }
}

func (a *Broadcaster) Start() {
    addr, err := net.ResolveUDPAddr("udp", a.udpAddr)
    if err != nil {
        log.Fatalf("Failed to resolve UDP address: %v", err)
    }

    conn, err := net.ListenUDP("udp", addr)
    if err != nil {
        log.Fatalf("Failed to listen on UDP: %v", err)
    }
    a.conn = conn

    conn.SetReadBuffer(65536 * 10)

    log.Printf("Audio broadcaster started on %s (PCM S16_LE, %dHz, %d channel)", a.udpAddr, a.SampleRate, a.Channels)

    go func() {
        defer conn.Close()
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
                    if n%2 != 0 {
                        n--
                    }
                    a.broadcast(buf[:n])
                }
            }
        }
    }()
}

func (a *Broadcaster) broadcast(data []byte) {
    a.mu.Lock()
    defer a.mu.Unlock()
    for ch := range a.clients {
        select {
        case ch <- append([]byte{}, data...):
        default:
        }
    }
}

func (a *Broadcaster) ServeWAV(w http.ResponseWriter, r *http.Request) {
    w.Header().Set("Content-Type", "audio/wav")
    w.Header().Set("Cache-Control", "no-cache")
    w.Header().Set("Connection", "keep-alive")
    flusher, ok := w.(http.Flusher)
    if !ok {
        http.Error(w, "Streaming unsupported", http.StatusInternalServerError)
        return
    }

    header := makeWavHeader(a.SampleRate, a.Channels)
    if _, err := w.Write(header); err != nil {
        return
    }
    flusher.Flush()

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

func makeWavHeader(sampleRate, channels int) []byte {
    header := make([]byte, 44)
    copy(header[0:4], "RIFF")
    binary.LittleEndian.PutUint32(header[4:8], 0xFFFFFFFF)
    copy(header[8:12], "WAVE")
    copy(header[12:16], "fmt ")
    binary.LittleEndian.PutUint32(header[16:20], 16)
    binary.LittleEndian.PutUint16(header[20:22], 1)
    binary.LittleEndian.PutUint16(header[22:24], uint16(channels))
    binary.LittleEndian.PutUint32(header[24:28], uint32(sampleRate))
    binary.LittleEndian.PutUint32(header[28:32], uint32(sampleRate*channels*2))
    binary.LittleEndian.PutUint16(header[32:34], uint16(channels*2))
    binary.LittleEndian.PutUint16(header[34:36], 16)
    copy(header[36:40], "data")
    binary.LittleEndian.PutUint32(header[40:44], 0xFFFFFFFF)
    return header
}

func (a *Broadcaster) Shutdown() {
    close(a.quit)
    if a.conn != nil {
        a.conn.Close()
    }
}
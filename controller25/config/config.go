package config

import (
    "gopkg.in/ini.v1"
    "io"
    "log"
    "os"
    "os/exec"
    "path/filepath"
    "syscall"
)

type Config struct {
    Op25RxPath string
}

func MustLoadConfig(filename string) *Config {
    cfg, err := ini.Load(filename)
    if err != nil {
        log.Fatalf("Failed to load config: %v", err)
    }
    op25rxpath := cfg.Section("").Key("op25rxpath").String()
    if op25rxpath == "" {
        log.Fatalf("op25rxpath not found in config file")
    }
    return &Config{Op25RxPath: op25rxpath}
}

func MustChdir(path string) {
    if err := os.Chdir(path); err != nil {
        log.Fatalf("Failed to change working directory: %v", err)
    }
}

func StartOp25ProcessUDP() (*exec.Cmd, io.ReadCloser, io.ReadCloser) {
    var op25Cmd *exec.Cmd
    op25_args := []string{
        "--args", "'rtl'",
        "-N", "LNA:47",
        "-S", "1400000",
        "-T", "trunk.tsv",
        "-X",
        "-V",
        "-v", "9",
        "-l", "http:0.0.0.0:8080",
        "-w",
        "-W", "127.0.0.1",
    }

    var full_command []string
    if filepath.Ext("rx.py") == ".py" {
        full_command = append([]string{"-n", "-15", "python3", "rx.py"}, op25_args...)
    } else {
        full_command = append([]string{"-n", "-15", "./rx.py"}, op25_args...)
    }

    op25Cmd = exec.Command("nice", full_command...)
    op25Cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}

    stdout, err := op25Cmd.StdoutPipe()
    if err != nil {
        log.Fatalf("Failed to get OP25 stdout pipe: %v", err)
    }
    stderr, err := op25Cmd.StderrPipe()
    if err != nil {
        log.Fatalf("Failed to get OP25 stderr pipe: %v", err)
    }

    log.Printf("Starting OP25 with command: %s %v", op25Cmd.Path, op25Cmd.Args)
    if err := op25Cmd.Start(); err != nil {
        log.Fatalf("Failed to start op25: %v", err)
    }
    log.Printf("OP25 process started with PID: %d", op25Cmd.Process.Pid)
    return op25Cmd, stdout, stderr
}
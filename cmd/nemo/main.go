package main

import (
	_ "embed"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
)

//go:embed nemo.ps1
var script string

func run() int {
	shell := os.Getenv("NEMO_PS")
	if shell == "" {
		if runtime.GOOS == "windows" {
			shell = "powershell.exe"
		} else {
			shell = "pwsh"
		}
	}

	dir, err := os.MkdirTemp("", "nemo-")
	if err != nil {
		fmt.Fprintln(os.Stderr, "nemo: cannot create temp dir:", err)
		return 1
	}
	defer os.RemoveAll(dir)

	path := filepath.Join(dir, "nemo.ps1")
	if err := os.WriteFile(path, []byte(script), 0600); err != nil {
		fmt.Fprintln(os.Stderr, "nemo: cannot write temp script:", err)
		return 1
	}

	args := []string{"-NoProfile"}
	if runtime.GOOS == "windows" {
		args = append(args, "-ExecutionPolicy", "Bypass")
	}
	args = append(args, "-File", path)
	args = append(args, os.Args[1:]...)

	cmd := exec.Command(shell, args...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			return exitErr.ExitCode()
		}
		fmt.Fprintln(os.Stderr, "nemo: cannot start", shell+":", err)
		return 1
	}
	return 0
}

func main() {
	os.Exit(run())
}

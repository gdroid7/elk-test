package main

import (
	"bufio"
	"context"
	"embed"
	"encoding/json"
	"fmt"
	"io"
	"io/fs"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/statucred/go-simulator/internal/scenarios"
)

//go:embed web
var webFS embed.FS

func main() {
	if err := os.MkdirAll("logs", 0755); err != nil {
		log.Fatalf("mkdir logs: %v", err)
	}
	if err := os.MkdirAll("bin/scenarios", 0755); err != nil {
		log.Fatalf("mkdir bin/scenarios: %v", err)
	}

	mux := http.NewServeMux()

	// --- simulator UI ---
	mux.HandleFunc("GET /", indexHandler)
	mux.HandleFunc("GET /api/scenarios", scenariosHandler)
	mux.HandleFunc("GET /api/run/{id}", runHandler)
	mux.HandleFunc("GET /api/status", statusHandler)

	// --- interactive demo endpoints ---
	mux.HandleFunc("GET /play", playHandler)
	mux.HandleFunc("GET /api/demo/myip", myIPHandler)
	mux.HandleFunc("POST /api/demo/auth", demoAuthHandler)

	addr := ":8080"
	log.Printf("Listening on %s", addr)
	if err := http.ListenAndServe(addr, mux); err != nil {
		log.Fatal(err)
	}
}

// ── existing handlers ────────────────────────────────────────────────────────

func indexHandler(w http.ResponseWriter, r *http.Request) {
	sub, err := fs.Sub(webFS, "web")
	if err != nil {
		http.Error(w, "web not found", 500)
		return
	}
	http.FileServer(http.FS(sub)).ServeHTTP(w, r)
}

func scenariosHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(scenarios.All())
}

func runHandler(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if !isValidScenarioID(id) {
		http.Error(w, "invalid scenario id", 400)
		return
	}
	meta, ok := scenarios.Get(id)
	if !ok {
		http.Error(w, "scenario not found", 404)
		return
	}

	compress := r.URL.Query().Get("compress") != "false"
	tz := r.URL.Query().Get("tz")
	if tz == "" {
		tz = "Asia/Kolkata"
	}

	logFile := filepath.Join("logs", "sim-"+id+".log")
	args := []string{"--tz=" + tz, "--log-file=" + logFile}
	if compress {
		args = append(args, "--compress-time")
	}

	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Minute)
	defer cancel()

	binPath := meta.BinPath
	if !filepath.IsAbs(binPath) {
		if exe, err := os.Executable(); err == nil {
			absPath := filepath.Join(filepath.Dir(exe), binPath)
			if _, err := os.Stat(absPath); err == nil {
				binPath = absPath
			}
		}
	}

	cmd := exec.CommandContext(ctx, binPath, args...)
	pr, pw := io.Pipe()
	defer pr.Close()
	cmd.Stdout = pw
	cmd.Stderr = pw

	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")
	w.Header().Set("Access-Control-Allow-Origin", "*")

	flusher, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, "streaming not supported", 500)
		return
	}

	if err := cmd.Start(); err != nil {
		pw.CloseWithError(err)
		fmt.Fprintf(w, "data: {\"error\":%q}\n\n", err.Error())
		flusher.Flush()
		return
	}

	go func() {
		if err := cmd.Wait(); err != nil {
			pw.CloseWithError(err)
		} else {
			pw.Close()
		}
	}()

	scanner := bufio.NewScanner(pr)
	for scanner.Scan() {
		select {
		case <-ctx.Done():
			return
		default:
		}
		line := scanner.Text()
		if strings.TrimSpace(line) == "" {
			continue
		}
		fmt.Fprintf(w, "data: %s\n\n", line)
		flusher.Flush()
	}

	if err := scanner.Err(); err != nil {
		log.Printf("scenario %s error: %v", id, err)
		fmt.Fprintf(w, "data: {\"error\":%q}\n\n", err.Error())
		flusher.Flush()
		return
	}

	fmt.Fprintf(w, "data: [DONE]\n\n")
	flusher.Flush()
}

func statusHandler(w http.ResponseWriter, r *http.Request) {
	resp := map[string]string{"status": "ok", "elk": "up"}
	if url := getNgrokURL(); url != "" {
		resp["ngrok_url"] = url
		resp["play_url"] = url + "/play"
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

// ── demo handlers ────────────────────────────────────────────────────────────

// GET /play — serves the public demo page
func playHandler(w http.ResponseWriter, r *http.Request) {
	sub, err := fs.Sub(webFS, "web")
	if err != nil {
		http.Error(w, "not found", 404)
		return
	}
	f, err := sub.Open("play.html")
	if err != nil {
		http.Error(w, "play page not found", 404)
		return
	}
	defer f.Close()
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	io.Copy(w, f)
}

// GET /api/demo/myip — returns caller IP + geo info
func myIPHandler(w http.ResponseWriter, r *http.Request) {
	ip := getRealIP(r)
	geo := getGeoInfo(ip)
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Access-Control-Allow-Origin", "*")
	json.NewEncoder(w).Encode(map[string]string{
		"ip":      ip,
		"city":    geo.City,
		"region":  geo.RegionName,
		"country": geo.Country,
	})
}

// authLogEntry mirrors the scenario binary's JSON log format.
// Fields counted against the max-8 rule (not time/level/msg):
//   brute-force: scenario, user_id, ip_address, attempt_count, error_code, city  → 6
//   valid login: scenario, user_id, ip_address, city, country                    → 5
type authLogEntry struct {
	Level        string `json:"level"`
	Msg          string `json:"msg"`
	Time         string `json:"time"`
	Scenario     string `json:"scenario"`
	UserID       string `json:"user_id"`
	IPAddress    string `json:"ip_address"`
	City         string `json:"city"`
	Country      string `json:"country,omitempty"`
	AttemptCount int    `json:"attempt_count,omitempty"`
	ErrorCode    string `json:"error_code,omitempty"`
}

// POST /api/demo/auth?name=<name>&valid=true|false
// Headers: X-User-Name (alternative to query param)
// Writes crafted log entries to logs/sim-auth-brute-force.log
func demoAuthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Content-Type", "application/json")

	name := strings.TrimSpace(r.URL.Query().Get("name"))
	if name == "" {
		name = strings.TrimSpace(r.Header.Get("X-User-Name"))
	}
	if name == "" {
		http.Error(w, `{"error":"name required: ?name=YourName or X-User-Name header"}`, 400)
		return
	}
	if !isValidName(name) {
		http.Error(w, `{"error":"name must be 1-32 alphanumeric/space/hyphen/underscore chars"}`, 400)
		return
	}

	valid := r.URL.Query().Get("valid") == "true"
	ip := getRealIP(r)
	geo := getGeoInfo(ip)

	ist, _ := time.LoadLocation("Asia/Kolkata")
	now := time.Now().In(ist)

	logFile := filepath.Join("logs", "sim-auth-brute-force.log")
	f, err := os.OpenFile(logFile, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
	if err != nil {
		http.Error(w, `{"error":"failed to open log file"}`, 500)
		return
	}
	defer f.Close()

	var entries []authLogEntry

	if valid {
		e := authLogEntry{
			Level:     "INFO",
			Msg:       "Login successful",
			Time:      now.Format(time.RFC3339),
			Scenario:  "auth-brute-force",
			UserID:    name,
			IPAddress: ip,
			City:      geo.City,
			Country:   geo.Country,
		}
		if err := writeLogEntry(f, e); err != nil {
			log.Printf("demo auth write error: %v", err)
		}
		entries = append(entries, e)
	} else {
		// 5 failed attempts (spread 5 min apart for Kibana timeline)
		for i := 1; i <= 5; i++ {
			t := now.Add(time.Duration(i-1) * 5 * time.Minute)
			e := authLogEntry{
				Level:        "WARN",
				Msg:          "Login failed",
				Time:         t.Format(time.RFC3339),
				Scenario:     "auth-brute-force",
				UserID:       name,
				IPAddress:    ip,
				AttemptCount: i,
				ErrorCode:    "INVALID_PASSWORD",
				City:         geo.City,
			}
			if err := writeLogEntry(f, e); err != nil {
				log.Printf("demo auth write error: %v", err)
			}
			entries = append(entries, e)
		}
		// account locked
		t := now.Add(5 * 5 * time.Minute)
		e := authLogEntry{
			Level:        "ERROR",
			Msg:          "Account locked",
			Time:         t.Format(time.RFC3339),
			Scenario:     "auth-brute-force",
			UserID:       name,
			IPAddress:    ip,
			AttemptCount: 5,
			ErrorCode:    "ACCOUNT_LOCKED",
			City:         geo.City,
		}
		if err := writeLogEntry(f, e); err != nil {
			log.Printf("demo auth write error: %v", err)
		}
		entries = append(entries, e)
	}

	json.NewEncoder(w).Encode(entries)
}

// ── helpers ──────────────────────────────────────────────────────────────────

func writeLogEntry(f *os.File, e authLogEntry) error {
	b, err := json.Marshal(e)
	if err != nil {
		return err
	}
	_, err = f.Write(append(b, '\n'))
	return err
}

// GeoInfo is the subset of ip-api.com fields we use.
type GeoInfo struct {
	Status     string `json:"status"`
	City       string `json:"city"`
	RegionName string `json:"regionName"`
	Country    string `json:"country"`
	Query      string `json:"query"`
}

func getGeoInfo(ip string) GeoInfo {
	if isPrivateIP(ip) {
		return GeoInfo{Status: "local", City: "localhost", RegionName: "", Country: "local", Query: ip}
	}
	client := &http.Client{Timeout: 3 * time.Second}
	resp, err := client.Get("http://ip-api.com/json/" + ip + "?fields=status,city,regionName,country,query")
	if err != nil {
		return GeoInfo{Status: "error", City: "Unknown", Country: "Unknown", Query: ip}
	}
	defer resp.Body.Close()
	var geo GeoInfo
	if err := json.NewDecoder(resp.Body).Decode(&geo); err != nil {
		return GeoInfo{Status: "error", City: "Unknown", Country: "Unknown", Query: ip}
	}
	if geo.City == "" {
		geo.City = "Unknown"
	}
	return geo
}

func getRealIP(r *http.Request) string {
	// ngrok sets X-Forwarded-For; proxies may set X-Real-IP
	if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
		return strings.TrimSpace(strings.Split(xff, ",")[0])
	}
	if xri := r.Header.Get("X-Real-IP"); xri != "" {
		return strings.TrimSpace(xri)
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

func isPrivateIP(ipStr string) bool {
	ip := net.ParseIP(ipStr)
	if ip == nil {
		return true
	}
	private := []string{
		"10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16",
		"127.0.0.0/8", "::1/128", "fc00::/7",
	}
	for _, cidr := range private {
		_, block, _ := net.ParseCIDR(cidr)
		if block != nil && block.Contains(ip) {
			return true
		}
	}
	return false
}

// getNgrokURL queries the local ngrok agent API for the active tunnel URL.
func getNgrokURL() string {
	client := &http.Client{Timeout: 500 * time.Millisecond}
	resp, err := client.Get("http://localhost:4040/api/tunnels")
	if err != nil {
		return ""
	}
	defer resp.Body.Close()
	var result struct {
		Tunnels []struct {
			PublicURL string `json:"public_url"`
			Proto     string `json:"proto"`
		} `json:"tunnels"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return ""
	}
	for _, t := range result.Tunnels {
		if t.Proto == "https" {
			return t.PublicURL
		}
	}
	if len(result.Tunnels) > 0 {
		return result.Tunnels[0].PublicURL
	}
	return ""
}

func isValidScenarioID(id string) bool {
	for _, c := range id {
		if !((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-') {
			return false
		}
	}
	return len(id) > 0 && len(id) <= 64
}

func isValidName(name string) bool {
	if len(name) == 0 || len(name) > 32 {
		return false
	}
	for _, c := range name {
		if !((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
			(c >= '0' && c <= '9') || c == '-' || c == '_' || c == ' ') {
			return false
		}
	}
	return true
}

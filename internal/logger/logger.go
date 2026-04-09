package logger

import (
	"fmt"
	"io"
	"log/slog"
	"os"
	"sync"
	"time"
)

type Config struct {
	FilePath   string
	TZ         *time.Location
	Compress   bool
	TimeWindow time.Duration
	LogCount   int
	StartTime  time.Time
}

type Logger struct {
	handler   *slog.Logger
	mu        sync.Mutex
	cfg       Config
	callCount int
	file      *os.File
}

func New(cfg Config) *Logger {
	if cfg.TZ == nil {
		cfg.TZ, _ = time.LoadLocation("Asia/Kolkata")
	}
	if cfg.TimeWindow == 0 {
		cfg.TimeWindow = 30 * time.Minute
	}
	if cfg.StartTime.IsZero() {
		cfg.StartTime = time.Now().In(cfg.TZ)
	}

	var writers []io.Writer
	writers = append(writers, os.Stdout)

	var f *os.File
	if cfg.FilePath != "" {
		var err error
		f, err = os.OpenFile(cfg.FilePath, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
		if err != nil {
			fmt.Fprintf(os.Stderr, "logger: failed to open log file %s: %v\n", cfg.FilePath, err)
		} else {
			writers = append(writers, f)
		}
	}

	w := io.MultiWriter(writers...)
	h := slog.NewJSONHandler(w, &slog.HandlerOptions{
		ReplaceAttr: func(groups []string, a slog.Attr) slog.Attr {
			if a.Key == slog.TimeKey {
				return slog.Attr{} // we inject time manually
			}
			if a.Key == slog.LevelKey {
				return slog.Attr{Key: "level", Value: slog.StringValue(a.Value.String())}
			}
			return a
		},
	})

	return &Logger{
		handler: slog.New(h),
		cfg:     cfg,
		file:    f,
	}
}

func (l *Logger) timestamp() time.Time {
	if !l.cfg.Compress || l.cfg.LogCount == 0 {
		return time.Now().In(l.cfg.TZ)
	}
	step := l.cfg.TimeWindow / time.Duration(l.cfg.LogCount)
	t := l.cfg.StartTime.Add(time.Duration(l.callCount) * step)
	l.callCount++
	return t
}

func (l *Logger) log(level slog.Level, msg string, args ...any) {
	l.mu.Lock()
	defer l.mu.Unlock()
	ts := l.timestamp()
	allArgs := append([]any{"time", ts.Format(time.RFC3339)}, args...)
	l.handler.Log(nil, level, msg, allArgs...)
}

func (l *Logger) Info(msg string, args ...any)  { l.log(slog.LevelInfo, msg, args...) }
func (l *Logger) Warn(msg string, args ...any)  { l.log(slog.LevelWarn, msg, args...) }
func (l *Logger) Error(msg string, args ...any) { l.log(slog.LevelError, msg, args...) }

func (l *Logger) Close() {
	if l.file != nil {
		l.file.Close()
	}
}

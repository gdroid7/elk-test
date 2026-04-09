package scenarios

import "sort"

type Meta struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Description string `json:"description"`
	DurationSec int    `json:"duration_sec"`
	LogCount    int    `json:"log_count"`
	Index       string `json:"index"`
	BinPath     string `json:"bin_path"`
}

// registry is written only from init() functions (before ListenAndServe).
// Reads from concurrent HTTP handlers are safe without locking.
var registry = map[string]Meta{}

func Register(m Meta) {
	registry[m.ID] = m
}

func Get(id string) (Meta, bool) {
	m, ok := registry[id]
	return m, ok
}

func All() []Meta {
	all := make([]Meta, 0, len(registry))
	for _, m := range registry {
		all = append(all, m)
	}
	sort.Slice(all, func(i, j int) bool {
		return all[i].ID < all[j].ID
	})
	return all
}

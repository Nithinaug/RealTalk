// Load test for the RealTalk WebSocket server.
//
// It opens many clients, puts them into rooms, makes every client send a
// message at a fixed interval, and measures how many messages arrive and how
// long they take. Every message is echoed to everyone in the room, including
// the sender, so each message is timed by the clients that receive it.
//
// Run from the server folder, with the server already running:
//
//	go run ./loadtest -url ws://localhost:8080/ws -rooms 10 -users 20 -duration 30s
//
// Latency is only meaningful when the server and this test run on the same
// machine, because the send time is read from the same clock.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"math"
	"math/rand/v2"
	"os"
	"slices"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/gorilla/websocket"
)

type wsMsg struct {
	Id   string `json:"id,omitempty"`
	Type string `json:"type"`
	User string `json:"user,omitempty"`
	Text string `json:"text,omitempty"`
	Room string `json:"room,omitempty"`
}

type client struct {
	room    string
	user    string
	conn    *websocket.Conn
	sent    int
	seq     int
	lat     []int64 // nanoseconds, one entry per message received
	dropped bool
}

func (c *client) send(size int) error {
	c.seq++
	text := strconv.FormatInt(time.Now().UnixNano(), 10) + ":" + strings.Repeat("x", size)
	err := c.conn.WriteJSON(wsMsg{
		Id:   fmt.Sprintf("%s-%d", c.user, c.seq),
		Type: "message",
		User: c.user,
		Text: text,
		Room: c.room,
	})
	if err == nil {
		c.sent++
	}
	return err
}

func (c *client) sendLoop(interval time.Duration, size int, done <-chan struct{}, wg *sync.WaitGroup) {
	defer wg.Done()
	// Random start so every user does not send at the same instant.
	select {
	case <-time.After(time.Duration(rand.Int64N(int64(interval)))):
	case <-done:
		return
	}
	t := time.NewTicker(interval)
	defer t.Stop()
	for {
		if err := c.send(size); err != nil {
			c.dropped = true
			return
		}
		select {
		case <-t.C:
		case <-done:
			return
		}
	}
}

func (c *client) readLoop(closing *atomic.Bool, wg *sync.WaitGroup) {
	defer wg.Done()
	for {
		_, data, err := c.conn.ReadMessage()
		if err != nil {
			if !closing.Load() {
				c.dropped = true
			}
			return
		}
		var m wsMsg
		if json.Unmarshal(data, &m) != nil || m.Type != "message" {
			continue
		}
		ts, _, ok := strings.Cut(m.Text, ":")
		if !ok {
			continue
		}
		sentAt, err := strconv.ParseInt(ts, 10, 64)
		if err != nil {
			continue
		}
		c.lat = append(c.lat, time.Now().UnixNano()-sentAt)
	}
}

func percentile(sorted []int64, p float64) float64 {
	i := int(math.Ceil(p/100*float64(len(sorted)))) - 1
	i = max(0, min(i, len(sorted)-1))
	return float64(sorted[i]) / 1e6
}

func main() {
	url := flag.String("url", "ws://localhost:8080/ws", "WebSocket URL of the server")
	rooms := flag.Int("rooms", 10, "number of rooms")
	users := flag.Int("users", 20, "users per room")
	interval := flag.Duration("interval", time.Second, "time between messages from each user")
	duration := flag.Duration("duration", 30*time.Second, "how long users keep sending")
	ramp := flag.Duration("ramp", 5*time.Millisecond, "pause between opening connections")
	size := flag.Int("size", 0, "extra bytes added to every message")
	drain := flag.Duration("drain", 3*time.Second, "wait for in-flight messages after sending stops")
	flag.Parse()

	if *rooms < 1 || *users < 1 || *interval <= 0 || *duration <= 0 {
		fmt.Fprintln(os.Stderr, "rooms, users, interval and duration must be positive")
		os.Exit(2)
	}

	total := *rooms * *users
	clients := make([]*client, 0, total)
	for r := 0; r < *rooms; r++ {
		for u := 0; u < *users; u++ {
			clients = append(clients, &client{
				room: fmt.Sprintf("loadtest-%d", r),
				user: fmt.Sprintf("user-%d-%d", r, u),
			})
		}
	}

	var (
		closing   atomic.Bool
		readers   sync.WaitGroup
		senders   sync.WaitGroup
		failed    int
		hintShown bool
	)
	dialer := websocket.Dialer{HandshakeTimeout: 10 * time.Second}

	fmt.Printf("connecting %d clients (%d rooms x %d users)...\n", total, *rooms, *users)
	connected := make([]*client, 0, total)
	for _, c := range clients {
		conn, _, err := dialer.Dial(*url, nil)
		if err != nil {
			failed++
			if !hintShown && strings.Contains(err.Error(), "too many open files") {
				hintShown = true
				fmt.Fprintln(os.Stderr, "hint: raise the file limit with 'ulimit -n 20000' in the shell that runs the server and this test")
			}
			continue
		}
		c.conn = conn
		if err := conn.WriteJSON(wsMsg{Type: "join", User: c.user, Room: c.room}); err != nil {
			conn.Close()
			failed++
			continue
		}
		readers.Add(1)
		go c.readLoop(&closing, &readers)
		connected = append(connected, c)
		time.Sleep(*ramp)
	}
	if len(connected) == 0 {
		fmt.Fprintln(os.Stderr, "no connections succeeded, is the server running?")
		os.Exit(1)
	}

	members := map[string]int{}
	for _, c := range connected {
		members[c.room]++
	}

	time.Sleep(time.Second) // let the last joins finish
	fmt.Printf("%d connected, sending for %s...\n", len(connected), *duration)

	done := make(chan struct{})
	for _, c := range connected {
		senders.Add(1)
		go c.sendLoop(*interval, *size, done, &senders)
	}
	time.Sleep(*duration)
	close(done)
	senders.Wait()
	time.Sleep(*drain)

	closing.Store(true)
	for _, c := range connected {
		c.conn.Close()
	}
	readers.Wait()

	var sent, expected, dropped int
	sentByRoom := map[string]int{}
	var all []int64
	for _, c := range connected {
		sent += c.sent
		sentByRoom[c.room] += c.sent
		if c.dropped {
			dropped++
		}
		all = append(all, c.lat...)
	}
	for room, n := range sentByRoom {
		expected += n * members[room]
	}
	delivered := len(all)
	secs := duration.Seconds()

	fmt.Println()
	fmt.Println("Results")
	fmt.Printf("  clients:             %d connected, %d failed, %d dropped during the test\n", len(connected), failed, dropped)
	fmt.Printf("  messages sent:       %d (%.0f per second)\n", sent, float64(sent)/secs)
	if expected > 0 {
		fmt.Printf("  messages delivered:  %d of %d expected (%.2f%%), %.0f per second\n",
			delivered, expected, 100*float64(delivered)/float64(expected), float64(delivered)/secs)
	}
	if delivered == 0 {
		fmt.Println("  latency:             no messages received")
		return
	}
	slices.Sort(all)
	fmt.Printf("  latency (ms):        p50 %.2f   p95 %.2f   p99 %.2f   max %.2f\n",
		percentile(all, 50), percentile(all, 95), percentile(all, 99), float64(all[len(all)-1])/1e6)
}

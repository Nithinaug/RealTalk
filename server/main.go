package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		return true
	},
}

type Message struct {
	Type  string   `json:"type"`
	User  string   `json:"user,omitempty"`
	Text  string   `json:"text,omitempty"`
	Users []string `json:"users,omitempty"`
}

type Client struct {
	Conn *websocket.Conn
	User string
}

var (
	clients   = make(map[*Client]bool)
	clientsMu sync.Mutex
)

func handleConnections(c *gin.Context) {
	ws, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		log.Println(err)
		return
	}
	defer ws.Close()

	client := &Client{Conn: ws}
	clientsMu.Lock()
	clients[client] = true
	clientsMu.Unlock()

	defer func() {
		clientsMu.Lock()
		delete(clients, client)
		clientsMu.Unlock()
		ws.Close()
		broadcastUserList()
	}()

	for {
		var msg Message
		err := ws.ReadJSON(&msg)
		if err != nil {
			break
		}

		switch msg.Type {
		case "join":
			client.User = msg.User
			broadcastUserList()
		case "message":
			broadcastMessage(msg)
		}
	}
}

func broadcastUserList() {
	clientsMu.Lock()
	defer clientsMu.Unlock()

	uniqueUsers := make(map[string]bool)
	for client := range clients {
		if client.User != "" {
			uniqueUsers[client.User] = true
		}
	}

	var userList []string
	for user := range uniqueUsers {
		userList = append(userList, user)
	}

	msg := Message{
		Type:  "users",
		Users: userList,
	}

	for client := range clients {
		err := client.Conn.WriteJSON(msg)
		if err != nil {
			client.Conn.Close()
			delete(clients, client)
		}
	}
}

func broadcastMessage(msg Message) {
	clientsMu.Lock()
	defer clientsMu.Unlock()

	for client := range clients {
		err := client.Conn.WriteJSON(msg)
		if err != nil {
			client.Conn.Close()
			delete(clients, client)
		}
	}
}

func findPath(target string) string {
	if _, err := os.Stat(target); err == nil {
		return target
	}
	if _, err := os.Stat(filepath.Join("..", target)); err == nil {
		return filepath.Join("..", target)
	}
	return target
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	gin.SetMode(gin.ReleaseMode)
	r := gin.Default()

	webDir := findPath("web")
	indexFile := filepath.Join(webDir, "index.html")

	r.GET("/health", func(c *gin.Context) {
		c.String(http.StatusOK, "OK")
	})

	r.GET("/ws", func(c *gin.Context) {
		handleConnections(c)
	})

	r.Static("/static", webDir)

	r.NoRoute(func(c *gin.Context) {
		c.File(indexFile)
	})

	// Start self-pinging keep-alive if APP_URL is provided
	if appURL := os.Getenv("APP_URL"); appURL != "" {
		go startKeepAlive(appURL)
	}

	log.Printf("Server started on :%s", port)
	err := r.Run(":" + port)
	if err != nil {
		log.Fatal(err)
	}
}

func startKeepAlive(appURL string) {
	ticker := time.NewTicker(14 * time.Minute)
	log.Printf("Keep-alive active: Pinging %s every 14 minutes", appURL)

	for {
		select {
		case <-ticker.C:
			resp, err := http.Get(fmt.Sprintf("%s/health", appURL))
			if err != nil {
				log.Printf("Keep-alive heartbeat failed: %v", err)
			} else {
				log.Printf("Keep-alive heartbeat: %s", resp.Status)
				resp.Body.Close()
			}
		}
	}
}

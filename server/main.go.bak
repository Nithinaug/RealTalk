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
	abs, err := filepath.Abs(".")
	if err != nil {
		return target
	}

	path := filepath.Join(abs, target)
	if _, err := os.Stat(path); err == nil {
		return path
	}

	path = filepath.Join(abs, "..", target)
	if _, err := os.Stat(path); err == nil {
		return path
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
	absWebDir, _ := filepath.Abs(webDir)
	indexFile := filepath.Join(absWebDir, "index.html")

	r.GET("/health", func(c *gin.Context) {
		c.String(http.StatusOK, "OK")
	})

	r.GET("/ws", func(c *gin.Context) {
		handleConnections(c)
	})

	r.GET("/static/*filepath", func(c *gin.Context) {
		file := c.Param("filepath")

		if file == "/config.js" || file == "config.js" {
			url := os.Getenv("SUPABASE_URL")
			key := os.Getenv("SUPABASE_ANON_KEY")

			if url == "" || key == "" {
				c.Header("Content-Type", "application/javascript")
				c.String(500, "console.error('SERVER ERROR: Supabase environment variables are missing!');")
				return
			}

			configContent := fmt.Sprintf(`const CONFIG = {
    SUPABASE_URL: '%s',
    SUPABASE_ANON_KEY: '%s'
};`, url, key)

			c.Header("Content-Type", "application/javascript")
			c.String(http.StatusOK, configContent)
			return
		}

		fullPath := filepath.Join(absWebDir, file)
		c.File(fullPath)
	})

	r.NoRoute(func(c *gin.Context) {
		c.File(indexFile)
	})

	r.GET("/debug/web", func(c *gin.Context) {
		files, _ := os.ReadDir(absWebDir)
		var list []string
		for _, f := range files {
			list = append(list, f.Name())
		}
		currDir, _ := filepath.Abs(".")
		c.JSON(200, gin.H{
			"webDir": absWebDir,
			"files":  list,
			"cwd":    currDir,
		})
	})

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

	for {
		select {
		case <-ticker.C:
			resp, err := http.Get(fmt.Sprintf("%s/health", appURL))
			if err == nil {
				resp.Body.Close()
			}
		}
	}
}

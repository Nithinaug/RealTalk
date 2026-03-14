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
	Room  string   `json:"room,omitempty"`
	Users []string `json:"users,omitempty"`
}

type Client struct {
	Conn *websocket.Conn
	User string
	Room string
}

var (
	rooms   = make(map[string]map[*Client]bool)
	roomsMu sync.Mutex
)

func handleConnections(c *gin.Context) {
	ws, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		log.Println(err)
		return
	}
	defer ws.Close()

	client := &Client{Conn: ws}

	defer func() {
		roomsMu.Lock()
		if client.Room != "" {
			if roomClients, ok := rooms[client.Room]; ok {
				delete(roomClients, client)
				if len(roomClients) == 0 {
					delete(rooms, client.Room)
				}
			}
		}
		roomsMu.Unlock()
		ws.Close()

		if client.Room != "" {
			broadcastUserList(client.Room)
		}
	}()

	for {
		var msg Message
		err := ws.ReadJSON(&msg)
		if err != nil {
			break
		}

		switch msg.Type {
		case "join":
			roomsMu.Lock()
			// If client was in another room, remove them first
			if client.Room != "" && client.Room != msg.Room {
				if oldRoomClients, ok := rooms[client.Room]; ok {
					delete(oldRoomClients, client)
					if len(oldRoomClients) == 0 {
						delete(rooms, client.Room)
					}
					// Unlock briefly to broadcast to old room, then re-lock for new room
					roomsMu.Unlock()
					broadcastUserList(client.Room)
					roomsMu.Lock()
				}
			}

			client.User = msg.User
			client.Room = msg.Room
			log.Printf("User %s joined room %s", client.User, client.Room)

			if rooms[client.Room] == nil {
				rooms[client.Room] = make(map[*Client]bool)
			}
			rooms[client.Room][client] = true
			roomsMu.Unlock()

			broadcastUserList(client.Room)

		case "leave":
			roomsMu.Lock()
			if roomClients, ok := rooms[msg.Room]; ok {
				delete(roomClients, client)
				if len(roomClients) == 0 {
					delete(rooms, msg.Room)
				}
			}
			roomsMu.Unlock()

			client.Room = ""
			broadcastUserList(msg.Room)

		case "message":
			if msg.Room == "" {
				msg.Room = client.Room
			}
			broadcastMessage(msg)
		}
	}
}

func broadcastUserList(roomID string) {
	if roomID == "" {
		return
	}

	roomsMu.Lock()
	roomClients := rooms[roomID]

	uniqueUsers := make(map[string]bool)
	for client := range roomClients {
		if client.User != "" {
			uniqueUsers[client.User] = true
		}
	}
	roomsMu.Unlock()

	var userList []string
	for user := range uniqueUsers {
		userList = append(userList, user)
	}
	log.Printf("Broadcasting users for room %s: %v", roomID, userList)

	msg := Message{
		Type:  "users",
		Users: userList,
		Room:  roomID,
	}

	roomsMu.Lock()
	defer roomsMu.Unlock()
	for client := range rooms[roomID] {
		err := client.Conn.WriteJSON(msg)
		if err != nil {
			client.Conn.Close()
			delete(rooms[roomID], client)
		}
	}
}

func broadcastMessage(msg Message) {
	if msg.Room == "" {
		return
	}

	roomsMu.Lock()
	defer roomsMu.Unlock()

	roomClients := rooms[msg.Room]
	for client := range roomClients {
		err := client.Conn.WriteJSON(msg)
		if err != nil {
			client.Conn.Close()
			delete(roomClients, client)
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

	for range ticker.C {
		resp, err := http.Get(fmt.Sprintf("%s/health", appURL))
		if err == nil {
			resp.Body.Close()
		}
	}
}

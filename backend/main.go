package main

import (
	"log"
	"net/http"
	"sync"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
)

type Message struct {
	Type  string   `json:"type"`
	User  string   `json:"user"`
	Text  string   `json:"text"`
	Users []string `json:"users"`
}

type Client struct {
	conn *websocket.Conn
	user string
}

var (
	clients  = make(map[*Client]bool)
	mu       sync.Mutex
	upgrader = websocket.Upgrader{
		CheckOrigin: func(r *http.Request) bool { return true },
	}
)

func main() {
	r := gin.Default()

	r.GET("/ws", wsHandler)
	r.GET("/", func(c *gin.Context) {
		c.File("../frontend/index.html")
	})
	r.Static("/static", "../frontend")

	log.Println("Running on :8080")
	r.Run(":8080")
}

func wsHandler(c *gin.Context) {
	ws, _ := upgrader.Upgrade(c.Writer, c.Request, nil)
	client := &Client{conn: ws}

	mu.Lock()
	clients[client] = true
	mu.Unlock()

	defer func() {
		mu.Lock()
		delete(clients, client)
		mu.Unlock()
		sendUsers()
		ws.Close()
	}()

	for {
		var msg Message
		if ws.ReadJSON(&msg) != nil {
			break
		}

		switch msg.Type {

		case "join":
			client.user = msg.User
			sendUsers()

		case "message":
			broadcast(msg)

		case "typing":
			broadcast(msg)
		}
	}
}

func broadcast(msg Message) {
	mu.Lock()
	defer mu.Unlock()

	for c := range clients {
		c.conn.WriteJSON(msg)
	}
}

func sendUsers() {
	var list []string

	mu.Lock()
	for c := range clients {
		if c.user != "" {
			list = append(list, c.user)
		}
	}
	mu.Unlock()

	broadcast(Message{
		Type:  "users",
		Users: list,
	})
}

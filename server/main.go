package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
	"sync"

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

func handleConnections(w http.ResponseWriter, r *http.Request) {
	ws, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Println(err)
		return
	}

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

	var userList []string
	for client := range clients {
		if client.User != "" {
			userList = append(userList, client.User)
		}
	}

	msg := Message{
		Type:  "users",
		Users: userList,
	}

	for client := range clients {
		err := client.Conn.WriteJSON(msg)
		if err != nil {
			log.Printf("error: %v", err)
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
			log.Printf("error: %v", err)
			client.Conn.Close()
			delete(clients, client)
		}
	}
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	http.HandleFunc("/ws", handleConnections)

	fs := http.FileServer(http.Dir("./web"))
	http.Handle("/static/", http.StripPrefix("/static/", fs))
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		http.ServeFile(w, r, "./web/index.html")
	})

	fmt.Printf("Server started on :%s\n", port)
	err := http.ListenAndServe(":"+port, nil)
	if err != nil {
		log.Fatal("ListenAndServe: ", err)
	}
}

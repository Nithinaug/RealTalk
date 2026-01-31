# 💬 Go WebSocket Chat App

A simple real-time chat application built with Go (Gin + Gorilla WebSocket) and a lightweight HTML/CSS/JavaScript frontend.

This project demonstrates real-time communication using WebSockets and a clean chat UI.

---

## 🚀 Features

- Real-time messaging with WebSockets  
- Multiple users chatting simultaneously  
- Live online users list  
- Username-based join system  
- Clean WhatsApp-style UI  
- Green (your) vs White (others) message bubbles  
- Full-page layout  
- Lightweight and fast  

---

## 🛠 Tech Stack

Backend
- Go  
- Gin Web Framework  
- Gorilla WebSocket  

Frontend
- HTML  
- CSS  
- Vanilla JavaScript  

---

## 📁 Project Structure

```
project-root/
│
├── backend/
│   └── main.go
│
├── frontend/
│   ├── index.html
│   ├── app.js
│   └── style.css
│
└── README.md
```

---

## ⚙️ How It Works

1. User enters a username  
2. Browser opens a WebSocket connection to the Go server  
3. Messages are broadcast to all connected users  
4. Online users list updates automatically  
5. Chat updates instantly without page refresh

---

## 💡 Usage

- Enter a username  
- Click Join  
- Start chatting in real time  
- Open multiple tabs or devices to chat with others  

---

## ⚠️ Limitation

- Messages are **live only**  
- No chat history is stored  
- Refreshing the page clears previous messages  
- Only currently connected users can see messages  

This keeps the app simple and focused on real-time communication.

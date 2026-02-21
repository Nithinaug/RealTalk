# 🗨️ RealTalk: Multi-Platform Real-Time Chat

RealTalk is a high-performance, real-time chat application with a hybrid architecture. It features a persistent chat history powered by **Supabase** and a live presence system built with **Go and WebSockets**.

The project includes both a sleek **Web frontend** and a modern **Flutter mobile application**.

---

## 🚀 Key Features

- **Persistent Messaging**: Chat history is saved securely in Supabase.
- **Real-Time Presence**: Live "Online Users" list powered by a Go WebSocket server.
- **Multi-Platform**: Fully featured web app and mobile app (Flutter).
- **Secure Authentication**: Username/Password login and signup via Supabase Auth.
- **Premium UI**: WhatsApp-inspired design with smooth animations and responsive layouts.

---

## 🛠 Tech Stack

### Backend & Infrastructure
- **Go (Golang)**: Presence coordinator and WebSocket server.
- **Supabase**: 
  - **Database**: PostgreSQL for message storage.
  - **Auth**: User management and session persistence.
  - **Realtime**: Database change listeners for instant message updates.

### Frontend
- **Web**: Vanilla JavaScript, HTML5, CSS3.
- **Mobile**: Flutter/Dart (Android & iOS).

---

## 📁 Project Structure

```text
Real-Time-Chatroom/
├── app/            # Flutter Mobile Application
├── server/         # Go WebSocket Server (Presence)
├── web/            # Web Frontend (Vanilla JS)
└── README.md       # Project Documentation
```

---

## ⚙️ How It Works

1.  **Authentication**: Users sign up/log in using Supabase. The app mocks an email internally (`username@example.com`) to keep the experience focused on usernames.
2.  **Messaging**: When a message is sent, it is inserted directly into the Supabase `messages` table. All connected clients listen for `INSERT` events to show the message instantly.
3.  **Presence**: As soon as a user logs in, they connect to the tiny **Go WebSocket server**. This server maintains a list of active connections and broadcasts the list of "Online Users" to everyone.

---

## 🚀 Getting Started

### 1. Backend (Go)
```bash
cd server
go run main.go
```
*The server starts on port 8080 by default.*

### 2. Web Frontend
Simply open `web/index.html` in your browser or serve it using any static file server.

### 3. Mobile App (Flutter)
```bash
cd app
flutter pub get
flutter run
```

---

## 📝 Configuration
- **Supabase**: You will need your own `SUPABASE_URL` and `SUPABASE_ANON_KEY`. 
  - Update them in `web/app.js` for the web.
  - Update them in `app/lib/main.dart` for the mobile app.

---

## ⚠️ Requirements
- Go 1.18+
- Flutter SDK
- Supabase Project (Tables: `messages`)

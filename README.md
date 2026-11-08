# RealTalk

RealTalk is a production-grade, high-performance real-time messaging platform designed for cross-platform communication. Built with a robust Go backend and featuring dedicated Web and Flutter clients, it prioritizes performance, scalability, and exceptional user experience.

[![RealTalk demo video](https://img.youtube.com/vi/QC4QKiZmXq4/maxresdefault.jpg)](https://youtu.be/QC4QKiZmXq4)

▶️ **[Watch the 50-second demo](https://youtu.be/QC4QKiZmXq4)**

---

## 🚀 Features

- **Real-Time Synchronicity**: Lightning-fast message delivery powered by optimized WebSockets.
- **Cross-Platform Access**: Seamless communication across native Mobile (Flutter) and Web (HTML5/Vanilla JS) environments.
- **Live Typing Indicators**: Real-time "user is typing" UI synced instantly across both mobile and web clients.
- **Secure Authentication**: Robust user registration and login flows powered entirely by Supabase GoTrue.
- **Dynamic Room Management**: Create rooms, join via unique IDs, view live online user counts, and seamlessly manage your personal room list.
- **Message Persistence & Control**: Full message history synchronization with "Delete for Me" and "Delete for Everyone" functionality.
- **Premium Aesthetics**: Modern, responsive UI featuring glassmorphism elements, vibrant gradients, and smooth micro-animations.

## 🏗️ Technology Stack

- **Backend**: Go (Gin Gonic, Gorilla WebSockets)
- **Web Frontend**: Vanilla JavaScript, Semantic HTML5, CSS3 Custom Properties
- **Mobile App**: Flutter / Dart
- **Database/Auth**: Supabase (PostgreSQL & GoTrue)
- **Configuration**: Environment-driven via native platform secret management.

## 🛠️ Getting Started

### Prerequisites

- [Go](https://go.dev/) 1.25+
- [Flutter SDK](https://docs.flutter.dev/get-started/install)
- A Supabase Project

### Database Setup

1. In your Supabase project, open **SQL Editor**, paste [`supabase_setup.sql`](supabase_setup.sql) and run it. It creates the tables, row level security policies and Realtime settings. It is safe to run again.
2. Go to **Authentication → Sign In / Providers → Email** and turn off **Confirm email**. Users sign up with a username only, so there is no inbox to confirm.
3. Copy the **Project URL** and **anon key** from **Project Settings → API**.

### Environment Variables

| Where | Variable | Purpose |
|---|---|---|
| Server (shell env) | `SUPABASE_URL`, `SUPABASE_ANON_KEY` | Passed to the web client via `/static/config.js` |
| Server (shell env) | `PORT` | Defaults to `8080` |
| Server (shell env) | `ALLOWED_ORIGINS` | Comma-separated WebSocket origins. If empty, any origin is accepted |
| `app/.env` | `SUPABASE_URL`, `SUPABASE_ANON_KEY` | Supabase for the Flutter app |
| `app/.env` | `APP_URL` | Your server URL, e.g. `http://192.168.1.10:8080` |

### Running Locally

**Backend + Web:**
```bash
cd server
SUPABASE_URL=... SUPABASE_ANON_KEY=... go run .
```
Then open http://localhost:8080. The Go server serves the web client.

**Mobile:**
```bash
cd app
flutter run
```

---

# RealTalk

RealTalk is a production-grade, high-performance real-time messaging platform designed for cross-platform communication. Built with a robust Go backend and featuring dedicated Web and Flutter clients, it prioritizes performance, scalability, and exceptional user experience.

---

## 🚀 Features

- **Real-Time Synchronicity**: Sub-millisecond message delivery powered by optimized WebSockets.
- **Cross-Platform Access**: Seamless communication across native Mobile (Flutter) and Web (HTML5/Vanilla JS) environments.
- **JWT Authentication**: Secure token-based access control integrated across all clients.
- **Dynamic Room Management**: Create persistent or ephemeral rooms, join via unique IDs, and manage memberships with integrated "Exit Room" functionality.
- **Message Persistence**: Full message history synchronization via Supabase integration.
- **Premium Aesthetics**: Modern, responsive UI featuring glassmorphism elements, vibrant gradients, and smooth micro-animations.

## 🏗️ Technology Stack

- **Backend**: Go (Gin Gonic, Gorilla WebSockets, JWT-Go)
- **Web Frontend**: Vanilla JavaScript, Semantic HTML5, CSS3 Custom Properties
- **Mobile App**: Flutter / Dart
- **Database/Auth**: Supabase (PostgreSQL & GoTrue)
- **Configuration**: Environment-driven via native platform secret management.

## 🛠️ Getting Started

### Prerequisites

- [Go](https://go.dev/) 1.25+
- [Flutter SDK](https://docs.flutter.dev/get-started/install)
- A Supabase Project

### Running Locally

**Backend:**
```bash
cd server
go run main.go
```

**Mobile:**
```bash
cd app
flutter run
```

**Web:**
Simply serve the `web/` directory using any static file server or open `index.html`.

---

*Built for high-concurrency real-time communication.*

# RealTalk

RealTalk is a production-grade, high-performance real-time messaging platform designed for cross-platform communication. Built with a robust Go backend and featuring dedicated Web and Flutter clients, it prioritizes security, scalability, and exceptional user experience.

---

## 🚀 Features

- **Real-Time Synchronicity**: Sub-millisecond message delivery powered by optimized WebSockets.
- **Cross-Platform Access**: Seamless communication across native Mobile (Flutter) and Web (HTML5/Vanilla JS) environments.
- **Dynamic Room Management**: Create persistent or ephemeral rooms, join via unique IDs, and manage memberships with integrated "Exit Room" functionality.
- **Message Persistence**: Full message history synchronization via Supabase integration.
- **Premium Aesthetics**: Modern, responsive UI featuring glassmorphism elements, vibrant gradients, and smooth micro-animations.

## 🛡️ Security Architecture

RealTalk is built with a security-first mindset, following industry best practices to ensure production-grade safety:

- **JWT Authentication**: Secure token-based authentication compatible with Supabase (supporting both legacy HS256 and modern ES256/ECC signing).
- **IP-Based Rate Limiting**: Intelligent backend protection against brute-force attacks and API abuse using token-bucket algorithms.
- **Strict CORS Policy**: Hardened Cross-Origin Resource Sharing configuration decoupled from the codebase via environment variables.
- **WebSocket Hardening**: Authenticated handshakes utilizing subprotocols to ensure only authorized clients can establish real-time streams.

## 🏗️ Technology Stack

- **Backend**: Go (Gin Gonic, Gorilla WebSockets, JWT-Go)
- **Web Frontend**: Vanilla JavaScript, Semantic HTML5, CSS3 Custom Properties
- **Mobile App**: Flutter / Dart
- **Database/Auth**: Supabase (PostgreSQL & GoTrue)
- **Configuration**: Environment-driven via `godotenv` and native platform secret management.

## 🛠️ Getting Started

### Prerequisites

- [Go](https://go.dev/) 1.25+
- [Flutter SDK](https://docs.flutter.dev/get-started/install)
- A Supabase Project

### Environment Setup

1. Copy the template: `cp .env.example .env`
2. Configure your specific environment variables:
   - `JWT_SECRET`: Your Supabase JWT Public Key (JSON or PEM format).
   - `ALLOWED_ORIGINS`: Comma-separated list of trusted frontend origins.
   - `SUPABASE_URL` & `SUPABASE_ANON_KEY`: Found in your Supabase API settings.

### Running Globally

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

## 🚢 Deployment

The repository is pre-configured for deployment on platforms like **Render** or **Vercel**. 

- **Frontend**: Deploy the `web` folder.
- **Backend**: Deploy the `server` folder using the Go runtime.
- **Variables**: Ensure all keys listed in `.env.example` are configured in your deployment dashboard's Environment settings.

---

*Built with precision for high-concurrency real-time communication.*

package main

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"math/big"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/time/rate"
)

func CORSMiddleware() gin.HandlerFunc {
	allowedOrigins := os.Getenv("ALLOWED_ORIGINS")
	if allowedOrigins == "" {
		allowedOrigins = "http://localhost:8080,http://localhost:3000,https://realtalk-f233.onrender.com"
	}

	config := cors.DefaultConfig()
	config.AllowOrigins = strings.Split(allowedOrigins, ",")
	config.AllowMethods = []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"}
	config.AllowHeaders = []string{"Origin", "Content-Type", "Accept", "Authorization"}
	config.AllowCredentials = true
	config.MaxAge = 12 * time.Hour

	return cors.New(config)
}

type IPRateLimiter struct {
	ips map[string]*rate.Limiter
	mu  sync.Mutex
	tps float64
	b   int
}

func NewIPRateLimiter(r float64, b int) *IPRateLimiter {
	return &IPRateLimiter{
		ips: make(map[string]*rate.Limiter),
		tps: r,
		b:   b,
	}
}

func (i *IPRateLimiter) GetLimiter(ip string) *rate.Limiter {
	i.mu.Lock()
	defer i.mu.Unlock()

	limiter, exists := i.ips[ip]
	if !exists {
		limiter = rate.NewLimiter(rate.Limit(i.tps), i.b)
		i.ips[ip] = limiter
	}

	return limiter
}

func RateLimitMiddleware() gin.HandlerFunc {
	tpsStr := os.Getenv("RATE_LIMIT_TPS")
	burstStr := os.Getenv("RATE_LIMIT_BURST")

	var tps float64 = 1.67
	var burst int = 50

	if tpsStr != "" {
		fmt.Sscanf(tpsStr, "%f", &tps)
	}
	if burstStr != "" {
		fmt.Sscanf(burstStr, "%d", &burst)
	}

	limiter := NewIPRateLimiter(tps, burst)

	return func(c *gin.Context) {
		if strings.HasPrefix(c.Request.URL.Path, "/ws") {
			c.Next()
			return
		}
		clientIP := c.ClientIP()
		l := limiter.GetLimiter(clientIP)

		if !l.Allow() {
			c.Header("X-RateLimit-Limit", fmt.Sprintf("%.2f", tps))
			c.Header("X-RateLimit-Remaining", "0")
			c.Header("X-RateLimit-Reset", "1")
			c.AbortWithStatusJSON(http.StatusTooManyRequests, gin.H{
				"error": "Too many requests. Please slow down.",
			})
			return
		}

		c.Next()
	}
}

func AuthMiddleware() gin.HandlerFunc {
	jwtSecret := os.Getenv("JWT_SECRET")

	return func(c *gin.Context) {
		authHeader := c.GetHeader("Authorization")
		if authHeader == "" {
			if c.GetHeader("Upgrade") == "websocket" {
				authHeader = c.GetHeader("Sec-WebSocket-Protocol")
			}
		}

		if authHeader == "" {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "Authorization header required"})
			return
		}

		tokenString := strings.TrimPrefix(authHeader, "Bearer ")
		tokenString = strings.TrimSpace(tokenString)

		if jwtSecret == "" {
			c.AbortWithStatusJSON(http.StatusInternalServerError, gin.H{"error": "JWT_SECRET not configured on server"})
			return
		}

		token, err := jwt.Parse(tokenString, func(token *jwt.Token) (interface{}, error) {
			if _, ok := token.Method.(*jwt.SigningMethodHMAC); ok {
				return []byte(jwtSecret), nil
			}
			if _, ok := token.Method.(*jwt.SigningMethodECDSA); ok {
				if strings.HasPrefix(strings.TrimSpace(jwtSecret), "{") {
					var jwk struct {
						X string `json:"x"`
						Y string `json:"y"`
					}
					if err := json.Unmarshal([]byte(jwtSecret), &jwk); err == nil {
						xBytes, _ := base64.RawURLEncoding.DecodeString(jwk.X)
						yBytes, _ := base64.RawURLEncoding.DecodeString(jwk.Y)
						return &ecdsa.PublicKey{
							Curve: elliptic.P256(),
							X:     new(big.Int).SetBytes(xBytes),
							Y:     new(big.Int).SetBytes(yBytes),
						}, nil
					}
				}
				pubKey, err := jwt.ParseECPublicKeyFromPEM([]byte(jwtSecret))
				if err != nil {
					return nil, fmt.Errorf("failed to parse ECC public key: %v", err)
				}
				return pubKey, nil
			}
			return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
		})

		if err != nil || !token.Valid {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "Invalid or expired token"})
			return
		}

		if claims, ok := token.Claims.(jwt.MapClaims); ok {
			c.Set("user_id", claims["sub"])
			c.Set("role", claims["role"])
		}

		c.Next()
	}
}

func RBACMiddleware(requiredRole string) gin.HandlerFunc {
	return func(c *gin.Context) {
		role, exists := c.Get("role")
		if !exists || role != requiredRole {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "Insufficient permissions"})
			return
		}
		c.Next()
	}
}

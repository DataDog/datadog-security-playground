package main

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"sync"
	"time"

	gintrace "github.com/DataDog/dd-trace-go/contrib/gin-gonic/gin/v2"
	"github.com/DataDog/dd-trace-go/v2/appsec"
	"github.com/DataDog/dd-trace-go/v2/ddtrace/tracer"
	"github.com/gin-gonic/gin"
)

type storedUser struct {
	UserID   string
	Username string
	Password string
	Email    string
	Phone    string
	USSSN    string
}

type authSession struct {
	Username  string
	SessionID string
}

type userResponse struct {
	UserID   string `json:"user_id"`
	Username string `json:"username"`
	Email    string `json:"email"`
	Phone    string `json:"phone"`
	USSSN    string `json:"us_ssn"`
}

type signupResponse struct {
	Message string `json:"message"`
}

type loginResponse struct {
	Message     string `json:"message"`
	AccessToken string `json:"access_token"`
	TokenType   string `json:"token_type"`
}

type healthResponse struct {
	Status      string `json:"status"`
	ServiceName string `json:"service_name"`
}

type errorResponse struct {
	Error string `json:"error"`
}

type detailErrorResponse struct {
	Detail string `json:"detail"`
}

type raspProbeResponse struct {
	Status string `json:"status"`
	Sink   string `json:"sink"`
	Input  string `json:"input"`
	Error  string `json:"error,omitempty"`
}

var (
	users        = map[string]storedUser{}
	authSessions = map[string]authSession{}
	mu           sync.RWMutex
)

func serviceName() string {
	if service := os.Getenv("DD_SERVICE"); service != "" {
		return service
	}
	return "appsec-test-api-go"
}

func generateUUIDv4() string {
	buffer := make([]byte, 16)
	_, _ = rand.Read(buffer)
	buffer[6] = (buffer[6] & 0x0f) | 0x40
	buffer[8] = (buffer[8] & 0x3f) | 0x80
	return fmt.Sprintf(
		"%x-%x-%x-%x-%x",
		buffer[0:4],
		buffer[4:6],
		buffer[6:8],
		buffer[8:10],
		buffer[10:16],
	)
}

func generateToken() string {
	buffer := make([]byte, 32)
	_, _ = rand.Read(buffer)
	return base64.RawURLEncoding.EncodeToString(buffer)
}

func buildContactEmail(username string) string {
	return fmt.Sprintf("%s@dogfooding.local", username)
}

func buildPhoneNumber(userID string) string {
	rawID := strings.ReplaceAll(userID, "-", "")
	numericSuffix, _ := strconv.ParseInt(rawID[0:4], 16, 64)
	return fmt.Sprintf("+1-202-555-%04d", numericSuffix%10000)
}

func buildUSSSN(userID string) string {
	rawID := strings.ReplaceAll(userID, "-", "")
	seed, _ := strconv.ParseInt(rawID[0:9], 16, 64)
	area := 100 + (seed % 900)
	group := 10 + ((seed / 1000) % 90)
	serial := 1000 + ((seed / 100000) % 9000)
	return fmt.Sprintf("%03d-%02d-%04d", area, group, serial)
}

func extractBearerToken(authorization string) (string, bool) {
	scheme, token, found := strings.Cut(strings.TrimSpace(authorization), " ")
	if !found || !strings.EqualFold(scheme, "Bearer") || strings.TrimSpace(token) == "" {
		return "", false
	}
	return strings.TrimSpace(token), true
}

func resolveAuthenticatedSession(authorization string) (authSession, storedUser, bool) {
	token, ok := extractBearerToken(authorization)
	if !ok {
		return authSession{}, storedUser{}, false
	}

	mu.RLock()
	session, sessionExists := authSessions[token]
	user, userExists := users[session.Username]
	mu.RUnlock()
	if !sessionExists || !userExists {
		return authSession{}, storedUser{}, false
	}

	return session, user, true
}

func seedDemoUsers() {
	const defaultPassword = "dogfooding-password"
	for _, username := range []string{"alice", "bob"} {
		userID := generateUUIDv4()
		users[username] = storedUser{
			UserID:   userID,
			Username: username,
			Password: defaultPassword,
			Email:    buildContactEmail(username),
			Phone:    buildPhoneNumber(userID),
			USSSN:    buildUSSSN(userID),
		}
	}
}

func toUserResponse(user storedUser) userResponse {
	return userResponse{
		UserID:   user.UserID,
		Username: user.Username,
		Email:    user.Email,
		Phone:    user.Phone,
		USSSN:    user.USSSN,
	}
}

func appsecUserTrackingMiddleware(c *gin.Context) {
	session, user, ok := resolveAuthenticatedSession(c.GetHeader("Authorization"))
	if ok {
		err := appsec.SetUser(
			c.Request.Context(),
			user.UserID,
			tracer.WithUserLogin(user.Username),
			tracer.WithUserSessionID(session.SessionID),
		)
		if err != nil {
			c.AbortWithStatusJSON(http.StatusForbidden, detailErrorResponse{Detail: "User blocked"})
			return
		}
	}

	c.Next()
}

func signupHandler(c *gin.Context) {
	username := c.Query("username")
	password := c.Query("password")

	mu.Lock()
	if _, exists := users[username]; exists {
		mu.Unlock()
		c.JSON(http.StatusBadRequest, errorResponse{Error: "User already exists"})
		return
	}

	userID := generateUUIDv4()
	users[username] = storedUser{
		UserID:   userID,
		Username: username,
		Password: password,
		Email:    buildContactEmail(username),
		Phone:    buildPhoneNumber(userID),
		USSSN:    buildUSSSN(userID),
	}
	mu.Unlock()

	appsec.TrackCustomEvent(
		c.Request.Context(),
		"users.signup",
		map[string]string{
			"usr.id":    userID,
			"usr.login": username,
		},
	)
	c.JSON(http.StatusOK, signupResponse{Message: "User created successfully"})
}

func loginHandler(c *gin.Context) {
	username := c.Query("username")
	password := c.Query("password")

	mu.RLock()
	user, exists := users[username]
	mu.RUnlock()
	if !exists {
		appsec.TrackUserLoginFailure(c.Request.Context(), username, false, nil)
		c.JSON(http.StatusForbidden, errorResponse{Error: "Invalid user password combination"})
		return
	}
	if user.Password != password {
		appsec.TrackUserLoginFailure(c.Request.Context(), username, true, map[string]string{"usr.id": user.UserID})
		c.JSON(http.StatusForbidden, errorResponse{Error: "Invalid user password combination"})
		return
	}

	token := generateToken()
	sessionID := generateUUIDv4()

	mu.Lock()
	authSessions[token] = authSession{
		Username:  username,
		SessionID: sessionID,
	}
	mu.Unlock()

	err := appsec.TrackUserLoginSuccess(
		c.Request.Context(),
		username,
		user.UserID,
		nil,
		tracer.WithUserSessionID(sessionID),
	)
	if err != nil {
		c.JSON(http.StatusForbidden, detailErrorResponse{Detail: "User blocked"})
		return
	}

	c.JSON(
		http.StatusOK,
		loginResponse{
			Message:     "Login successful",
			AccessToken: token,
			TokenType:   "bearer",
		},
	)
}

func whoamiHandler(c *gin.Context) {
	session, user, ok := resolveAuthenticatedSession(c.GetHeader("Authorization"))
	if !ok {
		c.JSON(http.StatusForbidden, detailErrorResponse{Detail: "User not logged in"})
		return
	}

	appsec.TrackCustomEvent(
		c.Request.Context(),
		"whoami_custom_business_logic_event",
		map[string]string{
			"username":   user.Username,
			"session_id": session.SessionID,
			"email":      user.Email,
			"phone":      user.Phone,
			"us_ssn":     user.USSSN,
		},
	)
	c.JSON(http.StatusOK, toUserResponse(user))
}

func healthHandler(c *gin.Context) {
	c.JSON(
		http.StatusOK,
		healthResponse{
			Status:      "ok",
			ServiceName: serviceName(),
		},
	)
}

func raspSSRFHandler(c *gin.Context) {
	targetURL := c.Query("url")
	client := http.Client{Timeout: 250 * time.Millisecond}
	request, err := http.NewRequestWithContext(
		c.Request.Context(),
		http.MethodGet,
		targetURL,
		nil,
	)
	if err != nil {
		c.JSON(http.StatusOK, raspProbeResponse{Status: "ok", Sink: "ssrf", Input: targetURL, Error: err.Error()})
		return
	}

	response, err := client.Do(request)
	if err != nil {
		c.JSON(http.StatusOK, raspProbeResponse{Status: "ok", Sink: "ssrf", Input: targetURL, Error: err.Error()})
		return
	}
	defer response.Body.Close()
	_, _ = io.CopyN(io.Discard, response.Body, 128)

	c.JSON(http.StatusOK, raspProbeResponse{Status: "ok", Sink: "ssrf", Input: targetURL})
}

func raspSHIHandler(c *gin.Context) {
	commandInput := c.Query("command")
	dangerousCommand := "echo " + commandInput
	execCtx, cancel := context.WithTimeout(c.Request.Context(), 300*time.Millisecond)
	defer cancel()

	err := runShellCommand(execCtx, dangerousCommand)
	if err != nil {
		c.JSON(http.StatusOK, raspProbeResponse{Status: "ok", Sink: "shi", Input: commandInput, Error: err.Error()})
		return
	}

	c.JSON(http.StatusOK, raspProbeResponse{Status: "ok", Sink: "shi", Input: commandInput})
}

func raspLFIHandler(c *gin.Context) {
	pathInput := c.Query("path")
	_, err := os.ReadFile(pathInput)
	if err != nil {
		c.JSON(http.StatusOK, raspProbeResponse{Status: "ok", Sink: "lfi", Input: pathInput, Error: err.Error()})
		return
	}

	c.JSON(http.StatusOK, raspProbeResponse{Status: "ok", Sink: "lfi", Input: pathInput})
}

func runShellCommand(ctx context.Context, command string) error {
	shellCandidates := []string{"/bin/sh", "/busybox/sh", "sh"}
	var lastErr error

	for _, shellPath := range shellCandidates {
		_, err := exec.CommandContext(ctx, shellPath, "-c", command).CombinedOutput()
		if err == nil {
			return nil
		}

		lastErr = err
		if !errors.Is(err, exec.ErrNotFound) && !strings.Contains(err.Error(), "no such file or directory") {
			return err
		}
	}

	return lastErr
}

func main() {
	tracer.Start(
		tracer.WithService(serviceName()),
		tracer.WithAppSecEnabled(true),
	)
	defer tracer.Stop()

	seedDemoUsers()

	router := gin.New()
	router.Use(gin.Recovery())
	router.Use(gintrace.Middleware(serviceName()))
	router.Use(appsecUserTrackingMiddleware)

	router.POST("/signup", signupHandler)
	router.POST("/login", loginHandler)
	router.GET("/whoami", whoamiHandler)
	router.GET("/health", healthHandler)
	router.GET("/rasp/ssrf", raspSSRFHandler)
	router.GET("/rasp/shi", raspSHIHandler)
	router.GET("/rasp/lfi", raspLFIHandler)

	if err := router.Run("0.0.0.0:8000"); err != nil {
		panic(err)
	}
}

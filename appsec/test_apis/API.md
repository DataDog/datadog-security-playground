# Test API Reference

This document describes the API used by the dogfooding scenarios.

Base URL:
- local direct: `http://localhost:8000`
- from web container: `http://appsec-test-api:8000`

## `GET /health`

Returns service health and service name.

Success response (`200`):

```json
{
  "status": "ok",
  "service_name": "appsec-dogfooding-api-<user>"
}
```

## `GET /rasp/ssrf`

Minimal SSRF-like endpoint used for RASP signal generation.

Query parameters:
- `url` (string, required): target URL fetched by the server.

Success response (`200`):

```json
{
  "status": "ok",
  "sink": "ssrf",
  "input": "http://169.254.169.254/latest/meta-data/",
  "error": "<optional error>"
}
```

Notes:
- This endpoint always returns `200` and includes execution errors in the optional `error` field.

## `GET /rasp/shi`

Minimal shell-injection endpoint used for RASP SHI signal generation.

Query parameters:
- `command` (string, required): user-controlled text concatenated into a shell command.

Success response (`200`):

```json
{
  "status": "ok",
  "sink": "shi",
  "input": "dogfooding; id",
  "error": "<optional error>"
}
```

Notes:
- This endpoint always returns `200` and includes execution errors in the optional `error` field.

## `GET /rasp/lfi`

Minimal local-file-access endpoint used for RASP LFI signal generation.

Query parameters:
- `path` (string, required): file path read by the server.

Success response (`200`):

```json
{
  "status": "ok",
  "sink": "lfi",
  "input": "/etc/passwd",
  "error": "<optional error>"
}
```

Notes:
- This endpoint always returns `200` and includes execution errors in the optional `error` field.

## `POST /signup`

Creates a user in the in-memory store.

Query parameters:
- `username` (string, required)
- `password` (string, required)

Success response (`200`):

```json
{
  "message": "User created successfully"
}
```

Error responses:
- `400` when user already exists

```json
{
  "error": "User already exists"
}
```

## `POST /login`

Authenticates a user and returns an access token.

Query parameters:
- `username` (string, required)
- `password` (string, required)

Success response (`200`):

```json
{
  "message": "Login successful",
  "access_token": "<token>",
  "token_type": "bearer"
}
```

Error responses:
- `403` invalid user/password combination

```json
{
  "error": "Invalid user password combination"
}
```

## `GET /whoami`

Returns current authenticated user details.

Headers:
- `Authorization: Bearer <access_token>`

Success response (`200`):

```json
{
  "user_id": "<uuid>",
  "username": "<username>",
  "email": "<username>@dogfooding.local",
  "phone": "+1-202-555-1234",
  "us_ssn": "123-45-6789"
}
```

Error responses:
- `403` when token is missing or invalid

```json
{
  "detail": "User not logged in"
}
```

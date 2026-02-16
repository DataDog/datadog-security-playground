import base64
import json
import os
import secrets
from typing import TYPE_CHECKING, Annotated, Literal
from uuid import uuid4

from ddtrace.appsec.track_user_sdk import (
    track_custom_event,
    track_login_failure,
    track_login_success,
    track_signup,
    track_user,
)
from fastapi import FastAPI, HTTPException, Path, Request, status
from fastapi.responses import JSONResponse, Response
from pydantic import BaseModel

if TYPE_CHECKING:
    from collections.abc import Awaitable, Callable


class User(BaseModel):
    user_id: str
    username: str
    email: str
    phone: str
    us_ssn: str


class StoredUser(BaseModel):
    user_id: str
    username: str
    password: str
    email: str
    phone: str
    us_ssn: str


class AuthSession(BaseModel):
    username: str
    session_id: str


class HealthResponse(BaseModel):
    status: Literal["ok"]
    service_name: str


class Api1SensitiveByIdResponse(BaseModel):
    requested_user_id: int
    username: str
    email: str
    phone: str
    us_ssn: str


class ErrorResponse(BaseModel):
    error: str


class SignupResponse(BaseModel):
    message: str


class LoginResponse(BaseModel):
    message: str
    access_token: str
    token_type: Literal["bearer"]


users: dict[str, StoredUser] = {}
auth_sessions: dict[str, AuthSession] = {}

app = FastAPI()


def _extract_bearer_token(request: Request) -> str | None:
    authorization = request.headers.get("Authorization")
    if authorization is None:
        return None

    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        return None

    return token.strip()


def _resolve_authenticated_session(request: Request) -> AuthSession | None:
    token = _extract_bearer_token(request)
    if token is None:
        return None

    auth_session = auth_sessions.get(token)
    if auth_session is None or auth_session.username not in users:
        return None

    return auth_session


@app.middleware("http")
async def track_user_middleware(
    request: Request, call_next: Callable[[Request], Awaitable[Response]]
) -> Response:
    auth_session = _resolve_authenticated_session(request)
    if auth_session is not None:
        track_user(
            auth_session.username,
            users[auth_session.username].user_id,
            session_id=auth_session.session_id,
        )
    return await call_next(request)


def _build_contact_email(username: str) -> str:
    return f"{username}@dogfooding.local"


def _build_phone_number(user_id: str) -> str:
    numeric_suffix = int(user_id.replace("-", "")[:4], 16) % 10000
    return f"+1-202-555-{numeric_suffix:04d}"


def _build_us_ssn(user_id: str) -> str:
    seed = int(user_id.replace("-", "")[:9], 16)
    area = 100 + (seed % 900)
    group = 10 + ((seed // 1000) % 90)
    serial = 1000 + ((seed // 100000) % 9000)
    return f"{area:03d}-{group:02d}-{serial:04d}"


DEFAULT_DEMO_PASSWORD = "dogfooding-password"  # noqa: S105


for demo_username in ("alice", "bob"):
    demo_user_id = str(uuid4())
    users[demo_username] = StoredUser(
        user_id=demo_user_id,
        username=demo_username,
        password=DEFAULT_DEMO_PASSWORD,
        email=_build_contact_email(demo_username),
        phone=_build_phone_number(demo_user_id),
        us_ssn=_build_us_ssn(demo_user_id),
    )


@app.post("/signup")
async def signup(username: str, password: str) -> JSONResponse:
    if username in users:
        error_response = ErrorResponse(error="User already exists")
        return JSONResponse(error_response.model_dump(), status_code=400)

    user_id = str(uuid4())
    users[username] = StoredUser(
        user_id=user_id,
        username=username,
        password=password,
        email=_build_contact_email(username),
        phone=_build_phone_number(user_id),
        us_ssn=_build_us_ssn(user_id),
    )

    track_signup(username, user_id, success=True)
    signup_response = SignupResponse(message="User created successfully")
    return JSONResponse(signup_response.model_dump())


@app.post("/login")
async def login(username: str, password: str) -> JSONResponse:
    if username not in users:
        track_login_failure(username, exists=False)
        error_response = ErrorResponse(error="Invalid user password combination")
        return JSONResponse(error_response.model_dump(), status_code=403)

    if users[username].password != password:
        track_login_failure(username, exists=True, user_id=users[username].user_id)
        error_response = ErrorResponse(error="Invalid user password combination")
        return JSONResponse(error_response.model_dump(), status_code=403)

    track_login_success(username, users[username].user_id)
    token = secrets.token_urlsafe(32)
    auth_sessions[token] = AuthSession(username=username, session_id=str(uuid4()))

    login_response = LoginResponse.model_validate(
        {
            "message": "Login successful",
            "access_token": token,
            "token_type": "bearer",
        }
    )
    return JSONResponse(login_response.model_dump())


@app.get("/whoami")
async def whoami(request: Request) -> User:
    auth_session = _resolve_authenticated_session(request)
    if auth_session is None:
        raise HTTPException(status_code=403, detail="User not logged in")

    current_user = users[auth_session.username]
    track_custom_event(
        "whoami_custom_business_logic_event",
        metadata={
            "username": auth_session.username,
            "session_id": auth_session.session_id,
            "email": current_user.email,
            "phone": current_user.phone,
            "us_ssn": current_user.us_ssn,
        },
    )
    return User(
        user_id=current_user.user_id,
        username=current_user.username,
        email=current_user.email,
        phone=current_user.phone,
        us_ssn=current_user.us_ssn,
    )


@app.get("/api1/users/{user_id}")
async def api1_sensitive_user_by_predictable_id(
    user_id: Annotated[int, Path(ge=1000, le=999999)],
    request: Request,
) -> Api1SensitiveByIdResponse:
    token = _extract_bearer_token(request)
    if token is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication required",
        )

    auth_session = auth_sessions.get(token)
    if auth_session is None or auth_session.username not in users:
        _, payload_segment, _ = token.split(".", maxsplit=2)
        padded_segment = payload_segment + ("=" * (-len(payload_segment) % 4))
        # VULNERABLE: accept JWT-like tokens and skip audience/signature validation.
        json.loads(base64.urlsafe_b64decode(padded_segment).decode("utf-8"))

    target_username = "alice" if user_id % 2 == 0 else "bob"
    target_user = users[target_username]

    return Api1SensitiveByIdResponse(
        requested_user_id=user_id,
        username=target_user.username,
        email=target_user.email,
        phone=target_user.phone,
        us_ssn=target_user.us_ssn,
    )


@app.get("/health")
async def health() -> HealthResponse:
    return HealthResponse(status="ok", service_name=os.getenv("DD_SERVICE", ""))

import os
import secrets
import subprocess
from pathlib import Path
from typing import TYPE_CHECKING, Literal
from urllib import request as urllib_request
from uuid import uuid4

from ddtrace.appsec.track_user_sdk import (
    track_custom_event,
    track_login_failure,
    track_login_success,
    track_signup,
    track_user,
)
from fastapi import FastAPI, HTTPException, Request
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


@app.get("/health")
async def health() -> HealthResponse:
    return HealthResponse(status="ok", service_name=os.getenv("DD_SERVICE", ""))


def _rasp_probe_response(
    *, sink: str, input_value: str, error: str | None = None
) -> JSONResponse:
    payload: dict[str, str] = {"status": "ok", "sink": sink, "input": input_value}
    if error is not None:
        payload["error"] = error
    return JSONResponse(payload)


@app.get("/rasp/ssrf")
def rasp_ssrf(url: str) -> JSONResponse:
    try:
        with urllib_request.urlopen(url, timeout=0.25) as response:  # noqa: S310
            response.read(128)
    except (OSError, ValueError) as error:
        return _rasp_probe_response(sink="ssrf", input_value=url, error=str(error))

    return _rasp_probe_response(sink="ssrf", input_value=url)


@app.get("/rasp/shi")
def rasp_shi(command: str) -> JSONResponse:
    try:
        subprocess.run(  # noqa: S602
            f"echo {command}",
            shell=True,
            check=False,
            capture_output=True,
            text=True,
            timeout=0.3,
        )
    except (OSError, subprocess.SubprocessError) as error:
        return _rasp_probe_response(sink="shi", input_value=command, error=str(error))

    return _rasp_probe_response(sink="shi", input_value=command)


@app.get("/rasp/lfi")
def rasp_lfi(path: str) -> JSONResponse:
    try:
        Path(path).read_text(encoding="utf-8", errors="ignore")
    except OSError as error:
        return _rasp_probe_response(sink="lfi", input_value=path, error=str(error))

    return _rasp_probe_response(sink="lfi", input_value=path)

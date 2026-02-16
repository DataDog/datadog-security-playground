from http import HTTPStatus
from typing import Any

import httpx

from ... import errors
from ...client import AuthenticatedClient, Client
from ...models.error_response import ErrorResponse
from ...models.login_response import LoginResponse
from ...models.validation_error_response import ValidationErrorResponse
from ...types import UNSET, Response


def _get_kwargs(
    *,
    username: str,
    password: str,
) -> dict[str, Any]:

    params: dict[str, Any] = {}

    params["username"] = username

    params["password"] = password

    params = {k: v for k, v in params.items() if v is not UNSET and v is not None}

    _kwargs: dict[str, Any] = {
        "method": "post",
        "url": "/login",
        "params": params,
    }

    return _kwargs


def _parse_response(
    *, client: AuthenticatedClient | Client, response: httpx.Response
) -> ErrorResponse | LoginResponse | ValidationErrorResponse | None:
    if response.status_code == 200:
        response_200 = LoginResponse.from_dict(response.json())

        return response_200

    if response.status_code == 403:
        response_403 = ErrorResponse.from_dict(response.json())

        return response_403

    if response.status_code == 422:
        response_422 = ValidationErrorResponse.from_dict(response.json())

        return response_422

    if client.raise_on_unexpected_status:
        raise errors.UnexpectedStatus(response.status_code, response.content)
    else:
        return None


def _build_response(
    *, client: AuthenticatedClient | Client, response: httpx.Response
) -> Response[ErrorResponse | LoginResponse | ValidationErrorResponse]:
    return Response(
        status_code=HTTPStatus(response.status_code),
        content=response.content,
        headers=response.headers,
        parsed=_parse_response(client=client, response=response),
    )


def sync_detailed(
    *,
    client: AuthenticatedClient | Client,
    username: str,
    password: str,
) -> Response[ErrorResponse | LoginResponse | ValidationErrorResponse]:
    """Authenticate and issue a bearer token

     Validates username/password against the in-memory user store.
    Input is provided through query parameters.

    Behavior:
      - Unknown username -> 403 with the same error message used for wrong password.
      - Wrong password -> 403.
      - Success -> generate a random token and store a session in `auth_sessions`.

    Args:
        username (str):
        password (str):

    Raises:
        errors.UnexpectedStatus: If the server returns an undocumented status code and Client.raise_on_unexpected_status is True.
        httpx.TimeoutException: If the request takes longer than Client.timeout.

    Returns:
        Response[ErrorResponse | LoginResponse | ValidationErrorResponse]
    """

    kwargs = _get_kwargs(
        username=username,
        password=password,
    )

    response = client.get_httpx_client().request(
        **kwargs,
    )

    return _build_response(client=client, response=response)


def sync(
    *,
    client: AuthenticatedClient | Client,
    username: str,
    password: str,
) -> ErrorResponse | LoginResponse | ValidationErrorResponse | None:
    """Authenticate and issue a bearer token

     Validates username/password against the in-memory user store.
    Input is provided through query parameters.

    Behavior:
      - Unknown username -> 403 with the same error message used for wrong password.
      - Wrong password -> 403.
      - Success -> generate a random token and store a session in `auth_sessions`.

    Args:
        username (str):
        password (str):

    Raises:
        errors.UnexpectedStatus: If the server returns an undocumented status code and Client.raise_on_unexpected_status is True.
        httpx.TimeoutException: If the request takes longer than Client.timeout.

    Returns:
        ErrorResponse | LoginResponse | ValidationErrorResponse
    """

    return sync_detailed(
        client=client,
        username=username,
        password=password,
    ).parsed


async def asyncio_detailed(
    *,
    client: AuthenticatedClient | Client,
    username: str,
    password: str,
) -> Response[ErrorResponse | LoginResponse | ValidationErrorResponse]:
    """Authenticate and issue a bearer token

     Validates username/password against the in-memory user store.
    Input is provided through query parameters.

    Behavior:
      - Unknown username -> 403 with the same error message used for wrong password.
      - Wrong password -> 403.
      - Success -> generate a random token and store a session in `auth_sessions`.

    Args:
        username (str):
        password (str):

    Raises:
        errors.UnexpectedStatus: If the server returns an undocumented status code and Client.raise_on_unexpected_status is True.
        httpx.TimeoutException: If the request takes longer than Client.timeout.

    Returns:
        Response[ErrorResponse | LoginResponse | ValidationErrorResponse]
    """

    kwargs = _get_kwargs(
        username=username,
        password=password,
    )

    response = await client.get_async_httpx_client().request(**kwargs)

    return _build_response(client=client, response=response)


async def asyncio(
    *,
    client: AuthenticatedClient | Client,
    username: str,
    password: str,
) -> ErrorResponse | LoginResponse | ValidationErrorResponse | None:
    """Authenticate and issue a bearer token

     Validates username/password against the in-memory user store.
    Input is provided through query parameters.

    Behavior:
      - Unknown username -> 403 with the same error message used for wrong password.
      - Wrong password -> 403.
      - Success -> generate a random token and store a session in `auth_sessions`.

    Args:
        username (str):
        password (str):

    Raises:
        errors.UnexpectedStatus: If the server returns an undocumented status code and Client.raise_on_unexpected_status is True.
        httpx.TimeoutException: If the request takes longer than Client.timeout.

    Returns:
        ErrorResponse | LoginResponse | ValidationErrorResponse
    """

    return (
        await asyncio_detailed(
            client=client,
            username=username,
            password=password,
        )
    ).parsed

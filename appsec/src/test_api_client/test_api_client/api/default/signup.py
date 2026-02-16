from http import HTTPStatus
from typing import Any

import httpx

from ... import errors
from ...client import AuthenticatedClient, Client
from ...models.error_response import ErrorResponse
from ...models.signup_response import SignupResponse
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
        "url": "/signup",
        "params": params,
    }

    return _kwargs


def _parse_response(
    *, client: AuthenticatedClient | Client, response: httpx.Response
) -> ErrorResponse | SignupResponse | ValidationErrorResponse | None:
    if response.status_code == 200:
        response_200 = SignupResponse.from_dict(response.json())

        return response_200

    if response.status_code == 400:
        response_400 = ErrorResponse.from_dict(response.json())

        return response_400

    if response.status_code == 422:
        response_422 = ValidationErrorResponse.from_dict(response.json())

        return response_422

    if client.raise_on_unexpected_status:
        raise errors.UnexpectedStatus(response.status_code, response.content)
    else:
        return None


def _build_response(
    *, client: AuthenticatedClient | Client, response: httpx.Response
) -> Response[ErrorResponse | SignupResponse | ValidationErrorResponse]:
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
) -> Response[ErrorResponse | SignupResponse | ValidationErrorResponse]:
    """Create a user account

     Creates a user in the in-memory `users` map.
    Input is provided through query parameters.

    Behavior:
      - If `username` already exists, return 400.
      - Otherwise create a user with generated `user_id`, `email`, `phone`, and `us_ssn`.

    Args:
        username (str):
        password (str):

    Raises:
        errors.UnexpectedStatus: If the server returns an undocumented status code and Client.raise_on_unexpected_status is True.
        httpx.TimeoutException: If the request takes longer than Client.timeout.

    Returns:
        Response[ErrorResponse | SignupResponse | ValidationErrorResponse]
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
) -> ErrorResponse | SignupResponse | ValidationErrorResponse | None:
    """Create a user account

     Creates a user in the in-memory `users` map.
    Input is provided through query parameters.

    Behavior:
      - If `username` already exists, return 400.
      - Otherwise create a user with generated `user_id`, `email`, `phone`, and `us_ssn`.

    Args:
        username (str):
        password (str):

    Raises:
        errors.UnexpectedStatus: If the server returns an undocumented status code and Client.raise_on_unexpected_status is True.
        httpx.TimeoutException: If the request takes longer than Client.timeout.

    Returns:
        ErrorResponse | SignupResponse | ValidationErrorResponse
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
) -> Response[ErrorResponse | SignupResponse | ValidationErrorResponse]:
    """Create a user account

     Creates a user in the in-memory `users` map.
    Input is provided through query parameters.

    Behavior:
      - If `username` already exists, return 400.
      - Otherwise create a user with generated `user_id`, `email`, `phone`, and `us_ssn`.

    Args:
        username (str):
        password (str):

    Raises:
        errors.UnexpectedStatus: If the server returns an undocumented status code and Client.raise_on_unexpected_status is True.
        httpx.TimeoutException: If the request takes longer than Client.timeout.

    Returns:
        Response[ErrorResponse | SignupResponse | ValidationErrorResponse]
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
) -> ErrorResponse | SignupResponse | ValidationErrorResponse | None:
    """Create a user account

     Creates a user in the in-memory `users` map.
    Input is provided through query parameters.

    Behavior:
      - If `username` already exists, return 400.
      - Otherwise create a user with generated `user_id`, `email`, `phone`, and `us_ssn`.

    Args:
        username (str):
        password (str):

    Raises:
        errors.UnexpectedStatus: If the server returns an undocumented status code and Client.raise_on_unexpected_status is True.
        httpx.TimeoutException: If the request takes longer than Client.timeout.

    Returns:
        ErrorResponse | SignupResponse | ValidationErrorResponse
    """

    return (
        await asyncio_detailed(
            client=client,
            username=username,
            password=password,
        )
    ).parsed

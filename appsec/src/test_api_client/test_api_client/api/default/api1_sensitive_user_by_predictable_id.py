from http import HTTPStatus
from typing import Any, cast
from urllib.parse import quote

import httpx

from ... import errors
from ...client import AuthenticatedClient, Client
from ...models.api_1_sensitive_by_id_response import Api1SensitiveByIdResponse
from ...models.detail_error_response import DetailErrorResponse
from ...models.validation_error_response import ValidationErrorResponse
from ...types import Response


def _get_kwargs(
    user_id: int,
) -> dict[str, Any]:

    _kwargs: dict[str, Any] = {
        "method": "get",
        "url": "/api1/users/{user_id}".format(
            user_id=quote(str(user_id), safe=""),
        ),
    }

    return _kwargs


def _parse_response(
    *, client: AuthenticatedClient | Client, response: httpx.Response
) -> Any | Api1SensitiveByIdResponse | DetailErrorResponse | ValidationErrorResponse | None:
    if response.status_code == 200:
        response_200 = Api1SensitiveByIdResponse.from_dict(response.json())

        return response_200

    if response.status_code == 401:
        response_401 = DetailErrorResponse.from_dict(response.json())

        return response_401

    if response.status_code == 422:
        response_422 = ValidationErrorResponse.from_dict(response.json())

        return response_422

    if response.status_code == 500:
        response_500 = cast(Any, None)
        return response_500

    if client.raise_on_unexpected_status:
        raise errors.UnexpectedStatus(response.status_code, response.content)
    else:
        return None


def _build_response(
    *, client: AuthenticatedClient | Client, response: httpx.Response
) -> Response[Any | Api1SensitiveByIdResponse | DetailErrorResponse | ValidationErrorResponse]:
    return Response(
        status_code=HTTPStatus(response.status_code),
        content=response.content,
        headers=response.headers,
        parsed=_parse_response(client=client, response=response),
    )


def sync_detailed(
    user_id: int,
    *,
    client: AuthenticatedClient,
) -> Response[Any | Api1SensitiveByIdResponse | DetailErrorResponse | ValidationErrorResponse]:
    """Return sensitive user data by predictable object ID

     Returns sensitive data for one of the two seeded users based only on `user_id` parity.

    Authorization behavior:
      1. Parse `Authorization` as `Bearer <token>`.
         - Missing or malformed bearer header -> 401 (`detail: Authentication required`).
      2. If token exists in `auth_sessions` and session username exists in `users`, authorize.
      3. Otherwise, attempt JWT-like fallback parsing:
         - Split token as three parts using `token.split('.', maxsplit=2)` unpacking.
         - Base64url-decode the middle segment (with '=' padding to a multiple of 4).
         - Decode UTF-8 and parse JSON.
         - Parsed payload content is not used for authorization decisions.

    Target user mapping:
      - even `user_id` -> `alice`
      - odd `user_id` -> `bob`

    Important:
      - JWT fallback parsing errors are not wrapped; they bubble up as framework-default 500 responses.

    Args:
        user_id (int):

    Raises:
        errors.UnexpectedStatus: If the server returns an undocumented status code and Client.raise_on_unexpected_status is True.
        httpx.TimeoutException: If the request takes longer than Client.timeout.

    Returns:
        Response[Any | Api1SensitiveByIdResponse | DetailErrorResponse | ValidationErrorResponse]
    """

    kwargs = _get_kwargs(
        user_id=user_id,
    )

    response = client.get_httpx_client().request(
        **kwargs,
    )

    return _build_response(client=client, response=response)


def sync(
    user_id: int,
    *,
    client: AuthenticatedClient,
) -> Any | Api1SensitiveByIdResponse | DetailErrorResponse | ValidationErrorResponse | None:
    """Return sensitive user data by predictable object ID

     Returns sensitive data for one of the two seeded users based only on `user_id` parity.

    Authorization behavior:
      1. Parse `Authorization` as `Bearer <token>`.
         - Missing or malformed bearer header -> 401 (`detail: Authentication required`).
      2. If token exists in `auth_sessions` and session username exists in `users`, authorize.
      3. Otherwise, attempt JWT-like fallback parsing:
         - Split token as three parts using `token.split('.', maxsplit=2)` unpacking.
         - Base64url-decode the middle segment (with '=' padding to a multiple of 4).
         - Decode UTF-8 and parse JSON.
         - Parsed payload content is not used for authorization decisions.

    Target user mapping:
      - even `user_id` -> `alice`
      - odd `user_id` -> `bob`

    Important:
      - JWT fallback parsing errors are not wrapped; they bubble up as framework-default 500 responses.

    Args:
        user_id (int):

    Raises:
        errors.UnexpectedStatus: If the server returns an undocumented status code and Client.raise_on_unexpected_status is True.
        httpx.TimeoutException: If the request takes longer than Client.timeout.

    Returns:
        Any | Api1SensitiveByIdResponse | DetailErrorResponse | ValidationErrorResponse
    """

    return sync_detailed(
        user_id=user_id,
        client=client,
    ).parsed


async def asyncio_detailed(
    user_id: int,
    *,
    client: AuthenticatedClient,
) -> Response[Any | Api1SensitiveByIdResponse | DetailErrorResponse | ValidationErrorResponse]:
    """Return sensitive user data by predictable object ID

     Returns sensitive data for one of the two seeded users based only on `user_id` parity.

    Authorization behavior:
      1. Parse `Authorization` as `Bearer <token>`.
         - Missing or malformed bearer header -> 401 (`detail: Authentication required`).
      2. If token exists in `auth_sessions` and session username exists in `users`, authorize.
      3. Otherwise, attempt JWT-like fallback parsing:
         - Split token as three parts using `token.split('.', maxsplit=2)` unpacking.
         - Base64url-decode the middle segment (with '=' padding to a multiple of 4).
         - Decode UTF-8 and parse JSON.
         - Parsed payload content is not used for authorization decisions.

    Target user mapping:
      - even `user_id` -> `alice`
      - odd `user_id` -> `bob`

    Important:
      - JWT fallback parsing errors are not wrapped; they bubble up as framework-default 500 responses.

    Args:
        user_id (int):

    Raises:
        errors.UnexpectedStatus: If the server returns an undocumented status code and Client.raise_on_unexpected_status is True.
        httpx.TimeoutException: If the request takes longer than Client.timeout.

    Returns:
        Response[Any | Api1SensitiveByIdResponse | DetailErrorResponse | ValidationErrorResponse]
    """

    kwargs = _get_kwargs(
        user_id=user_id,
    )

    response = await client.get_async_httpx_client().request(**kwargs)

    return _build_response(client=client, response=response)


async def asyncio(
    user_id: int,
    *,
    client: AuthenticatedClient,
) -> Any | Api1SensitiveByIdResponse | DetailErrorResponse | ValidationErrorResponse | None:
    """Return sensitive user data by predictable object ID

     Returns sensitive data for one of the two seeded users based only on `user_id` parity.

    Authorization behavior:
      1. Parse `Authorization` as `Bearer <token>`.
         - Missing or malformed bearer header -> 401 (`detail: Authentication required`).
      2. If token exists in `auth_sessions` and session username exists in `users`, authorize.
      3. Otherwise, attempt JWT-like fallback parsing:
         - Split token as three parts using `token.split('.', maxsplit=2)` unpacking.
         - Base64url-decode the middle segment (with '=' padding to a multiple of 4).
         - Decode UTF-8 and parse JSON.
         - Parsed payload content is not used for authorization decisions.

    Target user mapping:
      - even `user_id` -> `alice`
      - odd `user_id` -> `bob`

    Important:
      - JWT fallback parsing errors are not wrapped; they bubble up as framework-default 500 responses.

    Args:
        user_id (int):

    Raises:
        errors.UnexpectedStatus: If the server returns an undocumented status code and Client.raise_on_unexpected_status is True.
        httpx.TimeoutException: If the request takes longer than Client.timeout.

    Returns:
        Any | Api1SensitiveByIdResponse | DetailErrorResponse | ValidationErrorResponse
    """

    return (
        await asyncio_detailed(
            user_id=user_id,
            client=client,
        )
    ).parsed

from __future__ import annotations

from collections.abc import Mapping
from typing import Any, Literal, TypeVar, cast

from attrs import define as _attrs_define

T = TypeVar("T", bound="HealthResponse")


@_attrs_define
class HealthResponse:
    """
    Attributes:
        status (Literal['ok']):
        service_name (str):
    """

    status: Literal["ok"]
    service_name: str

    def to_dict(self) -> dict[str, Any]:
        status = self.status

        service_name = self.service_name

        field_dict: dict[str, Any] = {}

        field_dict.update(
            {
                "status": status,
                "service_name": service_name,
            }
        )

        return field_dict

    @classmethod
    def from_dict(cls: type[T], src_dict: Mapping[str, Any]) -> T:
        d = dict(src_dict)
        status = cast(Literal["ok"], d.pop("status"))
        if status != "ok":
            raise ValueError(f"status must match const 'ok', got '{status}'")

        service_name = d.pop("service_name")

        health_response = cls(
            status=status,
            service_name=service_name,
        )

        return health_response

from __future__ import annotations

from collections.abc import Mapping
from typing import Any, TypeVar

from attrs import define as _attrs_define

T = TypeVar("T", bound="DetailErrorResponse")


@_attrs_define
class DetailErrorResponse:
    """
    Attributes:
        detail (str):
    """

    detail: str

    def to_dict(self) -> dict[str, Any]:
        detail = self.detail

        field_dict: dict[str, Any] = {}

        field_dict.update(
            {
                "detail": detail,
            }
        )

        return field_dict

    @classmethod
    def from_dict(cls: type[T], src_dict: Mapping[str, Any]) -> T:
        d = dict(src_dict)
        detail = d.pop("detail")

        detail_error_response = cls(
            detail=detail,
        )

        return detail_error_response

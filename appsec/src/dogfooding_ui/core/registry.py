from __future__ import annotations

import importlib
import pkgutil
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from .model import Scenario, ScenarioGroup

_SCENARIOS: dict[str, type[Scenario]] = {}
_GROUPS: dict[str, type[ScenarioGroup]] = {}
_SCENARIOS_PACKAGE = "dogfooding_ui.core.scenarios"
_GROUPS_MODULE = "dogfooding_ui.core.groups"


def load_scenarios() -> None:
    importlib.import_module(_GROUPS_MODULE)

    package = importlib.import_module(_SCENARIOS_PACKAGE)
    package_path = getattr(package, "__path__", None)
    if package_path is None:
        msg = f"Package '{_SCENARIOS_PACKAGE}' is missing __path__."
        raise RuntimeError(msg)

    for module_info in pkgutil.iter_modules(
        path=package_path,
        prefix=f"{_SCENARIOS_PACKAGE}.",
    ):
        importlib.import_module(module_info.name)


def register(scenario_class: type[Scenario]) -> type[Scenario]:
    scenario_name = scenario_class.scenario_name()
    if scenario_name in _SCENARIOS:
        msg = f"Scenario '{scenario_name}' is already registered."
        raise ValueError(msg)
    _SCENARIOS[scenario_name] = scenario_class
    return scenario_class


def register_group(group_class: type[ScenarioGroup]) -> type[ScenarioGroup]:
    group_name = group_class.group_name()
    if group_name in _GROUPS:
        msg = f"Scenario group '{group_name}' is already registered."
        raise ValueError(msg)
    _GROUPS[group_name] = group_class
    return group_class


def all_scenarios() -> list[type[Scenario]]:
    return sorted(_SCENARIOS.values(), key=lambda scenario: scenario.scenario_name())


def by_name(name: str) -> type[Scenario]:
    scenario = _SCENARIOS.get(name)
    if scenario is None:
        msg = f"Unknown scenario '{name}'."
        raise ValueError(msg)
    return scenario


def by_group(group: str) -> list[type[Scenario]]:
    scenario_group = group_by_name(group)
    unique_scenarios = set(scenario_group.scenarios)
    return sorted(unique_scenarios, key=lambda scenario: scenario.scenario_name())


def all_groups() -> list[type[ScenarioGroup]]:
    return sorted(_GROUPS.values(), key=lambda group: group.group_name())


def group_by_name(name: str) -> type[ScenarioGroup]:
    group = _GROUPS.get(name)
    if group is None:
        msg = f"Unknown scenario group '{name}'."
        raise ValueError(msg)
    return group


def groups_for_scenario(
    scenario_class: type[Scenario],
) -> list[type[ScenarioGroup]]:
    groups = [group for group in _GROUPS.values() if scenario_class in group.scenarios]
    return sorted(groups, key=lambda group: group.group_name())

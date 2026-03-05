"""Core scenario models and registry."""

from .model import (
    Scenario,
    ScenarioGroup,
    ScenarioRunResult,
    StepExecutionResult,
    StepMetadata,
    Steps,
    StepSummary,
    step_metadata,
)
from .registry import (
    all_groups,
    all_scenarios,
    by_group,
    by_name,
    group_by_name,
    groups_for_scenario,
    load_scenarios,
    register,
    register_group,
)

__all__ = [
    "Scenario",
    "ScenarioGroup",
    "ScenarioRunResult",
    "StepExecutionResult",
    "StepMetadata",
    "StepSummary",
    "Steps",
    "all_groups",
    "all_scenarios",
    "by_group",
    "by_name",
    "group_by_name",
    "groups_for_scenario",
    "load_scenarios",
    "register",
    "register_group",
    "step_metadata",
]

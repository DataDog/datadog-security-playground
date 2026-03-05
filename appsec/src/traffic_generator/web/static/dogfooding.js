const runButtons = Array.from(
  document.querySelectorAll("button[data-scenario-run]"),
)

const statusByScenario = new Map(
  Array.from(document.querySelectorAll("[data-scenario-status]")).map((node) => [
    node.getAttribute("data-scenario-status"),
    node,
  ]),
)

const resultsByScenario = new Map(
  Array.from(document.querySelectorAll("[data-scenario-results]")).map((node) => [
    node.getAttribute("data-scenario-results"),
    node,
  ]),
)

const stepStatusByKey = new Map(
  Array.from(document.querySelectorAll("[data-step-status]")).map((node) => [
    node.getAttribute("data-step-status"),
    node,
  ]),
)

const stepMessageByKey = new Map(
  Array.from(document.querySelectorAll("[data-step-message]")).map((node) => [
    node.getAttribute("data-step-message"),
    node,
  ]),
)

const summaryActionNodes = Array.from(
  document.querySelectorAll("[data-scenario-summary-action]"),
)

const runningScenarios = new Set()

function scenarioStepPrefix(scenarioName) {
  return `${scenarioName}::`
}

function setStatus(scenarioName, message, tone) {
  const node = statusByScenario.get(scenarioName)
  if (!(node instanceof HTMLElement)) {
    return
  }

  node.textContent = message
  node.className = `scenario-run-status scenario-run-status-${tone}`
}

function setRunButtonState(button, running) {
  const icon = button.querySelector(".run-scenario-glyph")
  const label = button.querySelector(".run-scenario-label")

  button.disabled = running
  if (!(label instanceof HTMLElement)) {
    button.textContent = running ? "Running..." : "▶ Run"
    return
  }

  label.textContent = running ? "Running..." : "Run"
  if (icon instanceof HTMLElement) {
    icon.hidden = running
  }
}

function clearResults(scenarioName) {
  const node = resultsByScenario.get(scenarioName)
  if (!(node instanceof HTMLElement)) {
    return null
  }

  node.innerHTML = ""
  return node
}

function clearStepMessage(stepKey) {
  const node = stepMessageByKey.get(stepKey)
  if (!(node instanceof HTMLElement)) {
    return
  }

  node.replaceChildren()
  node.hidden = true
}

function resetInlineSteps(scenarioName) {
  const prefix = scenarioStepPrefix(scenarioName)
  for (const [stepKey, node] of stepStatusByKey) {
    if (!(typeof stepKey === "string" && stepKey.startsWith(prefix))) {
      continue
    }

    if (!(node instanceof HTMLElement)) {
      continue
    }

    node.hidden = true
    node.textContent = ""
    node.className = "step-inline-status step-inline-status-idle"
    clearStepMessage(stepKey)
  }
}

function markInlineStepsRunning(scenarioName) {
  const prefix = scenarioStepPrefix(scenarioName)
  for (const [stepKey, node] of stepStatusByKey) {
    if (!(typeof stepKey === "string" && stepKey.startsWith(prefix))) {
      continue
    }

    if (!(node instanceof HTMLElement)) {
      continue
    }

    node.hidden = false
    node.textContent = "Running..."
    node.className = "step-inline-status step-inline-status-running"
    clearStepMessage(stepKey)
  }
}

function renderInlineStepMessage(stepKey, step, datadogLink) {
  const node = stepMessageByKey.get(stepKey)
  if (!(node instanceof HTMLElement)) {
    return
  }

  const hasUnblockLink =
    typeof step.unblock_link === "string" && step.unblock_link.length > 0
  const hasDatadogLink =
    hasUnblockLink && typeof datadogLink === "string" && datadogLink.length > 0

  node.replaceChildren()
  node.className = "step-inline-message"
  if (hasUnblockLink) {
    node.classList.add("step-inline-message-blocked")
  }

  if (step.outcome !== "success" && typeof step.summary === "string" && step.summary) {
    const summaryText = document.createElement("span")
    summaryText.textContent = step.summary
    node.appendChild(summaryText)
  }

  if (hasUnblockLink) {
    const actions = document.createElement("span")
    actions.className = "step-inline-actions"

    const link = document.createElement("a")
    link.href = step.unblock_link
    link.target = "_blank"
    link.rel = "noopener noreferrer"
    link.className = "step-inline-unblock-button"

    const icon = cloneDatadogIcon()
    if (icon instanceof SVGElement) {
      icon.classList.add("step-inline-unblock-icon")
      link.appendChild(icon)
    }

    const label = document.createElement("span")
    label.textContent = "Unblock IP"
    link.appendChild(label)

    actions.appendChild(link)

    if (hasDatadogLink) {
      const datadogLinkButton = document.createElement("a")
      datadogLinkButton.href = datadogLink
      datadogLinkButton.target = "_blank"
      datadogLinkButton.rel = "noopener noreferrer"
      datadogLinkButton.className = "step-inline-datadog-button"

      const datadogIcon = cloneDatadogIcon()
      if (datadogIcon instanceof SVGElement) {
        datadogIcon.classList.add("step-inline-datadog-icon")
        datadogLinkButton.appendChild(datadogIcon)
      }

      const datadogLabel = document.createElement("span")
      datadogLabel.textContent = "Open in Datadog"
      datadogLinkButton.appendChild(datadogLabel)
      actions.appendChild(datadogLinkButton)
    }

    if (node.childNodes.length > 0) {
      const separator = document.createTextNode(" ")
      node.appendChild(separator)
    }

    node.appendChild(actions)
  }

  node.hidden = node.childNodes.length === 0
}

function renderInlineStepResult(scenarioName, step, datadogLink) {
  if (typeof step.step_id !== "string") {
    return
  }

  const stepKey = `${scenarioName}::${step.step_id}`
  const node = stepStatusByKey.get(stepKey)
  if (!(node instanceof HTMLElement)) {
    return
  }

  const isSuccess = step.outcome === "success"
  const label = isSuccess ? "Success" : "Failed"
  node.hidden = false
  node.textContent = `${label} · ${step.duration_ms} ms`
  node.className = `step-inline-status step-inline-status-${step.outcome}`

  renderInlineStepMessage(stepKey, step, datadogLink)
}

function hideUnreportedSteps(scenarioName, reportedStepIds) {
  const prefix = scenarioStepPrefix(scenarioName)
  for (const [stepKey, node] of stepStatusByKey) {
    if (!(typeof stepKey === "string" && stepKey.startsWith(prefix))) {
      continue
    }

    if (!(node instanceof HTMLElement)) {
      continue
    }

    const stepId = stepKey.slice(prefix.length)
    if (reportedStepIds.has(stepId)) {
      continue
    }

    node.hidden = true
    node.textContent = ""
    node.className = "step-inline-status step-inline-status-idle"
    clearStepMessage(stepKey)
  }
}

function renderErrorResult(scenarioName, errorMessage) {
  const resultsNode = clearResults(scenarioName)
  if (!(resultsNode instanceof HTMLElement)) {
    return
  }

  const errorText = document.createElement("p")
  errorText.className = "scenario-inline-error"
  errorText.textContent = errorMessage
  resultsNode.appendChild(errorText)
}

function cloneDatadogIcon() {
  const template = document.getElementById("datadog-icon-template")
  if (!(template instanceof HTMLTemplateElement)) {
    return null
  }

  const icon = template.content.firstElementChild
  if (!(icon instanceof SVGElement)) {
    return null
  }

  const clonedIcon = icon.cloneNode(true)
  if (!(clonedIcon instanceof SVGElement)) {
    return null
  }

  clonedIcon.classList.add("scenario-run-conclusion-icon")
  return clonedIcon
}

function renderDatadogLink(resultsNode, datadogLink) {
  if (!(resultsNode instanceof HTMLElement)) {
    return
  }

  if (typeof datadogLink !== "string" || datadogLink.length === 0) {
    return
  }

  const linkLine = document.createElement("p")
  linkLine.className = "scenario-run-conclusion-link"

  const link = document.createElement("a")
  link.href = datadogLink
  link.target = "_blank"
  link.rel = "noopener noreferrer"

  const icon = cloneDatadogIcon()
  if (icon instanceof SVGElement) {
    link.appendChild(icon)
  }

  const label = document.createElement("span")
  label.textContent = "Open in Datadog"
  link.appendChild(label)

  linkLine.append(link)
  resultsNode.appendChild(linkLine)
}

function renderStepResults(scenarioName, stepResults, datadogLink) {
  const resultsNode = clearResults(scenarioName)
  if (!(resultsNode instanceof HTMLElement)) {
    return
  }

  if (!Array.isArray(stepResults) || stepResults.length === 0) {
    resetInlineSteps(scenarioName)
    renderDatadogLink(resultsNode, datadogLink)
    return
  }

  const reportedStepIds = new Set()
  let hasBlockedStep = false
  for (const step of stepResults) {
    if (typeof step.step_id === "string") {
      reportedStepIds.add(step.step_id)
    }

    if (typeof step.unblock_link === "string" && step.unblock_link.length > 0) {
      hasBlockedStep = true
    }

    renderInlineStepResult(scenarioName, step, datadogLink)
  }

  hideUnreportedSteps(scenarioName, reportedStepIds)
  if (!hasBlockedStep) {
    renderDatadogLink(resultsNode, datadogLink)
  }
}

function statusMessageForOutcome(outcome, stepResultsLength) {
  if (outcome === "success") {
    return `Success (${stepResultsLength} step${stepResultsLength === 1 ? "" : "s"}).`
  }

  return "Needs attention. Review steps."
}

async function runScenario(scenarioName, button) {
  if (runningScenarios.has(scenarioName)) {
    return
  }

  runningScenarios.add(scenarioName)
  setRunButtonState(button, true)
  clearResults(scenarioName)
  markInlineStepsRunning(scenarioName)
  setStatus(scenarioName, "Running...", "running")

  try {
    const response = await fetch(
      `/dogfooding/api/scenarios/${encodeURIComponent(scenarioName)}/run`,
      {
        method: "POST",
      },
    )

    let payload = null
    try {
      payload = await response.json()
    } catch {
      payload = null
    }

    if (!response.ok) {
      const detail =
        payload && typeof payload.detail === "string"
          ? payload.detail
          : `HTTP ${response.status}`
      throw new Error(detail)
    }

    renderStepResults(scenarioName, payload.step_results, payload.datadog_link)
    setStatus(
      scenarioName,
      statusMessageForOutcome(payload.outcome, payload.step_results.length),
      payload.outcome,
    )
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    setStatus(scenarioName, `Execution failed: ${message}`, "failure")
    resetInlineSteps(scenarioName)
    renderErrorResult(scenarioName, message)
  } finally {
    runningScenarios.delete(scenarioName)
    setRunButtonState(button, false)
  }
}

for (const node of summaryActionNodes) {
  node.addEventListener("click", (event) => {
    event.stopPropagation()
  })
}

for (const button of runButtons) {
  const scenarioName = button.getAttribute("data-scenario-run")
  if (!scenarioName) {
    continue
  }

  button.addEventListener("click", (event) => {
    event.preventDefault()
    event.stopPropagation()
    void runScenario(scenarioName, button)
  })
}

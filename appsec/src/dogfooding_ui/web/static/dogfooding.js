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

const runningScenarios = new Set()

function formatJson(value) {
  if (typeof value === "string") {
    return value
  }

  try {
    return JSON.stringify(value, null, 2)
  } catch {
    return String(value)
  }
}

function setStatus(scenarioName, message, tone) {
  const node = statusByScenario.get(scenarioName)
  if (!(node instanceof HTMLElement)) {
    return
  }

  node.textContent = message
  node.className = `scenario-run-status scenario-run-status-${tone}`
}

function clearResults(scenarioName) {
  const node = resultsByScenario.get(scenarioName)
  if (!(node instanceof HTMLElement)) {
    return null
  }

  node.innerHTML = ""
  return node
}

function renderErrorResult(scenarioName, errorMessage) {
  const resultsNode = clearResults(scenarioName)
  if (!(resultsNode instanceof HTMLElement)) {
    return
  }

  const errorBlock = document.createElement("article")
  errorBlock.className = "step-run-card step-run-failure"

  const heading = document.createElement("strong")
  heading.textContent = "Execution error"

  const errorText = document.createElement("pre")
  errorText.className = "step-run-details"
  errorText.textContent = errorMessage

  errorBlock.append(heading, errorText)
  resultsNode.appendChild(errorBlock)
}

function renderDatadogLink(resultsNode, datadogLink) {
  if (typeof datadogLink !== "string" || datadogLink.length === 0) {
    return
  }

  const conclusionCard = document.createElement("article")
  conclusionCard.className = "step-run-card scenario-run-conclusion-card"

  const title = document.createElement("strong")
  title.className = "scenario-run-conclusion-title"
  title.textContent = "See the result in Datadog"

  const linkLine = document.createElement("p")
  linkLine.className = "scenario-run-conclusion-link"

  const link = document.createElement("a")
  link.href = datadogLink
  link.target = "_blank"
  link.rel = "noopener noreferrer"
  link.textContent = "Open link"

  linkLine.append(link)
  conclusionCard.append(title, linkLine)
  resultsNode.appendChild(conclusionCard)
}

function renderStepResults(scenarioName, stepResults, datadogLink) {
  const resultsNode = clearResults(scenarioName)
  if (!(resultsNode instanceof HTMLElement)) {
    return
  }

  if (!Array.isArray(stepResults) || stepResults.length === 0) {
    const emptyState = document.createElement("p")
    emptyState.className = "scenario-step-results-empty"
    emptyState.textContent = "No step results were returned."
    resultsNode.appendChild(emptyState)
    renderDatadogLink(resultsNode, datadogLink)
    return
  }

  for (const step of stepResults) {
    const resultCard = document.createElement("article")
    resultCard.className = `step-run-card step-run-${step.outcome}`

    const header = document.createElement("div")
    header.className = "step-run-header"

    const title = document.createElement("strong")
    title.textContent = step.step_display_name || step.step_id

    const chip = document.createElement("span")
    chip.className = "step-run-chip"
    chip.textContent = step.outcome

    header.append(title, chip)

    const summary = document.createElement("p")
    summary.className = "step-run-summary"
    summary.textContent = step.summary

    const meta = document.createElement("p")
    meta.className = "step-run-meta"
    meta.textContent = `${step.step_id} | ${step.duration_ms} ms`

    resultCard.append(header, summary, meta)

    if (step.meta !== null && step.meta !== undefined) {
      const details = document.createElement("pre")
      details.className = "step-run-details"
      details.textContent = formatJson(step.meta)
      resultCard.appendChild(details)
    }

    resultsNode.appendChild(resultCard)
  }

  renderDatadogLink(resultsNode, datadogLink)
}

function statusMessageForOutcome(outcome, stepResultsLength) {
  if (outcome === "success") {
    return `Completed successfully (${stepResultsLength} step${stepResultsLength === 1 ? "" : "s"}).`
  }
  return "Completed with failures. Review step details."
}

async function runScenario(scenarioName, button) {
  if (runningScenarios.has(scenarioName)) {
    return
  }

  runningScenarios.add(scenarioName)
  button.disabled = true
  button.textContent = "Running..."
  setStatus(scenarioName, "Running scenario...", "running")

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
    renderErrorResult(scenarioName, message)
  } finally {
    runningScenarios.delete(scenarioName)
    button.disabled = false
    button.textContent = "Run scenario"
  }
}

for (const button of runButtons) {
  const scenarioName = button.getAttribute("data-scenario-run")
  if (!scenarioName) {
    continue
  }

  button.addEventListener("click", () => {
    void runScenario(scenarioName, button)
  })
}

# Gemini CLI Sub-Agent Orchestration Demo

This project is a demonstration of a prompt-native sub-agent orchestration system built for the Gemini CLI. It showcases how complex tasks can be delegated to specialized AI agents whose entire lifecycle is managed through CLI commands and filesystem state, without requiring external process management scripts.

## Core Concept: Asynchronous State-via-Filesystem

The fundamental principle of this system is that an agent's task is not a synchronous operation but a **state file on disk** that controls a **background process**. An orchestrator, invoked by user commands, manages the lifecycle of these tasks.

-   **Task Creation**: A task is initiated as a JSON file with a `pending` status.
-   **Execution**: The orchestrator launches the corresponding agent as a background process, updates the task file to `running`, and records the Process ID (PID).
-   **Completion**: The background agent, upon finishing its task, creates a `.done` sentinel file.
-   **Reconciliation**: The orchestrator detects this `.done` file, marks the task as `complete`, and cleans up the sentinel file.

This entire system lives within the `.gemini/agents/` directory, which includes dedicated subdirectories for:
-   `tasks`: Contains the JSON state files for each task and the `.done` sentinel files.
-   `plans`: Holds Markdown files that agents can use for long-term planning.
-   `logs`: Stores the output logs from each agent's background process.
-   `workspace`: A dedicated directory where agents can create, modify, and read files.

## Architecture

The system consists of two main components:

1.  **The Orchestrator**: A set of prompt-driven commands (`/agents:*`) that manage the agent task lifecycle.
2.  **Sub-Agents**: Specialized Gemini CLI extensions, each with a unique "persona" and a constrained set of capabilities (e.g., a `coder-agent` for writing code, a `reviewer-agent` for analyzing it). Each agent is designed to run autonomously in the background and signal its completion.

## Commands

The system is operated through the `/agents:*` command suite.

### `/agents:start <agent_name> "<prompt>"`

Queues a new task for a sub-agent by creating a task file in `.gemini/agents/tasks/` with a `pending` status.

### `/agents:run`

Finds the oldest `pending` task and starts it. The command's prompt generates the necessary shell script to:
1.  Update the task's status to `running`.
2.  Execute the sub-agent as a **background process**.
3.  Capture the agent's **PID** and update the task file with it.

### `/agents:status`

Provides a report of all tasks. Before displaying the status, it performs a **reconciliation step**:
1.  It scans for `running` tasks.
2.  For each one, it checks for a corresponding `.done` file.
3.  If a `.done` file is found, it marks the task as `complete` and removes the sentinel file.

### `/agents:type`

Lists the available agent types (extensions) that can be used.

## Example Workflow: Building a GitHub Repo Viewer

1.  **Queue a Task**: Ask the `coder-agent` to build a simple web application.
    ```bash
    gemini /agents:start coder-agent "in a folder, use html/css/js (nicely designed) to build an app that looks at github.com/pauldatta and is a one-stop view of the repos and what they have been built for (public repos)"
    ```
    **Output**: `Task task_20250726T183100Z created for agent 'coder-agent' and is now pending.`

2.  **Run the Orchestrator**: Execute the next pending task in the background.
    ```bash
    gemini /agents:run
    ```
    **Output**: `Orchestrator started task task_20250726T183100Z (PID: 13539) in the background.`

3.  **Check the Status**: While the agent is running, you can see its status.
    ```bash
    gemini /agents:status
    ```
    **Output**:
    | Task ID | Agent | Status | Created At | PID | Prompt |
    |---|---|---|---|---|---|
    | task_20250726T183100Z | coder-agent | running | 2025-07-26T18:31:00Z | 13539 | in a folder, use html/css/js... |

4.  **Verify Completion**: After the agent has finished, check the status again. The `/agents:status` command will first reconcile the completed task.
    ```bash
    gemini /agents:status
    ```
    **Output**:
    `Task task_20250726T183100Z has been marked as complete.`
    | Task ID | Agent | Status | Created At | PID | Prompt |
    |---|---|---|---|---|---|
    | task_20250726T183100Z | coder-agent | complete | 2025-07-26T18:31:00Z | 13539 | in a folder, use html/css/js... |

At this point, the `coder-agent` has created the application in the `.gemini/agents/workspace/github-repo-viewer/` directory, containing `index.html`, `style.css`, and `script.js`.

---

## Disclaimer

This project is a proof-of-concept experiment.

-   **Inspiration**: The core architecture is inspired by Anthropic's documentation on [Building a Sub-Agent with Claude](https://docs.anthropic.com/en/docs/claude-code/sub-agents).
-   **Roadmap**: A more robust and official agentic feature is on the [Gemini CLI roadmap](https://github.com/google-gemini/gemini-cli/issues/4168).
-   **Security**: This implementation is **not secure for production use**. It relies on the `-y` (`--yolo`) flag, which bypasses important security checks. For any real-world application, you should enable features like checkpointing and sandboxing. For more information, please refer to the [official Gemini CLI documentation](https://github.com/google-gemini/gemini-cli/blob/main/docs/cli/commands.md).
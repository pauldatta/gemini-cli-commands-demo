## 1. Product Requirements Document: Prompt-Driven Sub-Agents

### 1.1. Overview

This document outlines the requirements for a prompt-native sub-agent orchestration system in the Gemini CLI. The system will allow a user to delegate complex tasks to specialized "sub-agents" (which are themselves instances of the Gemini CLI with specific extensions). The entire lifecycle of these agents—creation, task assignment, execution, and status tracking—will be managed through CLI commands and the filesystem, without resorting to external shell scripts for process management.

### 1.2. The Core Concept: State via Filesystem

Instead of launching background processes and tracking their PIDs, the orchestrator will manage state through a structured directory within the user's `.gemini/` folder. A task for a sub-agent is not a "running process" but a "state file" on disk. An orchestrator prompt will read these files, execute the next logical step, and update the state file.

### 1.3. Required Directory Structure

The following directories must be created within the user's project under `.gemini/`:

- **/agents**: The root directory for this feature.
- **/agents/tasks**: Contains the state files for each agent task. This is the "task queue."
- **/agents/plans**: Contains the Markdown plan files that agents use for long-term tracking.
- **/agents/logs**: Contains the output logs from each sub-agent execution.
- **/agents/workspace**: A dedicated directory where agents can create, modify, and read files.

### 1.4. The Sub-Agent "Personas" (Extensions)

Sub-agents are defined as standard Gemini CLI extensions. Their personality, capabilities, and constraints are defined in the extension's prompt. Here are two examples:

**File: `.gemini/extensions/coder-agent.json`**

```json
{
  "name": "coder-agent",
  "version": "1.0.0",
  "contextFileName": "coder-agent-scratchpad.md",
  "prompt": "You are an expert software developer. Your SOLE task is to write clean, efficient, and correct code to satisfy the user's request. You will be given a task and a plan file. First, update the plan with the steps you will take. Then, write the code to a file in the `.gemini/agents/workspace/` directory. When you are finished, output only the absolute path to the file you created."
}
```

**File: `.gemini/extensions/reviewer-agent.json`**

```json
{
  "name": "reviewer-agent",
  "version": "1.0.0",
  "contextFileName": "reviewer-agent-scratchpad.md",
  "prompt": "You are an expert code reviewer. You will be given a file path to review. Your SOLE task is to analyze the code for bugs, style violations, and improvements. Update the agent's plan file with your review and then output 'Review complete.' to finish the task."
}
```

### 1.5. The Orchestration Commands

The entire system is operated through a new `/agent` command namespace.

#### **1.5.1. `/agent:start <agent_name> "<prompt>"`**

This command initiates a new task. It **does not** execute the task directly.

- **Description**: Creates and queues a new task for a sub-agent.
- **Arguments**:
  1.  `agent_name` (string): The name of the extension to use (e.g., `coder-agent`).
  2.  `prompt` (string): The detailed task for the agent.
- **Behavior**: This command is powered by a prompt that performs the following logic:

  1.  Generate a unique task ID (e.g., `task_` + current timestamp).
  2.  Create a state file: `.gemini/agents/tasks/<task_id>.json`.
  3.  Populate the state file with the initial task details.
  4.  Create an empty plan file: `.gemini/agents/plans/<task_id>_plan.md`.
  5.  Output a confirmation to the user.

- **Example `start.toml` command definition:**

  **File:** `.gemini/commands/agent/start.toml`

  ````toml
  description = "Starts and queues a new sub-agent task: /agent:start <agent_name> \"<prompt>\""
  prompt = """
  You are the Orchestrator's setup assistant. Your job is to create the necessary files to queue a new agent task.

  **User Arguments:** `{{args}}`

  **Instructions:**
  1.  Generate a unique Task ID in the format `task_<timestamp>`.
  2.  The first argument is the `agent_name`. The second argument is the `prompt`.
  3.  Create a JSON state file at `.gemini/agents/tasks/<Task_ID>.json`.
  4.  The JSON file's content must be:
      ```json
      {
        "taskId": "<Task_ID>",
        "status": "pending",
        "agent": "{{arg0}}",
        "prompt": "{{arg1}}",
        "planFile": ".gemini/agents/plans/<Task_ID>_plan.md",
        "logFile": ".gemini/agents/logs/<Task_ID>.log",
        "createdAt": "<current_iso_timestamp>"
      }
      ```
  5.  Create an empty plan file at `.gemini/agents/plans/<Task_ID>_plan.md` with the initial title `# Plan for {{arg0}} - {{arg1}}`.
  6.  After creating the files, output a single confirmation line to the user: `Task <Task_ID> created for agent '{{arg0}}' and is now pending.`
  """
  ````

#### **1.5.2. `/agent:run`**

This is the main orchestrator command that executes one pending task.

- **Description**: Finds the oldest pending task, executes it using the appropriate sub-agent, and updates its status.
- **Behavior**: This is the most critical prompt. It scans for a `pending` task, constructs the command to execute it, and then generates a subsequent command to update the task's state file.
- **Example `run.toml` command definition:**

  **File:** `.gemini/commands/agent/run.toml`

  ````toml
  description = "The main agent orchestrator. Finds and runs one pending task."
  prompt = """
  You are the master Orchestrator. Your purpose is to execute the agent task lifecycle.

  **Instructions:**
  1.  Scan the `.gemini/agents/tasks/` directory for task files.
  2.  Find the oldest file with a `"status": "pending"`.
  3.  If no pending tasks exist, output "No pending agent tasks found." and stop.
  4.  If a pending task is found, read its JSON content.
  5.  **Step 1: Mark as Running.** Your first action is to update the task file's status to "running". Construct the command to overwrite the file with the updated status.
  6.  **Step 2: Execute the Agent.** Your second action is to construct the Gemini CLI command to run the sub-agent. The agent's output should be logged. The command format is:
      `gemini -e <agent> -p "Task: <prompt>. Your plan file is at <planFile>. All file I/O must be within the './.gemini/agents/workspace/' directory." >> <logFile> 2>&1`
  7.  **Step 3: Mark as Complete.** Your third action is to update the task file's status to "complete" and add a "completedAt" timestamp.
  8.  You must now generate the shell commands for these three steps in sequence. The user's shell will execute them one by one.

  **Example Output for a task with ID 'task_123'**:
  ```shell
  # Step 1: Mark as running
  echo '{"taskId": "task_123", "status": "running", ...}' > .gemini/agents/tasks/task_123.json

  # Step 2: Execute the agent's task
  gemini -e coder-agent -p "Task: Write a function. Your plan file is at .gemini/agents/plans/task_123_plan.md..." >> .gemini/agents/logs/task_123.log 2>&1

  # Step 3: Mark as complete
  echo '{"taskId": "task_123", "status": "complete", "completedAt": "...", ...}' > .gemini/agents/tasks/task_123.json

  echo "Orchestrator finished task task_123."
  ````

  Now, find the oldest pending task and generate the precise sequence of shell commands to execute it.
  """

  ```

  ```

#### **1.5.3. `/agent:status`**

This command provides a view of all tasks.

- **Description**: Lists all tasks and their current status.
- **Behavior**: The command's prompt instructs the AI to scan the `/agents/tasks` directory, read each JSON file, and format the output as a human-readable table.
- **Example `status.toml` command definition:**

  **File:** `.gemini/commands/agent/status.toml`

  ```toml
  description = "Displays the status of all agent tasks."
  prompt = """
  You are the Orchestrator's status reporter. Your SOLE PURPOSE is to scan the `.gemini/agents/tasks/` directory, parse each JSON file, and present the information in a clean, formatted markdown table.

  The table should have the following columns:
  - Task ID
  - Agent
  - Status
  - Created At
  - Prompt

  Now, generate the report.
  """
  ```

### 1.6. User Workflow Example

1.  **User wants to create a Python script.**

    ```bash
    gemini /agent:start coder-agent "Create a python script in the workspace called 'math.py' that contains a function to add two numbers."
    ```

    - **Output:** `Task task_1699893721 created for agent 'coder-agent' and is now pending.`

2.  **User wants to see the queue.**

    ```bash
    gemini /agent:status
    ```

    - **Output:**
      | Task ID | Agent | Status | Created At | Prompt |
      | ------------------ | ----------- | ------- | ------------------- | ---------------------------------------------- |
      | task_1699893721 | coder-agent | pending | 2025-07-26T00:00:00Z | Create a python script... |

3.  **User runs the orchestrator.**

    ```bash
    gemini /agent:run
    ```

    - **Behind the Scenes:** The `run.toml` prompt generates and executes the shell commands to update the task file to `running`, run the `coder-agent`, and finally update the file to `complete`. The `coder-agent` will have created the file at `.gemini/agents/workspace/math.py`.
    - **Output:** `Orchestrator finished task task_1699893721.`

4.  **User checks the status again.**
    ```bash
    gemini /agent:status
    ```
    - **Output:**
      | Task ID | Agent | Status | Created At | Prompt |
      | ------------------ | ----------- | --------- | ------------------- | ---------------------------------------------- |
      | task_1699893721 | coder-agent | complete | 2025-07-26T00:00:00Z | Create a python script... |

---

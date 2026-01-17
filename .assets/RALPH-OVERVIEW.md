The "Ralph" loop (often called the **Ralph Wiggum Loop**) is a primitive but highly effective architectural pattern for autonomous software engineering, popularized by Geoffrey Huntley around late 2025.

Its central thesis is that **context degradation** is the primary failure mode of long-running agents. Ralph solves this by enforcing a "stateless" runtime where agents live only for a single task cycle, relying entirely on file-system artifacts for memory.

The following system definition describes the core mechanics for an AI to abstract.

### 1. Core Philosophy: The "Goldfish" Memory Model
The Ralph system rejects the idea of a long-running chat session where an agent "remembers" what it did 10 turns ago. Instead, it operates on **fresh instantiation**:
- **Single-Task Lifespan:** An agent is spawned to do exactly one unit of work (a "story" or "ticket"). Once that unit is verified, the agent process is killed.
- **Zero-Shot State:** The next agent starts with zero conversational history. It knows *only* what exists in the file system (code, docs, logs).
- **Infinite Retries:** If an agent fails a task (tests don't pass), the loop simply discards the attempt and spawns a new agent to try again, often with the error log from the previous attempt injected as context.

### 2. The Loop Mechanics
The system is effectively a `while` loop that runs until a "Product Requirements Document" (PRD) is fully satisfied.

**The Algorithm:**
1.  **Read State**: Parse `prd.json` to find the next item marked `status: todo` or `passes: false`.
2.  **Spawn Agent**: Initialize a new AI session (e.g., `llm run`).
3.  **Inject Context**: Feed the agent:
    *   The specific task description.
    *   Current project file tree.
    *   `AGENTS.md` (project-specific "memory" file).
4.  **Execution**: Agent modifies code and writes tests.
5.  **Verification**: The system runs a deterministic check (e.g., `npm test`, `tsc`, or a browser verification script).
    *   *If Pass*: Commit changes to git, update `prd.json` to `passes: true`, append learnings to `AGENTS.md`.
    *   *If Fail*: Revert changes (optional, or keep for debugging), log the failure output, and restart the loop for the same task.
6.  **Termination**: Loop exits only when `prd.json` has all items marked complete.

### 3. Context Management & Artifacts
Since the agent has no memory, the "brain" of the system is externalized into three specific file types. This is the **Persistent Context Layer**.

#### A. The Driver (`prd.json`)
The source of truth for *what* needs to be done. It is a structured list of granular tasks.
```json
{
  "tasks": [
    { "id": 1, "description": "Scaffold Next.js app", "status": "complete" },
    { "id": 2, "description": "Add Tailwind config", "status": "pending" }
  ]
}
```
*Principle*: The agent parses this, picks the first pending ID, executes it, and acts as a function that transforms `pending` -> `complete`.

#### B. The Long-Term Memory (`AGENTS.md` / `progress.txt`)
A cumulative knowledge base written *by* agents *for* future agents.
*   **Write Operation**: After finishing a task, the agent must append a "retrospective" to this file. (e.g., *"Note: This project uses a custom fetch wrapper at `/lib/api.ts`; do not use `axios` directly."*)
*   **Read Operation**: Every new agent reads this file first. It serves as the "onboarding" document that gets smarter over time.
*   **Function**: Prevents regression and context loops where Agent #5 makes the same mistake Agent #2 fixed.

#### C. The Verifier (Test/Typecheck)
The loop relies on **machine-verifiable truth** rather than agent self-reporting.
*   The agent is never asked "Did you finish?"; the system asks the compiler/test runner.
*   **Constraint**: A task is not complete until the system can execute a command that returns exit code 0.

### 4. First Principles Summary
*   **Deterministic Context Allocation**: You don't guess what context an agent needs; you give it the current file state + the specific task. This prevents "context bloat" where the model gets confused by irrelevant history.
*   **Compound Engineering**: The code base improves iteratively. Even if an agent is "dumb," if it can pass a test and write a note in `AGENTS.md`, the *system* gets smarter.
*   **Mechanical Sympathy**: The system assumes LLMs are probabilistic and prone to hallucination. The loop structure forces them to converge on a solution by rejecting invalid states (failing tests) and committing only valid ones.
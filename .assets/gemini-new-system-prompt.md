This is the critical missing link. OSS models, unlike Claude 3.5 Sonnet, do not have "good engineering instincts" baked in via massive RLHF. You have to program those instincts explicitly in the system prompt.

Since you are modifying `ralph-inferno`, we need a system prompt that acts as a **strict governor** over the model's behavior. We are going to strip away the "Anthropic/Claude" identity and replace it with a **"Ralph" Engineering Protocol**.

Here is the distilled, high-performance System Prompt designed for OSS models (Mistral, Qwen, Nemotron) running in your agent loop.

### The "Ralph" System Kernel

This prompt is designed to be modular. You will inject your specific tool definitions (Native or JSON) where indicated, but the **behavioral logic** remains constant.

```markdown
You are Ralph, an elite autonomous software engineer. You are running in a disposable sandbox environment.
Your goal is to complete the provided software specification exactly.

# CORE OPERATING RULES
1.  **NO CONVERSATION**: Do not talk to the user. Do not say "Here is the code" or "I will now do X". Output ONLY thoughts and tool calls.
2.  **STATELESSNESS**: You have no memory of previous sessions. You only know what is in the current file system.
3.  **FULL COMPLETION**: You must complete the entire spec. Do not stop until the verification step passes.

# ENGINEERING STANDARD OPERATING PROCEDURE (SOP)
You must follow this loop for every step. Violating this loop will result in failure.

## PHASE 1: RECONNAISSANCE (Mandatory First Step)
-   **NEVER** write or modify code without reading it first.
-   **Step 1**: Run `ls -R` (or `list_dir`) to map the project structure.
-   **Step 2**: Read the `spec` file (if provided) and any relevant existing code files using `read_file`.
-   **Step 3**: If you are fixing a bug, you MUST create a reproduction script or test case first.

## PHASE 2: PLANNING (The "Thinking" Block)
Before every tool call, you must output a thought block.
-   Analyze the current state.
-   Identify what information is missing.
-   Propose the next immediate step.
-   *Example*: "I need to check `package.json` to see available scripts before running build."

## PHASE 3: EXECUTION (Strict Coding Standards)
-   **NO PLACEHOLDERS**: Never output code with comments like `// ... rest of code`. You must output the FULL, functional file content.
-   **NO TRUNCATION**: Do not truncate functions or classes.
-   **DEPENDENCY CHECK**: Do not use libraries that are not in `package.json`.
-   **ONE FILE AT A TIME**: Do not try to edit 5 files in one turn. Edit one, verify, then move to the next.

## PHASE 4: VERIFICATION
-   After every write, run `npm run build` (or equivalent) to verify syntax.
-   If the build fails, READ the error message, THINK about the cause, and try a different solution. Do not repeat the same failed command.

# TOOL USAGE
{{INSERT_TOOL_DEFINITIONS_HERE}}
```

---

### Integration Guide for `ralph-inferno`

Here is how to adapt the `{{INSERT_TOOL_DEFINITIONS_HERE}}` section based on your two formats.

#### 1. For "Format B" (JSON-in-Text) - *Best for Qwen/DeepSeek/Llama*
OSS models often struggle with complex JSON escaping (e.g., putting a whole Python script inside a JSON string). I recommend a **Block Format** over pure JSON for code writing. It is much more reliable for 7B models.

**Replace the JSON instructions in your current prompt with this:**

```markdown
# TOOL PROTOCOL
You must invoke tools using the following strict XML-like format. Do not use Markdown code blocks for tool calls.

<tool_code>
[TOOL_NAME]
argument1: value
argument2: value
content: 
(multiline content goes here if needed)
[/TOOL_NAME]
</tool_code>

## AVAILABLE TOOLS

1.  **read_file**
    Usage:
    [read_file]
    path: src/main.js
    [/read_file]

2.  **write_file** (WARNING: This overwrites the entire file. Output FULL content.)
    Usage:
    [write_file]
    path: src/utils.js
    content:
    const x = 1;
    function test() { return true; }
    [/write_file]

3.  **run_command**
    Usage:
    [run_command]
    cmd: ls -R
    [/run_command]

4.  **done**
    Usage:
    [done]
    summary: I have completed the login feature.
    [/done]
```

*Why this format?* It avoids the "JSON Parse Error" hell where the model forgets to escape a double quote inside the code it's writing.

#### 2. For "Format A" (Native Tool Calling) - *Ministral/Claude/GPT-4*
Keep your current definition, but inject the **SOP** text from the "Ralph Kernel" above. The Native Tool definition is handled by the API schema, not the text prompt, but the *behavior* (Read before Write) must be in the system prompt.

---

### Specific Answers to your Design Questions

**1. "Examine related files... to plan"**
Yes. You need to be aggressive here.
*   **Add this to the prompt:** "If the spec references 'the auth system', you MUST `search` for 'auth' or list files in `src/auth` before writing a single line of code. Blind coding is forbidden."

**2. Handling "Thinking" (DeepSeek/Qwen vs others)**
Since you are using `ralph-inferno` and might switch models dynamically:
*   **Recommendation:** Force a standard `[THOUGHT]` block in the text response for *all* models.
*   **Why?** Even if Qwen has `<think>`, DeepSeek has `<think>`, and Mistral has nothing, normalizing the output makes your regex parsers in Python much simpler.
*   **Prompt Instruction:** "Start every response with a `[THOUGHT]` block explaining your logic, followed by your Tool Call."

**3. Error Recovery**
OSS models get stuck in loops (trying the same failed command 5 times).
*   **Prompt Instruction:** "If a tool returns an error, you must acknowledge it in your next `[THOUGHT]` block. You are forbidden from issuing the exact same command twice in a row without changing arguments."

### Summary of Changes for `ralph-inferno`
1.  **Adopt the "SOP" section**: This is the engine that drives behavior.
2.  **Explicit "Read-First" Rule**: Make it a "Critical Failure" condition if they don't.
3.  **Switch Format B to Block-Text**: Move away from JSON-for-everything if you are hitting parsing errors with 7B models writing code.
4.  **Normalize Thinking**: Enforce `[THOUGHT]` tags in the system prompt so you can parse reasoning regardless of the underlying model's native capabilities.
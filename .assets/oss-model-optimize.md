# gemini plan for boiling down claude code prompt:

This is a great project. The reason your raw OSS models are failing is that the Claude system prompt relies heavily on **specific training triggers** (like `<antml>` tags) and a massive amount of "pre-fill" context that creates a rigid behavioral sandbox. Raw OSS models (Qwen, Mistral, etc.) need clearer, less proprietary instructions to act as agents.

Here is the high-level breakdown of what we need to strip, what we must keep, and how we need to translate it for models running in LM Studio.

### 1. The Core Identity & Tone (KEEP & SIMPLIFY)
The Claude prompt spends paragraphs on being "face blind" or "empathetic." For an engineering agent, we need to strip that out and enforce the "Senior Engineer" persona found in the `artifacts_info` and `styles_info` sections.

*   **Keep:** "You are an expert software engineer."
*   **Keep:** "Be concise. No fluff. No 'Here is the code'. Just code."
*   **Keep:** "Do not use placeholders. Output complete, functional code."
*   **Translation:** OSS models love to chatter. We need a "Style" section that strictly forbids conversational filler ("Sure! I can help with that...") and prioritizes dense technical output.

### 2. The Tool Protocol (CRITICAL - NEEDS TRANSLATION)
This is the most important part. Claude uses `<antml:function_calls>` because it was fine-tuned to recognize that XML schema.
*   **The Problem:** If you feed Qwen or Mistral `<antml>` tags without fine-tuning, they will hallucinate or write broken XML.
*   **The Fix:** We need to define a **Tool Usage Syntax** compatible with LM Studio.
    *   *Option A (JSON):* Most robust for Qwen/Nemotron.
    *   *Option B (Markdown):* `[TOOL: write_file | path: "script.py"]`.
*   **The Tools:** We need to distill the massive list down to the essentials for an engineering loop:
    1.  `read_file` (FileSystem)
    2.  `write_file` (FileSystem)
    3.  `list_directory` (FileSystem)
    4.  `run_terminal_command` (The "REPL" equivalent)

### 3. The "Thinking" Process (KEEP & ENFORCE)
Claude's prompt has a section called `<thinking_mode>`. This is vital for agents.
*   **Why:** Raw models jump straight to coding. If they don't plan, they write bugs.
*   **Strategy:** We must instruct the model to output a `<thinking>` (or `[THOUGHT]`) block *before* every tool use.
*   **Logic:**
    1.  Analyze user request.
    2.  Check what info is missing.
    3.  Formulate a plan (e.g., "I need to read `main.py` first").
    4.  Emit Tool Call.

### 4. Artifacts vs. Direct Editing (MODIFY)
The Claude prompt uses "Artifacts" (separate windows for code). In a CLI/LM Studio flow, you likely want **direct file manipulation**.
*   **Change:** Instead of "Create an artifact," the instruction should be "Write the file to disk using the `write_file` tool."
*   **Keep:** The instruction about **"Update vs. Rewrite."**
    *   *Rule:* If the file is small, overwrite it. If large, use a search/replace or patch tool (if your agent infrastructure supports it). For simplicity, start with full file overwrites.

### 5. What to Cut (THE BLOAT)
Remove these to save context window tokens and reduce confusion:
*   **Copyright/Safety boilerplate:** (Unless you are releasing this publicly, local models don't need 500 words on not singing "Let It Go").
*   **Google Drive/Calendar/Gmail:** Unless you have specifically built these API hooks into your local python script, these are hallucinations waiting to happen. Remove them.
*   **Browser Storage Restrictions:** Irrelevant for a local backend.
*   **Date/Time complexities:** Simplify to just "Current Date: {{date}}".

---

### The Proposed Structure

Here is how I recommend we structure the new System Prompt. If you agree, I will draft the full text in the next step.

**Section 1: Agent Definition**
"You are a Senior Software Engineer Agent. You operate in a command-line environment. Your goal is to solve coding tasks autonomously."

**Section 2: The Environment (Tools)**
"You have access to the following tools. You must use them to interact with the system. You cannot act otherwise."
*(List tools here in a format your Python script/LM Studio wrapper can parse)*

**Section 3: The Protocol (The Loop)**
"For every user request, you must follow this loop:
1.  **THINK**: Analyze the request and previous tool outputs inside `<thinking>` tags.
2.  **ACT**: Execute a tool command to read files, run code, or write files.
3.  **WAIT**: Wait for the tool output."

**Section 4: Output Rules**
"No conversational filler.
Always write complete code files.
Handle errors gracefully by reading the error output and trying a different approach."

**Section 5: Project Context**
(A placeholder where you inject the `ls -R` or summary of the current repo).

**Shall I proceed with drafting the actual prompt text based on this structure?**


----

# ministral jinja template:
```
{#- Default system message if no system prompt is passed. #}
{%- set default_system_message = '# HOW YOU SHOULD THINK AND ANSWER\n\nFirst draft your thinking process (inner monologue) until you arrive at a response. Format your response using Markdown, and use LaTeX for any mathematical equations. Write both your thoughts and the response in the same language as the input.\n\nYour thinking process must follow the template below:[THINK]Your thoughts or/and draft, like working through an exercise on scratch paper. Be as casual and as long as you want until you are confident to generate the response to the user.[/THINK]Here, provide a self-contained response.' %}

{#- Begin of sequence token. #}
{{- bos_token }}

{#- Handle system prompt if it exists. #}
{#- System prompt supports text content or text and thinking chunks. #}
{%- if messages[0]['role'] == 'system' %}
    {{- '[SYSTEM_PROMPT]' -}}
    {%- if messages[0]['content'] is string %}
        {{- messages[0]['content'] -}}
    {%- else %}        
        {%- for block in messages[0]['content'] %}
            {%- if block['type'] == 'text' %}
                {{- block['text'] }}
            {%- elif block['type'] == 'thinking' %}
                {{- '[THINK]' + block['thinking'] + '[/THINK]' }}
            {%- else %}
                {{- raise_exception('Only text and thinking chunks are supported in system message contents.') }}
            {%- endif %}
        {%- endfor %}
    {%- endif %}
    {{- '[/SYSTEM_PROMPT]' -}}
    {%- set loop_messages = messages[1:] %}
{%- else %}
    {%- set loop_messages = messages %}
    {%- if default_system_message != '' %}
        {{- '[SYSTEM_PROMPT]' + default_system_message + '[/SYSTEM_PROMPT]' }}
    {%- endif %}
{%- endif %}


{#- Tools definition #}
{%- set tools_definition = '' %}
{%- set has_tools = false %}
{%- if tools is defined and tools is not none and tools|length > 0 %}
    {%- set has_tools = true %}
    {%- set tools_definition = '[AVAILABLE_TOOLS]' + (tools| tojson) + '[/AVAILABLE_TOOLS]' %}
    {{- tools_definition }}
{%- endif %}

{#- Checks for alternating user/assistant messages. #}
{%- set ns = namespace(index=0) %}
{%- for message in loop_messages %}
    {%- if message.role == 'user' or (message.role == 'assistant' and (message.tool_calls is not defined or message.tool_calls is none or message.tool_calls | length == 0)) %}
        {%- if (message['role'] == 'user') != (ns.index % 2 == 0) %}
            {{- raise_exception('After the optional system message, conversation roles must alternate user and assistant roles except for tool calls and results.') }}
        {%- endif %}
        {%- set ns.index = ns.index + 1 %}
    {%- endif %}
{%- endfor %}

{#- Handle conversation messages. #}
{%- for message in loop_messages %}

    {#- User messages supports text content or text and image chunks. #}
    {%- if message['role'] == 'user' %}
        {%- if message['content'] is string %}
            {{- '[INST]' + message['content'] + '[/INST]' }}
        {%- elif message['content'] | length > 0 %}
            {{- '[INST]' }}
            {%- if message['content'] | length == 2 %}
                {%- if message['content'][0]['type'] == 'text' and message['content'][1]['type'] in ['image', 'image_url'] %}
                    {%- set blocks = [message['content'][1], message['content'][0]] %}
                {%- else %}
                    {%- set blocks = message['content'] %}
                {%- endif %}
            {%- else %}
                {%- set blocks = message['content'] %}
            {%- endif %}
            {%- for block in blocks %}
                {%- if block['type'] == 'text' %}
                    {{- block['text'] }}
                {%- elif block['type'] in ['image', 'image_url'] %}
                    {{- '[IMG]' }}
                {%- else %}
                    {{- raise_exception('Only text, image and image_url chunks are supported in user message content.') }}
                {%- endif %}
            {%- endfor %}
            {{- '[/INST]' }}
        {%- else %}
            {{- raise_exception('User message must have a string or a list of chunks in content') }}
        {%- endif %}

    {#- Assistant messages supports text content or text, image and thinking chunks. #}
    {%- elif message['role'] == 'assistant' %}
        {%- if (message['content'] is none or message['content'] == '' or message['content']|length == 0) and (message['tool_calls'] is not defined or message['tool_calls'] is none or message['tool_calls']|length == 0) %}
            {{- raise_exception('Assistant message must have a string or a list of chunks in content or a list of tool calls.') }}
        {%- endif %}

        {%- if message['content'] is string and message['content'] != '' %}
            {{- message['content'] }}
        {%- elif message['content'] | length > 0 %}
            {%- for block in message['content'] %}
                {%- if block['type'] == 'text' %}
                    {{- block['text'] }}
                {%- elif block['type'] == 'thinking' %}
                    {{- '[THINK]' + block['thinking'] + '[/THINK]' }}
                {%- else %}
                    {{- raise_exception('Only text and thinking chunks are supported in assistant message contents.') }}
                {%- endif %}
            {%- endfor %}
        {%- endif %}
        
        {%- if message['tool_calls'] is defined and message['tool_calls'] is not none and message['tool_calls']|length > 0 %}
            {%- for tool in message['tool_calls'] %}
                {{- '[TOOL_CALLS]' }}
                {%- set name = tool['function']['name'] %}
                {%- set arguments = tool['function']['arguments'] %}
                {%- if arguments is not string %}
                    {%- set arguments = arguments|tojson %}
                {%- elif arguments == '' %}
                    {%- set arguments = '{}' %}
                {%- endif %}
                {{- name + '[ARGS]' + arguments }}
            {%- endfor %}
        {%- endif %}

        {{- eos_token }}

    {#- Tool messages only supports text content. #}
    {%- elif message['role'] == 'tool' %}
        {{- '[TOOL_RESULTS]' + message['content']|string + '[/TOOL_RESULTS]' }}

    {#- Raise exception for unsupported roles. #}
    {%- else %}
        {{- raise_exception('Only user, assistant and tool roles are supported, got ' + message['role'] + '.') }}
    {%- endif %}
{%- endfor %}
```
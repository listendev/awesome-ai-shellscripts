# ai-git-commit-log - AI-Powered Git Commit Message Generator

## Overview

`ai-git-commit-log` is a Bash script that leverages AI models (via OpenAI or Together AI) to automatically generate Git commit messages based on the provided diff/patch content. It analyzes the changes and produces a commit message that adheres to a strict set of formatting and content rules, aiming for clarity and convention compliance.

The script sends the diff along with detailed instructions to the configured AI provider and then formats the AI's response to ensure it meets the specified commit message structure.

## Prerequisites

- **`bash`**: The script is written in Bash (version 4+ recommended).
- **`curl`**: Used for making API requests to the AI provider.
- **`jq`**: Used for constructing the API request payload and parsing the JSON response.
- **API Key**: You need an API key for your chosen AI provider:
  - OpenAI API Key
  - Together AI API Key

## Installation

1. Download or save the `ai-git-commit-log.sh` script to a file on your system (e.g., `ai-git-commit-log`).
2. Make the script executable:

   ```bash
   chmod +x ai-git-commit-log
   ```

3. Place the script in a directory included in your system's `PATH` environment variable (e.g., `~/bin`, `/usr/local/bin`) for easy access from anywhere in the terminal.

## Configuration

Configuration is managed through environment variables. You can set these in your shell's configuration file (e.g., `.bashrc`, `.zshrc`) or export them in your current session.

**Required:**

- **`AI_PROVIDER`**: Specify the AI service to use.
  - Set to `"openai"` to use OpenAI.
  - Set to `"togetherai"` to use Together AI.
  - **Default**: `"togetherai"`
- **`OPENAI_TOKEN`**: Your OpenAI API key. (Required only if `AI_PROVIDER="openai"`)
- **`TOGETHER_KEY`**: Your Together AI API key. (Required only if `AI_PROVIDER="togetherai"`)

**Optional (Defaults are generally sensible):**

- **`OPENAI_MODEL`**: The specific OpenAI model to use (e.g., `gpt-4o`, `gpt-4-turbo`).
  - Used only if `AI_PROVIDER="openai"`.
  - **Default**: `"gpt-4.5-preview"`
- **`TOGETHER_MODEL`**: The specific Together AI model to use (e.g., `mistralai/Mixtral-8x7B-Instruct-v0.1`, `meta-llama/Llama-3-70b-chat-hf`).
  - Used only if `AI_PROVIDER="togetherai"`.
  - **Default**: `"Qwen/Qwen2.5-Coder-32B-Instruct"`
- **`AI_TEMP`**: The generation temperature (controls randomness). Lower values (e.g., 0.2) make the output more deterministic, higher values (e.g., 0.8) make it more creative.
  - **Default**: `"0.3"`
- **`AI_MAX_TOKENS`**: The maximum number of tokens the AI should generate for the commit message.
  - **Default**: `"4096"`
- **`CURL_TIMEOUT`**: Maximum time in seconds allowed for the `curl` API request.
  - **Default**: `60`
- **`CURL_RETRIES`**: Number of times to retry the `curl` request if it fails.
  - **Default**: `2`
- **`CURL_RETRY_DELAY`**: Delay in seconds between `curl` retries.
  - **Default**: `5`

**Example Configuration Export:**

```bash
# Example for using Together AI (Default Provider)
export TOGETHER_KEY="your_together_ai_api_key"
# Optional: Specify a different model
# export TOGETHER_MODEL="meta-llama/Llama-3-70b-chat-hf"

# --- OR ---

# Example for using OpenAI
# export AI_PROVIDER="openai"
# export OPENAI_TOKEN="your_openai_api_key"
# Optional: Specify a different model
# export OPENAI_MODEL="gpt-4o"
```

## Usage

The script reads the diff/patch content from standard input (`stdin`). You typically pipe the output of `git diff` or `git show` to the script. The generated commit message is printed to standard output (`stdout`).

### Generate message for staged changes

```bash
git diff --cached | ai-git-commit-log
```

### Generate message for the latest commit

```bash
git show HEAD | ai-git-commit-log
```

### Generate message for unstaged changes in the working directory

```bash
git diff HEAD | ai-git-commit-log
```

### Use the generated message directly in `git commit`

This is a common workflow: generate the message for staged changes and immediately use it to commit.

```bash
git diff --cached | ai-git-commit-log | git commit -F -
```

This command pipes the staged diff to `ai-git-commit-log`, which generates the message. The output message is then piped directly to `git commit -F -`, which reads the commit message from standard input.

## Commit Message Format Rules (Enforced by AI Prompt & Script Formatting)

The script instructs the AI to follow these rules strictly. The script also performs some post-processing (like line wrapping and indentation) to help enforce formatting.

**Overall Structure:**

1. A subject line.
2. A single blank line.
3. A detailed message body.

**Subject Line Rules:**

- **Prefix:** MUST start with ONE of the following prefixes, chosen based on the highest priority applicable change type:
  1. `feature:` (New functionality added)
  2. `fix:` (Bug corrected, no new features)
  3. `refactor:` (Code restructuring/improvement, no features or fixes)
  4. `chore:` (Maintenance, build process, tooling, trivial changes)
- **Case:** MUST be entirely lowercase.
- **Length:** MUST NOT exceed 80 characters total (including prefix and space).
- **Tense:** MUST use the imperative mood (e.g., `fix bug`, `add feature`).
- **Punctuation:** MUST NOT end with a period.

**Message Body Rules:**

- **Content Focus:** Provide a technical, detailed description focusing ONLY on the _purpose_, _reasoning_, _causes_, _effects_, and _technical implications_ of the changes. Explain _why_ the change is necessary.
- **Detail Level:** Avoid merely summarizing the diff or listing implementation details (like specific variable/function names) unless essential for understanding the core logic or impact. Do NOT include non-technical summaries or conversational text.
- **Tense:** MUST use the imperative mood consistently (e.g., use 'Introduce X' not 'Introduced X').
- **Line Formatting (CRITICAL):**
  - Wrap ALL text (subject and body) strictly at **80 columns** maximum per line. The script uses `fold -s -w 80` for this.
  - Every line in the message body MUST start with an **uppercase letter**.
  - Every line in the message body MUST end with a **period**.
- **Bullet Points (Use for multiple distinct points):**
  - Use a hyphen (`-`) followed by a single space for bullets.
  - The text immediately following the bullet MUST start with a **lowercase letter**.
  - Each complete bullet point (which might span multiple wrapped lines) MUST end with a **period**.
  - Subsequent lines belonging to the same bullet point MUST be indented to align vertically with the first letter _after_ the hyphen and space. The script attempts to enforce this using `sed`.

**Example Body Snippet (Illustrating Formatting):**

```text
fix: address potential race conditions in the caching layer.

Introduce a fine-grained locking mechanism for cache updates. Previously,
concurrent writes could lead to inconsistent state under heavy load,
causing intermittent data corruption for users.

Modify the cache eviction policy to better handle frequently accessed
items. This prevents premature eviction of critical data points during
peak usage periods.

Update relevant unit tests to cover the new locking behavior and
eviction logic. Ensures regressions are caught early.

- Introduce a fine-grained locking mechanism for cache updates. previously,
  concurrent writes could lead to inconsistent state under heavy load,
  causing intermittent data corruption for users.

- Modify the cache eviction policy to better handle frequently accessed
  items. this prevents premature eviction of critical data points during
  peak usage periods.

- Update relevant unit tests to cover the new locking behavior and
  eviction logic. ensures regressions are caught early.
```

> Note: The example above shows both paragraph and bullet styles as requested from the AI

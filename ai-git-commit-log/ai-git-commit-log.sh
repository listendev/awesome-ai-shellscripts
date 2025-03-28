#!/bin/bash

# Specify the AI provider ("openai" or "togetherai", default: togetherai).
AI_PROVIDER="${AI_PROVIDER:-togetherai}"

# Define the AI model names (defaults are used if corresponding env var is unset).
OPENAI_MODEL="${OPENAI_MODEL:-gpt-4.5-preview}"
TOGETHER_MODEL="${TOGETHER_MODEL:-Qwen/Qwen2.5-Coder-32B-Instruct}"

# Define API endpoints.
OPENAI_API_URL="https://api.openai.com/v1/chat/completions"
TOGETHER_API_URL="https://api.together.xyz/v1/chat/completions"

# Define AI generation parameters.
AI_TEMP="${AI_TEMP:-0.3}"
AI_MAX_TOKENS="${AI_MAX_TOKENS:-4096}"

# Define curl parameters.
CURL_TIMEOUT="${CURL_TIMEOUT:-60}"
CURL_RETRIES="${CURL_RETRIES:-2}"
CURL_RETRY_DELAY="${CURL_RETRY_DELAY:-5}"

# --- Prompt Definition ---
# Define the main prompt instructing the AI on commit message format.
read -r -d '' prompt <<'EOF'
Generate a Git commit log (subject line and detailed body) based on the provided patch.
Adhere STRICTLY and PRECISELY to ALL the following rules:

**Overall Structure:**
1.  A subject line.
2.  A single blank line.
3.  A detailed message body.

**Subject Line Rules:**
*   **Prefix:** MUST start with ONE of following prefixes, by priority (highest first):
    1. `feature`: If any new functionality is added, regardless of other changes.
    2. `fix`: If no features are added, but bugs are corrected.
    3. `refactor`: If no features or fixes, on code restructuring or improvements.
    4. `chore`: If only maintenance, build process, tooling, or trivial change is present.
*   **Case:** MUST be entirely lowercase.
*   **Length:** MUST NOT exceed 80 chars total (including prefix and separating space).
*   **Tense:** MUST use the imperative mood (e.g., 'fix bug', 'add feature').
*   **Punctuation:** MUST NOT end with a period.

**Message Body Rules:**
*   **Content Focus:** Provide a technical, detailed description focusing ONLY on the
    *purpose*, *reasoning*, *causes*, *effects*, and *technical implications* of the
    changes. Explain *why* the change is necessary.
*   **Detail Level:** Avoid summarizing the diff or listing implementation details (like
    specific variable/function names) unless absolutely essential for understanding the
    core logic or impact. Do NOT include non-technical summaries or conversational text.
*   **Tense:** MUST use the imperative mood consistently. Avoid past tense (e.g., use
    'Introduce X' not 'Introduced X').
*   **Line Formatting (CRITICAL):**
    * Wrap ALL text (subject and body) strictly at 80 columns maximum per line.
    * Every line in the message body MUST start with a uppercase letter.
    * Every line in the message body MUST end with a period.
*   **Bullet Points (Use for multiple distinct points):**
    * Use a hyphen (`-`) followed by a single space for bullets.
    * The text immediately following the bullet MUST start with a lowercase letter.
    * Each complete bullet point (which might span multiple wrapped lines) MUST end with
      a period.
    * Subsequent lines belonging to the same bullet point MUST be indented to align
      vertically with the first letter *after* the hyphen and space.

**Example Body Snippet (Illustrating Formatting):**

```text
fix : addresses potential race conditions in the caching layer.

- Introduce a fine-grained locking mechanism for cache updates. Previously,
  concurrent writes could lead to inconsistent state under heavy load,
  causing intermittent data corruption for users.

- Modify the cache eviction policy to better handle frequently accessed
  items. This prevents premature eviction of critical data points during
  peak usage periods.

- Update relevant unit tests to cover the new locking behavior and
  eviction logic. Ensures regressions are caught early.
```

**Final Output:**
Produce ONLY the formatted commit message (subject and body). Do NOT include any
introductory phrases, explanations, apologies, or markdown code fences (like ```) around
the output.

The patch to analyze follows:
EOF

# Define the system prompt for the AI, emphasizing technical expertise.
system_prompt="You are an expert software engineer with mastery over Linux internals, \
systems programming, architecture, and git conventions. Your responses are concise, \
technically accurate, and focused on reasoning and implications, adhering strictly to \
specified formatting rules."

# --- Input Handling ---
# Read patch content from standard input.
input=$(cat)
if [ -z "$input" ]; then
    echo "Error: No patch provided. Pipe a git diff or patch content." >&2
    exit 1
fi

# --- API Configuration ---
# Validate provider and set API key, model, and URL accordingly.
case "$AI_PROVIDER" in
openai)
    if [ -z "$OPENAI_TOKEN" ]; then
        echo "Error: OPENAI_TOKEN env var is not set for AI_PROVIDER=openai." >&2
        exit 1
    fi
    API_KEY="$OPENAI_TOKEN"
    MODEL_NAME="$OPENAI_MODEL"
    API_URL="$OPENAI_API_URL"
    ;;
togetherai)
    if [ -z "$TOGETHER_KEY" ]; then
        echo "Error: TOGETHER_KEY env var is not set for AI_PROVIDER=togetherai." >&2
        exit 1
    fi
    API_KEY="$TOGETHER_KEY"
    MODEL_NAME="$TOGETHER_MODEL"
    API_URL="$TOGETHER_API_URL"
    ;;
*)
    echo "Error: Unsup AI_PROVIDER: '$AI_PROVIDER'. Use 'openai' or 'togetherai'." >&2
    exit 1
    ;;
esac

# --- API Request ---
# Create a temporary file to store the API request payload.
tempfile=$(mktemp)
# Ensure the temporary file is removed upon script exit.
trap 'rm -f "$tempfile"' EXIT

# Combine the main prompt and the input patch.
full_prompt_content="${prompt}\n\n${input}"

# Construct the JSON payload for the API request using jq.
jq -nc \
    --arg model "$MODEL_NAME" \
    --arg temp "$AI_TEMP" \
    --argjson maxtokens "$AI_MAX_TOKENS" \
    --arg system "$system_prompt" \
    --arg user_content "$full_prompt_content" \
    '{
        model: $model,
        temperature: ($temp | tonumber),
        max_tokens: $maxtokens,
        messages: [
            {"role": "system", "content": $system},
            {"role": "user", "content": $user_content}
        ]
    }' >"$tempfile"

# Execute the API call using curl.
response=$(curl -s \
    --max-time "$CURL_TIMEOUT" \
    --retry "$CURL_RETRIES" \
    --retry-delay "$CURL_RETRY_DELAY" \
    --request POST \
    --header "Content-Type: application/json" \
    --header "Authorization: Bearer $API_KEY" \
    --data @"$tempfile" \
    "$API_URL")
curl_exit_code=$?

# Check the exit code of the curl command.
if [ $curl_exit_code -ne 0 ]; then
    echo "Error: curl command failed with exit code $curl_exit_code." >&2
    exit 1
fi

# --- Response Processing ---
# Validate the API response, ensuring it is not empty.
if [ -z "$response" ]; then
    echo "Error: API response was empty. Check API key, endpoint, and network." >&2
    exit 1
fi

# Ensure the API response is valid JSON.
if ! echo "$response" | jq -e . >/dev/null 2>&1; then
    echo "Error: Invalid API response format (not valid JSON)." >&2
    echo "Raw response: $response" >&2
    exit 1
fi

# Check for specific error messages within the API response JSON.
api_error=$(echo "$response" | jq -r '.error.message // empty')
if [ -n "$api_error" ]; then
    echo "Error: API returned: $api_error" >&2
    exit 1
fi

# Extract the generated commit message content from the response.
commit_message=$(echo "$response" | jq -r '.choices[0].message.content // empty')

# Handle cases where message extraction fails despite a valid response structure.
if [ -z "$commit_message" ]; then
    echo "Error: Failed to extract commit message from API response." >&2
    echo "Raw response: $response" >&2
    exit 1
fi

# --- Output Formatting ---
# Format the extracted commit message according to specified rules.
echo "$commit_message" |
    # Remove leading/trailing whitespace from the entire message.
    sed 's/^[[:space:]]*//;s/[[:space:]]*$//' |
    # Ensure exactly one blank line between the subject and body.
    awk '
        NR==1 { print; next }
        NR==2 && NF > 0 { print ""; print; next }
        NR==2 && NF == 0 { print; next }
        { print }
    ' |
    # Wrap lines at 80 columns, breaking at spaces.
    fold -s -w 80 |
    # Indent wrapped lines belonging to bullet points.
    sed -E '/^[[:space:]]*- /{
        :a; n; /^[[:space:]]*$/b; /^[[:space:]]*- /b;
        s/^([[:space:]]*)([^[:space:]])/\1  \2/; ta;
    }' |
    # Remove any trailing blank lines from the final output.
    sed -e :a -e '/^\n*$/{$d;N;ba' -e '}'

exit 0

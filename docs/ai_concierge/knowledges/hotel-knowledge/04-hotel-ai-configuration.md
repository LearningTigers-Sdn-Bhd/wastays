# Hotel AI Configuration

## Per-Hotel Settings

Each hotel configures its own AI concierge through `Hotel` model fields:

- `ai_provider_enabled` (boolean) — enables/disables the AI concierge feature
- `ai_provider_name` (enum) — the LLM provider: `openai`, `claude`, `deepseek`, `gemini`
- `ai_provider_key` (encrypted) — the API key for the selected provider
- `ai_concierge_tone` (enum) — the conversation tone: `basic`, `business`, `cheerful`

## Provider Model Mapping

| Provider | Model |
|----------|-------|
| OpenAI   | gpt-4o-mini |
| Claude   | claude-haiku-4-5 |
| DeepSeek | deepseek-chat |
| Gemini   | gemini-2.5-flash |

## Rate Limiting

- 60 requests/min per API key
- 20 requests/min per IP
- Configured in `config/initializers/rack_attack.rb`

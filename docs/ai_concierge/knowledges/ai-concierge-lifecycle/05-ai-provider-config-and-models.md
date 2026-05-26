# AI Provider Configuration and Models

## Supported Providers

| Provider | Model |
|----------|-------|
| OpenAI   | gpt-4o-mini |
| Claude   | claude-haiku-4-5 |
| DeepSeek | deepseek-chat |
| Gemini   | gemini-2.5-flash |

## Per-Hotel Configuration

Configured via `Hotel` model:
- `ai_provider_enabled` — enables/disables
- `ai_provider_name` — enum: `openai`, `claude`, `deepseek`, `gemini`
- `ai_provider_key` — encrypted API key
- `ai_concierge_tone` — enum: `basic`, `business`, `cheerful`

## Key Integration Points

- `InterpreterAgent` calls the configured provider's API with the hotel's API key
- The provider's model returns structured JSON matching `interpretation_schema.rb`
- Ruby-side deterministic guards validate and sanitize the LLM output before any state mutation
- Rate limiting is applied per API key (60 req/min) and per IP (20 req/min)

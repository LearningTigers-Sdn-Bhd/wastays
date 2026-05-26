# Bad: Provider Errors and Rate Limiting

## AI Provider Errors

1. API key is invalid -> `InterpreterAgent` returns error
2. Provider returns malformed JSON -> Ruby validation catches, fallback returned
3. Provider is down/timeout -> fallback returned
4. Provider returns low-confidence interpretation -> fallback routing

## Rate Limiting

1. 60 req/min per API key exceeded -> `429 Too Many Requests`
2. 20 req/min per IP exceeded -> `429 Too Many Requests`

## Disabled Hotel

1. concierge disabled for hotel -> `422` returned
2. hotel has concierge enabled but provider key is missing -> error handled gracefully

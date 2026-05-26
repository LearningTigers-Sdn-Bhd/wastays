# Bad: Invalid Inputs

## Scenario: Missing identity

1. missing phone and missing `prospect_public_id` returns `422`
2. invalid `prospect_public_id` returns `404`

## Scenario: Failed booking

1. booking URL generation failure does not archive booking as completed
2. booking URL generation failure returns safe fallback

## Scenario: Unresolvable selection

1. ambiguous date reply lists matching room type names but cannot resolve uniquely
2. room-type shorthand like `executive one` asks for option number under that room type
3. room type with multiple options without specifying number -> ambiguity

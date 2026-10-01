# RSpec Error Consolidation & Failure Reporting Strategy

## Motivation
When running the full test suite or large domains (especially using `parallel_tests` / `parallel_rspec`), failure backtraces and assertion errors often interleave across worker processes or scroll past the screen buffer. For both human developers and LLM coding assistants, having a consolidated, structured failure summary at the very end of the test run saves significant context-hunting and debugging time.

---

## Proposed Options

### 1. Enhanced End-of-Run Digest in `bin/test`
[`bin/test`](file:///Users/orsontamin/Code/Jesselton-Pixel/wastays/bin/test) already includes a `print_failure_digest` helper (lines 600–664) that parses the combined test output. It currently caps output at 5 failures and truncates lines to 47 characters.

#### Recommended Enhancements:
- **Uncap the failure list**: Display all failing examples, not just the first 5.
- **Full file & line target**: Output un-truncated paths (e.g. `spec/services/rooms/rename_spec.rb:42`) so they can be clicked or copy-pasted directly into terminal commands.
- **Consolidated rerun commands block**: Print an explicit block at the very end:
  ```bash
  # Rerun all failures in one command:
  bundle exec rspec spec/services/rooms/rename_spec.rb:42 spec/models/hotel_spec.rb:105
  ```
- **Dump failure details to `tmp/last_failures.log`**: Write complete stack traces, failure messages, and diffs to a designated log file so developers or LLM assistants can inspect the entire failure bundle with a single file read.

---

### 2. RSpec Native Status Persistence (`--only-failures`)
Enable example status persistence in [`spec/spec_helper.rb`](file:///Users/orsontamin/Code/Jesselton-Pixel/wastays/spec/spec_helper.rb):
```ruby
RSpec.configure do |config|
  config.example_status_persistence_file_path = "tmp/rspec_examples.txt"
end
```

#### Benefits:
- Tracks passed and failed specs across serial runs.
- Enables:
  ```bash
  bundle exec rspec --only-failures
  bundle exec rspec --next-failure
  ```
- Git-ignored by default under `tmp/`.

---

### 3. Machine-Readable JSON Export
Configure a secondary formatter in [`.rspec`](file:///Users/orsontamin/Code/Jesselton-Pixel/wastays/.rspec) or for CI/local debugging scripts:
```text
--format progress
--format json --out tmp/rspec_failures.json
```
Allows tools and agents to parse JSON structures directly containing exact file paths, lines, messages, and backtrace arrays without parsing CLI text.

# frozen_string_literal: true

# What a live fixture run found, written down.
#
# A live run is an instrument, not a gate: a provider answering badly is the
# measurement, so nothing here raises. Turns are recorded, tokens are scraped
# off the log line UsageLog already writes, and the whole thing lands as one
# markdown file that can be read months later by somebody deciding which model
# a hotel should be on.
module AiConciergeEval
  class LiveReport
    OUTPUT_PATH = Rails.root.join("docs/concierge-provider-evidence.md")

    # USD per million tokens, list price on 2026-08-21. Dated on purpose:
    # there is no pricing anywhere in app/, and a table that pretends to be
    # current is worse than one that says when it was true.
    PRICE_PER_MTOK = {
      "openai" => { input: 0.15, output: 0.60, cached: 0.075 },
      "claude" => { input: 1.00, output: 5.00, cached: 0.10 },
      "gemini" => { input: 0.30, output: 2.50, cached: 0.075 }
    }.freeze

    USAGE_LINE = /AiConcierge::Usage (\w+) provider=(\w+) model=(\S+) in=(\d+) out=(\d+) cached=(\d+)/
    DEGRADED_LINE = /AiConcierge::AgentLoop degraded: (.+)/

    Turn = Struct.new(:provider, :fixture, :group, :index, :guest, :reply, :failure, :elapsed, keyword_init: true) do
      def passed? = failure.nil?
    end

    Usage = Struct.new(:provider, :stage, :model, :input, :output, :cached, keyword_init: true)

    class << self
      def instance = @instance ||= new

      def reset! = @instance = nil
    end

    def initialize
      @turns = []
      @usages = []
      @degradations = Hash.new { |hash, key| hash[key] = [] }
      @providers = []
      @unconfigured = []
    end

    attr_reader :turns, :usages, :degradations, :providers, :unconfigured

    def measuring(providers, unconfigured)
      @providers = providers
      @unconfigured = unconfigured
    end

    def record_turn(**attributes) = turns << Turn.new(**attributes)

    # Both interesting log lines pass through here. Usage is the per-call cost;
    # a degraded line is the difference between "the model answered badly" and
    # "the call never landed", which a reply alone cannot tell you.
    def observe_log(provider, message)
      text = message.to_s

      if (match = USAGE_LINE.match(text))
        usages << Usage.new(
          provider: provider, stage: match[1], model: match[3],
          input: match[4].to_i, output: match[5].to_i, cached: match[6].to_i
        )
      elsif (match = DEGRADED_LINE.match(text))
        degradations[provider] << match[1]
      end
    end

    def any_results? = turns.any?

    def write!(path: OUTPUT_PATH)
      File.write(path, render)
      path
    end

    private

    def render
      [
        header, matrix, fixture_section("Unscripted fixtures", unscripted_fixtures),
        fixture_section("Scripted fixtures", scripted_fixtures, scripted: true),
        failures_section, cost_section, verdict_section
      ].compact.join("\n\n")
    end

    def header
      <<~MARKDOWN.strip
        # Concierge provider evidence

        Phase M. A live run of the conversation fixtures against every
        configured provider — the first time these fixtures have reached a real
        model rather than `ScriptedChat` / `ReferenceClassifier`.

        - **Run on:** #{Time.current.strftime('%Y-%m-%d %H:%M %Z')}
        - **Fixtures:** #{fixture_ids.size} of #{ConversationFixture.all.size}#{coverage_note}
        - **Command:** `CONCIERGE_LIVE=1 bundle exec rspec spec/ai_concierge/eval/live_provider_spec.rb`
        - **Keys:** the platform `AppConfig` rows set at `/admin/integrations`.
        - **Measured:** #{provider_list}
        - **Not measured:** #{unmeasured_list}

        Scripted turns in the fixtures are ignored here by definition: the point
        of a live run is that the model decides. Retrieval stays faked (the
        fixture corpus, scored by word overlap) so what is being measured is the
        model, not the index. The reply stylist and the knowledge synthesis both
        run for real.

        **This is not a gate.** The live spec is excluded from `bin/test` and
        `bin/ci` unless `CONCIERGE_LIVE` is set. A red cell is a finding, not a
        broken build.
      MARKDOWN
    end

    # A run that covered part of the set is worth keeping, but only if the file
    # says which part.
    def coverage_note
      missing = ConversationFixture.all.map(&:id) - fixture_ids
      return "" if missing.empty?

      " — not run: #{missing.map { |id| "`#{id}`" }.join(', ')}"
    end

    def provider_list
      return "none — no provider had a key" if providers.empty?

      providers.map { |provider| "`#{provider.name}` (#{provider.model})" }.join(", ")
    end

    def unmeasured_list
      return "none" if unconfigured.empty?

      "#{unconfigured.map { |name| "`#{name}`" }.join(', ')} — no key in `AppConfig`, so these rows are blank rather than green"
    end

    def matrix
      names = providers.map(&:name)
      rows = fixture_ids.map do |fixture|
        cells = names.map { |name| cell_for(name, fixture) }
        "| #{fixture} | #{cells.join(' | ')} |"
      end

      <<~MARKDOWN.strip
        ## Matrix

        | fixture | #{names.join(' | ')} |
        | --- | #{names.map { '---' }.join(' | ')} |
        #{rows.join("\n")}

        #{totals_line}
      MARKDOWN
    end

    def cell_for(provider, fixture)
      rows = turns.select { |turn| turn.provider == provider && turn.fixture == fixture }
      return "not measured" if rows.empty?

      failed = rows.reject(&:passed?)
      failed.empty? ? "pass" : "**fail** (#{failed.size}/#{rows.size} turns)"
    end

    def totals_line
      providers.map do |provider|
        rows = turns.select { |turn| turn.provider == provider.name }
        passed = fixture_ids.count { |fixture| cell_for(provider.name, fixture) == "pass" }
        "- `#{provider.name}`: #{passed}/#{fixture_ids.size} fixtures clean, " \
          "#{rows.count(&:passed?)}/#{rows.size} turns clean" \
          "#{degraded_note(provider.name)}"
      end.join("\n")
    end

    def degraded_note(provider)
      failures = degradations[provider]
      return "" if failures.empty?

      " — #{failures.size} call(s) never landed: #{failures.uniq.join('; ')}"
    end

    def fixture_section(title, ids, scripted: false)
      return nil if ids.empty?

      note =
        if scripted
          "These fixtures script the model, and five of them script it getting the answer **wrong**. " \
            "A live run cannot honour that scripting, so a result here answers a different question: " \
            "does this provider make the mistake at all? Never read these as regression results."
        else
          "The regression reading: every turn here is a fair test of a provider reading a guest message cold."
        end

      <<~MARKDOWN.strip
        ## #{title} (#{ids.size})

        #{note}

        #{ids.map { |id| "- `#{id}` — #{providers.map { |p| "#{p.name}: #{cell_for(p.name, id)}" }.join(', ')}" }.join("\n")}
      MARKDOWN
    end

    def failures_section
      failed = turns.reject(&:passed?)
      return "## Failing turns\n\nNone." if failed.empty?

      blocks = failed.map do |turn|
        <<~MARKDOWN.strip
          ### `#{turn.provider}` · `#{turn.fixture}` · turn #{turn.index + 1}

          **Guest:** #{turn.guest}

          **Reply:** #{turn.reply.presence || '(none)'}

          ```
          #{turn.failure.to_s.strip}
          ```
        MARKDOWN
      end

      "## Failing turns\n\n#{blocks.join("\n\n")}"
    end

    def cost_section
      rows = providers.map do |provider|
        stats = usage_stats(provider.name)
        latencies = turns.select { |turn| turn.provider == provider.name }.filter_map(&:elapsed).sort
        "| `#{provider.name}` | #{stats[:calls]} | #{stats[:input]} | #{stats[:cached]} | #{stats[:output]} | " \
          "#{percent(stats[:cached], stats[:input])} | $#{format('%.4f', stats[:cost])} | " \
          "#{seconds(latencies[latencies.size / 2])} | #{seconds(latencies.last)} |"
      end

      <<~MARKDOWN.strip
        ## Cost and latency

        Token counts come from the `AiConcierge::Usage` log line Phase J added —
        no new instrumentation. Prices are list, #{PRICE_PER_MTOK.keys.size}-provider
        snapshot taken 2026-08-21.

        | provider | calls | input | cached | output | cached share | cost | p50 turn | slowest turn |
        | --- | --- | --- | --- | --- | --- | --- | --- | --- |
        #{rows.join("\n")}

        Cached share is the live check on Phase J's caching fix: claude writes an
        explicit `cache_control` breakpoint, openai and gemini cache a prefix
        automatically, and all three need the stable prompt to stay above the
        provider's minimum. A share near zero means the prefix stopped earning
        its keep.
      MARKDOWN
    end

    def usage_stats(provider)
      rows = usages.select { |usage| usage.provider == provider }
      price = PRICE_PER_MTOK.fetch(provider)
      input = rows.sum(&:input)
      cached = rows.sum(&:cached)
      output = rows.sum(&:output)

      {
        calls: rows.size, input: input, cached: cached, output: output,
        cost: (((input - cached) * price[:input]) + (cached * price[:cached]) + (output * price[:output])) / 1_000_000.0
      }
    end

    def verdict_section
      <<~MARKDOWN.strip
        ## What this settles

        `Hotel::AI_CONCIERGE_MODEL_NAMES` names one model per provider, and the
        provider is a per-hotel setting — so the table above is three different
        products, not three renderings of one. Read the matrix against the cost
        column before changing that constant; the change itself is one line and
        belongs in its own commit.

        _Written by `spec/support/ai_concierge/live_report.rb`. Re-running the
        live spec overwrites this file._
      MARKDOWN
    end

    def fixture_ids = turns.map(&:fixture).uniq.sort

    def scripted_fixtures = fixture_ids.select { |id| scripted_ids.include?(id) }

    def unscripted_fixtures = fixture_ids - scripted_fixtures

    # A fixture is "scripted" when any of its turns pins what the model said.
    def scripted_ids
      @scripted_ids ||= ConversationFixture.all.select { |fixture| fixture.turns.any?(&:model) }.map(&:id)
    end

    def percent(part, whole) = whole.zero? ? "—" : "#{((part / whole.to_f) * 100).round}%"

    def seconds(value) = value ? "#{format('%.1f', value)}s" : "—"
  end
end

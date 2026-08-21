# frozen_string_literal: true

require "rails_helper"

# Nothing in this file is even loaded without CONCIERGE_LIVE. The tag alone
# would be enough to stop it running, but reading the provider keys happens
# while the file loads -- and an ordinary suite run has no business opening a
# connection to look for them.
return unless ENV["CONCIERGE_LIVE"]

# The same fixtures, against a real provider.
#
# Every other run of these conversations puts ScriptedChat where the model
# stands, which measures the domain and says nothing at all about the model.
# But the provider is a per-hotel setting, so three hotels on three providers
# are running three different products -- and until this ran, no argument about
# which model belongs in Hotel::AI_CONCIERGE_MODEL_NAMES was anything but
# judgement.
#
# It is an instrument, not a gate. A wrong answer is recorded, not raised; the
# example fails only when the harness itself broke. Excluded from every ordinary
# run unless CONCIERGE_LIVE is set, because it costs money and needs a key.
RSpec.describe "AI concierge conversations, live", :ai_concierge_eval, :live_llm do
  # CONCIERGE_LIVE_FIXTURES=timing_to_quote,resume_picks_a_row narrows the run
  # to named fixtures -- a smoke test before spending a full run, or a second
  # look at one the report disagreed with.
  wanted = ENV["CONCIERGE_LIVE_FIXTURES"].to_s.split(",").map(&:strip).reject(&:empty?)
  fixtures = AiConciergeEval::ConversationFixture.all
  fixtures = fixtures.select { |fixture| wanted.include?(fixture.id) } if wanted.any?
  providers = AiConciergeEval::LiveProviders.configured
  report = AiConciergeEval::LiveReport.instance

  before(:all) do
    report.measuring(providers, AiConciergeEval::LiveProviders.unconfigured)
  end

  it "has a provider to measure" do
    expect(providers).not_to be_empty,
      "no provider key found. Set one at /admin/integrations, or pass " \
      "CONCIERGE_LIVE_OPENAI_KEY / CONCIERGE_LIVE_CLAUDE_KEY / CONCIERGE_LIVE_GEMINI_KEY."
  end

  providers.each do |provider|
    # One example per provider: a provider that dies mid-run does not cost the
    # others their results.
    it "answers every fixture on #{provider.name} (#{provider.model})" do
      capture_concierge_logs(provider.name, report)
      runs = Integer(ENV.fetch("CONCIERGE_LIVE_RUNS", 1))
      recorded = 0

      runs.times do
        fixtures.each do |fixture|
          run_fixture(fixture, live: provider) do |turn, outcome, index|
            recorded += 1
            record_live_turn(report, provider, fixture, turn, outcome, index)
          end
        end
      end

      expect(recorded).to be_positive, "no turn reached the provider"
    end
  end

  # Records what happened instead of failing on it. The only thing that can
  # fail this example is the harness: an auth error surfaces as a RubyLLM error
  # inside RunTurn, which shows up as a degraded line in the report.
  def record_live_turn(report, provider, fixture, turn, outcome, index)
    failure = nil

    begin
      assert_fixture_turn(turn, outcome)
    rescue RSpec::Expectations::ExpectationNotMetError => e
      failure = e.message
    end

    report.record_turn(
      provider: provider.name, fixture: fixture.id, group: fixture.group, index: index,
      guest: turn.guest, reply: outcome.reply, failure: failure, elapsed: outcome.elapsed
    )
  end

  # UsageLog already writes what a call cost; this reads its own log line back
  # rather than adding a second way to count the same tokens.
  def capture_concierge_logs(provider, report)
    %i[info warn].each do |level|
      allow(Rails.logger).to receive(level).and_wrap_original do |original, *args, &block|
        report.observe_log(provider, args.first || block&.call)
        original.call(*args, &block)
      end
    end
  end
end

RSpec.configure do |config|
  config.after(:suite) do
    next unless ENV["CONCIERGE_LIVE"]

    report = AiConciergeEval::LiveReport.instance
    next unless report.any_results?

    puts "\nConcierge provider evidence written to #{report.write!}"
  end
end

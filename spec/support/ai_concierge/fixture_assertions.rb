# frozen_string_literal: true

# Every assertion here reads something the conversation actually exposes: what
# the guest was told, and what the thread remembers afterwards.
#
# Nothing asserts on an interpretation hash, a decision symbol or a reply type,
# because none of those survive the rewrite -- and a fixture that asserts on
# today's internals cannot judge tomorrow's implementation. If a promise cannot
# be stated in terms of the reply or the persisted state, it is not a promise
# to the guest.
module AiConciergeEval
  module FixtureAssertions
    SUPPORTED_KEYS = %w[
      intent flow topic pending_question flow_status booking_status
      action_name needs_human_support reply_matches reply_excludes reply_equals
      creates_quote
    ].freeze

    def assert_fixture_turn(turn, outcome)
      expectations = turn.expectations
      unknown = expectations.keys - SUPPORTED_KEYS
      raise ArgumentError, "unknown fixture expectation(s): #{unknown.join(', ')}" if unknown.any?

      expect(outcome.result).to be_success, -> { "turn failed: #{outcome.result.error}" }

      expectations.each { |key, value| assert_fixture_expectation(key, value, outcome) }
    end

    private

    def assert_fixture_expectation(key, value, outcome)
      state = outcome.conversation_state

      case key
      when "intent" then expect(state.last_intent).to eq(value)
      when "flow" then expect(state.active_flow).to eq(value)
      when "topic" then expect(state.active_topic).to eq(value)
      when "pending_question" then expect(state.pending_question).to eq(value)
      when "flow_status" then expect(state.flow_status).to eq(value)
      when "booking_status" then expect(outcome.booking_task["status"]).to eq(value)
      when "action_name" then expect(outcome.payload[:action_name]).to eq(value)
      when "needs_human_support" then expect(outcome.payload[:needs_human_support]).to eq(value)
      when "reply_equals" then expect(outcome.reply).to eq(value)
      when "reply_matches" then Array(value).each { |text| expect(outcome.reply).to include(text) }
      when "reply_excludes" then Array(value).each { |text| expect(outcome.reply).not_to include(text) }
      when "creates_quote" then expect(outcome.quotes_created).to eq(value ? 1 : 0)
      end
    end
  end
end

RSpec.configure do |config|
  config.include AiConciergeEval::FixtureAssertions, :ai_concierge_eval
end

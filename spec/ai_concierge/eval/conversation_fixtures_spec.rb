# frozen_string_literal: true

require "rails_helper"

# The evaluation suite for the concierge.
#
# It existed so Phase F's rewrite was a measurable swap rather than a leap of
# faith: every fixture ran twice, once through the interpreting pipeline and
# once through the tool-calling loop, under the same assertions from the same
# file. The pipeline is gone and the second column with it, so what these
# fixtures now describe is simply how the concierge behaves.
RSpec.describe "AI concierge conversations", :ai_concierge_eval do
  fixtures = AiConciergeEval::ConversationFixture.all

  it "finds fixtures to run" do
    expect(fixtures).not_to be_empty
  end

  fixtures.group_by(&:group).each do |group, group_fixtures|
    describe group do
      group_fixtures.each do |fixture|
        context fixture.id do
          it fixture.description do
            run_fixture(fixture) do |turn, outcome, index|
              aggregate_failures("turn #{index + 1}: #{turn.guest.inspect}") do
                assert_fixture_turn(turn, outcome)
              end
            end
          end
        end
      end
    end
  end
end

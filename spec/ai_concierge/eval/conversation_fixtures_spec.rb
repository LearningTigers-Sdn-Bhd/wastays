# frozen_string_literal: true

require "rails_helper"

# The evaluation suite for the concierge.
#
# It exists so Phase F's rewrite is a measurable swap rather than a leap of
# faith: once the tool-calling loop lands, `:agent_loop` joins PIPELINES here
# and every fixture runs a second time, under the same assertions, from the
# same file. "Green in both columns" is the whole safety argument -- not "green
# with adjusted expectations".
RSpec.describe "AI concierge conversations", :ai_concierge_eval do
  fixtures = AiConciergeEval::ConversationFixture.all

  it "finds fixtures to run" do
    expect(fixtures).not_to be_empty
  end

  fixtures.group_by(&:group).each do |group, group_fixtures|
    describe group do
      group_fixtures.each do |fixture|
        AiConciergeEval::PipelineDriver::PIPELINES.each do |pipeline|
          context "#{fixture.id} [#{pipeline}]" do
            it fixture.description do
              run_fixture(fixture, pipeline: pipeline) do |turn, outcome, index|
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
end

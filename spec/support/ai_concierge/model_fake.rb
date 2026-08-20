# frozen_string_literal: true

# Puts ScriptedChat where the provider stands, for any spec that drives the
# concierge.
#
# The eval harness had this seam to itself while the tool-calling loop was
# behind a flag. Now that the loop is the only pipeline, every spec that used to
# stub `InterpreterAgent#call` needs the same thing -- and stubbing one class
# in one place beats each file reaching into an agent's instance variables to
# decide what the model would have said.
#
# `room_type_names` is the vocabulary ReferenceClassifier matches room mentions
# against; a spec that seeds rooms and does not pass them gets no room_type_name
# slot, which usually shows up as "I couldn't match that room type".
module AiConciergeEval
  module ModelFake
    def stub_concierge_model(room_type_names: [], scripted: {}, interpretation: nil)
      summary = { "room_type_names" => Array(room_type_names) }
      turns = scripted.compact.transform_values { |script| script.deep_symbolize_keys }

      allow_any_instance_of(AiConcierge::Providers::RubyLlmClient).to receive(:chat) do
        ScriptedChat.new(classifier_summary: summary, scripted_turns: turns, interpretation: interpretation)
      end

      stub_concierge_stylist
    end

    # The stylist reaches the provider through the same client as the loop, so
    # without this it would be handed ScriptedChat -- which answers anything it
    # has no tool call for with a greeting, quietly replacing every reply in
    # every spec with "Hello! How can I help you today?".
    #
    # Passing the template through is what a hotel on the default tone gets, so
    # this is the real behaviour rather than a convenience. A spec about the
    # stylist scripts it.
    def stub_concierge_stylist(text: nil, language: nil)
      allow_any_instance_of(AiConcierge::Agents::ReplyStylist).to receive(:call) do |stylist|
        AiConcierge::Agents::ReplyStylist::Styled.new(
          text: text || stylist.send(:template),
          language: language || stylist.send(:thread_language)
        )
      end
    end
  end
end

RSpec.configure do |config|
  config.include AiConciergeEval::ModelFake
end

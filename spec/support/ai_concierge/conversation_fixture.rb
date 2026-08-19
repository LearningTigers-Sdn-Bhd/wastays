# frozen_string_literal: true

# A conversation fixture is a guest talking to the concierge, written down.
#
# The point of the format is that the *same* file runs against both the old
# classify-then-route pipeline and the tool-calling loop that replaces it. The
# expectations belong to the conversation, not to the implementation, so a
# rewrite that keeps its promises leaves every one of these files untouched.
module AiConciergeEval
  class ConversationFixture
    ROOT = Rails.root.join("spec/fixtures/ai_concierge/conversations")

    class Turn
      def initialize(attributes)
        @attributes = attributes.deep_stringify_keys
      end

      def guest = @attributes.fetch("guest")

      # What the model is scripted to do, per pipeline. Omitted means "let
      # ReferenceClassifier decide", which is the common case -- scripting is
      # for turns where the point of the fixture is a specific model choice.
      def model_for(pipeline) = @attributes.dig("model", pipeline.to_s)

      def expectations = @attributes["expect"] || {}
    end

    def self.all
      Dir[ROOT.join("**/*.yml")].sort.map { |path| load_file(path) }
    end

    def self.load_file(path)
      new(YAML.safe_load_file(path, permitted_classes: [ Date ]), path: path)
    end

    def initialize(data, path:)
      @data = data.deep_stringify_keys
      @path = path
    end

    attr_reader :path

    def id = @data.fetch("id")
    def description = @data.fetch("description")

    # The rule or past failure this fixture exists to hold in place. Every
    # InformationIntentGuard regex is one of these -- they are not arbitrary
    # examples, they are bugs somebody already had to fix once.
    def origin = @data["origin"]

    def group = File.basename(File.dirname(path))
    def setup = @data["setup"] || {}
    def turns = Array(@data["turns"]).map { |turn| Turn.new(turn) }
  end
end

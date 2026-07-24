# frozen_string_literal: true

module ObservationDeck
  class InspectorShell < ViewComponent::Base
    def initialize(presenter:, trace_presenters:, configured_provider:)
      @presenter = presenter
      @trace_presenters = trace_presenters
      @configured_provider = configured_provider
    end
  end
end

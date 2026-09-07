# frozen_string_literal: true

module ObservationDeck
  class EventTable < ViewComponent::Base
    def initialize(entries:, pagination:, presenters:, selected_id:, filter_active:)
      @entries = entries
      @pagination = pagination
      @presenters = presenters
      @selected_id = selected_id
      @filter_active = filter_active
    end
  end
end

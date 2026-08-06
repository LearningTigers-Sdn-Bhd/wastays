# frozen_string_literal: true

module ObservationDeck
  class AppBar < ViewComponent::Base
    def initialize(environment:, refresh_path:, exit_path:)
      @environment = environment
      @refresh_path = refresh_path
      @exit_path = exit_path
    end
  end
end

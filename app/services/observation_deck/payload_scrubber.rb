# frozen_string_literal: true

module ObservationDeck
  # Masks secrets in what the Observation Deck stores. Email is deliberately
  # left readable so devs can debug a user's issue. Outbound credentials travel
  # in headers whose names the global filters miss: Channex's `user-api-key`
  # (hyphen, so `_key` does not match) and Basic `Authorization`.
  PayloadScrubber = ActiveSupport::ParameterFilter.new(
    (Rails.application.config.filter_parameters - [ :email ]) +
      [ :credit_card, :cvv, :passport, :ssn, :authorization, /api[-_]?key/i ]
  )
end

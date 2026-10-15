# frozen_string_literal: true

module GuestUI
  # The one tinted card on a portal page: which stay this page is about.
  #
  # Built like the concierge's stay card, so a guest who moves between the two
  # sees the same stay the same way: where, when, how it stands, and the two
  # numbers at the foot. The `actions` slot takes the buttons that act on the
  # whole stay.
  class StaySummary < GuestUI::BaseComponent
    HEADING_LEVELS = [ 1, 2, 3 ].freeze

    renders_one :actions

    def initialize(eyebrow:, property:, dates:, badge:, location: nil, detail: nil,
                   reference: nil, code: nil, heading_level: 2, class: nil)
      @eyebrow = eyebrow
      @property = property
      @dates = dates
      @badge = badge
      @location = location
      @detail = detail
      @reference = reference
      @code = code
      @heading_level = HEADING_LEVELS.include?(heading_level) ? heading_level : 2
      @class = binding.local_variable_get(:class)
    end

    private

    attr_reader :eyebrow, :property, :dates, :badge, :location, :detail, :reference, :code

    def heading_tag = :"h#{@heading_level}"
    def card_class = tw_merge("guest-stay-summary", @class)
  end
end

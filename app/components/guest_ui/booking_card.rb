# frozen_string_literal: true

module GuestUI
  # One booking in a list, with the whole card as the link to it.
  #
  # Nothing inside it is a control. A button inside a link is two targets in
  # one place, and a guest on a keyboard or a screen reader could reach only
  # one of them. What a guest does with a booking lives on its own page.
  class BookingCard < GuestUI::BaseComponent
    def initialize(href:, property:, dates:, badge:, detail: nil, reference: nil, code: nil, class: nil)
      @href = href
      @property = property
      @dates = dates
      @badge = badge
      @detail = detail
      @reference = reference
      @code = code
      @class = binding.local_variable_get(:class)
    end

    private

    attr_reader :href, :property, :dates, :badge, :detail, :reference, :code

    def card_class = tw_merge("guest-booking-card", @class)
  end
end

# frozen_string_literal: true

module GuestUI
  # One booking in a list, with the whole card as the link to it.
  #
  # Nothing inside it is a control. A button inside a link is two targets in
  # one place, and a guest on a keyboard or a screen reader could reach only
  # one of them. What a guest does with a booking lives on its own page.
  #
  # The body ends with the two booking numbers. The footer is the money: what
  # the guest has paid, and what is still outstanding. It is its own band, so
  # its divider runs edge to edge.
  class BookingCard < GuestUI::BaseComponent
    def initialize(href:, property:, dates:, badge:, paid:, detail: nil, reference: nil, code: nil,
                   outstanding: nil, owing: false, class: nil)
      @href = href
      @property = property
      @dates = dates
      @badge = badge
      @paid = paid
      @detail = detail
      @reference = reference
      @code = code
      @outstanding = outstanding
      @owing = owing
      @class = binding.local_variable_get(:class)
    end

    private

    attr_reader :href, :property, :dates, :badge, :paid, :detail, :reference, :code, :outstanding

    def owing? = @owing
    def card_class = tw_merge("guest-booking-card", @class)
  end
end

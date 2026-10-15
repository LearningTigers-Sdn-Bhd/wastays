# frozen_string_literal: true

module GuestUI
  # The two numbers on a booking, in small type at the foot of a card.
  #
  # They are not the same thing. The reference is the number on the
  # property's documents. The code is what the guest types to check in or to
  # open the concierge. Both are shown so a guest can match either one.
  class BookingRefs < GuestUI::BaseComponent
    def initialize(reference:, code:, class: nil)
      @reference = reference
      @code = code
      @class = binding.local_variable_get(:class)
    end

    def render? = @reference.present? || @code.present?

    def call
      tag.dl(class: tw_merge("guest-stay-summary__refs", @class)) do
        safe_join([
          ref("Ref", "Booking reference number", @reference),
          ref("Code", "Booking confirmation code", @code)
        ].compact)
      end
    end

    private

    def ref(short, full, value)
      return if value.blank?

      tag.div(class: "flex items-baseline gap-1.5") do
        safe_join([
          tag.dt { safe_join([ tag.span(short, aria: { hidden: "true" }), tag.span(full, class: "sr-only") ]) },
          tag.dd(value, class: "font-mono text-foreground")
        ])
      end
    end
  end
end

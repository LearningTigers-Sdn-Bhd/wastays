# frozen_string_literal: true

module GuestUI
  # A setting a guest turns on and off: Do Not Disturb today, anything else the
  # room has to agree about tomorrow.
  #
  # It posts and the page comes back with the new state. There is no local
  # state, on purpose. A guest turns Do Not Disturb on, closes the page, and
  # opens it on a second device, and housekeeping reads a third copy on the
  # floor sheet -- a switch that flips in the browser first is a switch that
  # can disagree with the room.
  #
  # The whole row is the control, so the tap target is the setting rather than
  # the 48px track beside it.
  class Switch < GuestUI::BaseComponent
    def initialize(label:, url:, checked: false, hint: nil, method: :patch, confirm: nil,
                   disabled: false, class: nil, **attributes)
      @label = label
      @url = url
      @checked = checked
      @hint = hint
      @method = method
      @confirm = confirm
      @disabled = disabled
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    def call
      helpers.button_to(@url, **button_attributes) { body }
    end

    private

    def body
      safe_join([ text, track ])
    end

    def text
      tag.span(class: "guest-switch__text") do
        safe_join([
          tag.span(@label, class: "guest-switch__label"),
          (tag.span(@hint, class: "guest-switch__hint") if @hint.present?)
        ].compact)
      end
    end

    # Decorative. The state is already on the control as aria-checked, and a
    # screen reader that read the track as well would report it twice.
    def track
      tag.span(class: "guest-switch__track", aria: { hidden: "true" }) do
        tag.span(class: "guest-switch__thumb")
      end
    end

    def button_attributes
      attributes = @attributes.deep_dup
      data = attributes.delete(:data) || {}

      attributes.merge(
        method: @method,
        disabled: @disabled,
        role: "switch",
        class: tw_merge("guest-switch", @class),
        form: { class: "contents" },
        data: data.merge(turbo_confirm: @confirm).compact,
        aria: { checked: @checked.to_s }
      )
    end
  end
end

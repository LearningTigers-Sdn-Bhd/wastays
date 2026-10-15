# frozen_string_literal: true

module GuestUI
  # The box a guest writes a sentence into: a housekeeping request, what is
  # wrong with the room, why they are asking for a refund.
  #
  # It grows with what is written (`field-sizing: content` in the stylesheet),
  # so a guest who types four lines can read all four. `rows` sets where it
  # starts, not where it stops.
  class TextArea < GuestUI::BaseComponent
    def initialize(form:, attribute:, rows: 4, id: nil, described_by: nil, invalid: false,
                   required: false, disabled: false, readonly: false, class: nil, **attributes)
      @form = form
      @attribute = attribute
      @rows = rows
      @id = id
      @described_by = described_by
      @invalid = invalid
      @required = required
      @disabled = disabled
      @readonly = readonly
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    def call
      @form.text_area(@attribute, **html_attributes)
    end

    private

    def html_attributes
      attributes = @attributes.deep_dup
      data = attributes.delete(:data) || {}
      aria = attributes.delete(:aria) || {}
      described_by = [ aria.delete(:describedby) || aria.delete("describedby"), @described_by ].compact.join(" ").presence

      attributes.merge(
        id: @id || attributes.delete(:id) || @form.field_id(@attribute),
        rows: @rows,
        class: tw_merge("guest-text-area", @class),
        required: @required || attributes.delete(:required),
        disabled: @disabled || attributes.delete(:disabled),
        readonly: @readonly || attributes.delete(:readonly),
        data: data,
        aria: aria.merge(describedby: described_by, invalid: (@invalid ? "true" : nil)).compact
      ).compact
    end
  end
end

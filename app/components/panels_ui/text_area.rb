# frozen_string_literal: true

module PanelsUI
  class TextArea < PanelsUI::BaseComponent
    RESIZES = %i[vertical none].freeze
    SIZES = FormField::SIZES

    def initialize(form:, attribute:, rows: 3, id: nil, described_by: nil, invalid: false, required: false,
                   disabled: false, readonly: false, size: :md, resize: :vertical, class: nil, **attributes)
      @form = form
      @attribute = attribute
      @id = id
      @rows = rows.to_i.positive? ? rows : 3
      @described_by = described_by
      @invalid = invalid
      @required = required
      @disabled = disabled
      @readonly = readonly
      @size = SIZES.include?(size) ? size : :md
      @resize = RESIZES.include?(resize) ? resize : :vertical
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
        class: tw_merge("panel-text-area", @class),
        rows: @rows,
        required: @required || attributes.delete(:required),
        disabled: @disabled || attributes.delete(:disabled),
        readonly: @readonly || attributes.delete(:readonly),
        data: data.merge(size: @size, resize: @resize),
        aria: aria.merge(describedby: described_by, invalid: (@invalid ? "true" : nil)).compact
      ).compact
    end
  end
end

# frozen_string_literal: true

module PanelsUI
  class Input < PanelsUI::BaseComponent
    TYPES = {
      text: :text_field,
      email: :email_field,
      password: :password_field,
      number: :number_field,
      search: :search_field,
      tel: :telephone_field,
      url: :url_field,
      date: :date_field,
      datetime_local: :datetime_local_field,
      month: :month_field,
      time: :time_field,
      week: :week_field
    }.freeze
    SIZES = FormField::SIZES

    def initialize(form:, attribute:, type: :text, id: nil, described_by: nil, invalid: false,
                   required: false, disabled: false, readonly: false, size: :md, class: nil, **attributes)
      @form = form
      @attribute = attribute
      @type = TYPES.key?(type) ? type : :text
      @id = id
      @described_by = described_by
      @invalid = invalid
      @required = required
      @disabled = disabled
      @readonly = readonly
      @size = SIZES.include?(size) ? size : :md
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    def call
      @form.public_send(TYPES.fetch(@type), @attribute, **html_attributes)
    end

    private

    def html_attributes
      attributes = @attributes.deep_dup
      data = attributes.delete(:data) || {}
      aria = attributes.delete(:aria) || {}
      described_by = [ aria.delete(:describedby) || aria.delete("describedby"), @described_by ].compact.join(" ").presence

      attributes.merge(
        id: @id || attributes.delete(:id) || @form.field_id(@attribute),
        class: tw_merge("panel-input", @class),
        required: @required || attributes.delete(:required),
        disabled: @disabled || attributes.delete(:disabled),
        readonly: @readonly || attributes.delete(:readonly),
        data: data.merge(size: @size),
        aria: aria.merge(describedby: described_by, invalid: (@invalid ? "true" : nil)).compact
      ).compact
    end
  end
end

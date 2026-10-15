# frozen_string_literal: true

module GuestUI
  # One line of text a guest types.
  #
  # Form-bound rather than tag-based: the field id, the label's `for`, and the
  # ids of the hint and the error all have to agree, and only the form object
  # knows what that id is.
  class Input < GuestUI::BaseComponent
    TYPES = {
      text: :text_field,
      email: :email_field,
      number: :number_field,
      password: :password_field,
      search: :search_field,
      tel: :telephone_field,
      url: :url_field,
      date: :date_field,
      time: :time_field
    }.freeze
    SIZES = %i[sm md lg].freeze
    VARIANTS = %i[default code].freeze

    def initialize(form:, attribute:, type: :text, variant: :default, size: :md, id: nil,
                   described_by: nil, invalid: false, required: false, disabled: false,
                   readonly: false, class: nil, **attributes)
      @form = form
      @attribute = attribute
      @type = TYPES.key?(type) ? type : :text
      @variant = VARIANTS.include?(variant) ? variant : :default
      @size = SIZES.include?(size) ? size : :md
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
      @form.public_send(TYPES.fetch(@type), @attribute, **html_attributes)
    end

    private

    # A confirmation code is not a word, so the phone must not treat it as one.
    # Autocorrect turns a code into a near miss the guest cannot see, and the
    # only report back is that the code was wrong.
    def code_attributes
      return {} unless @variant == :code

      { autocomplete: "off", autocapitalize: "characters", autocorrect: "off", spellcheck: "false" }
    end

    def html_attributes
      attributes = code_attributes.merge(@attributes.deep_dup)
      data = attributes.delete(:data) || {}
      aria = attributes.delete(:aria) || {}
      described_by = [ aria.delete(:describedby) || aria.delete("describedby"), @described_by ].compact.join(" ").presence

      attributes.merge(
        id: @id || attributes.delete(:id) || @form.field_id(@attribute),
        class: tw_merge("guest-input", @class),
        required: @required || attributes.delete(:required),
        disabled: @disabled || attributes.delete(:disabled),
        readonly: @readonly || attributes.delete(:readonly),
        data: data.merge(size: @size, variant: @variant),
        aria: aria.merge(describedby: described_by, invalid: (@invalid ? "true" : nil)).compact
      ).compact
    end
  end
end

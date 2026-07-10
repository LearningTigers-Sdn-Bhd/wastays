# frozen_string_literal: true

module PanelsUI

  # A native <select> control, styled to sit alongside Input and TextArea. Rails'
  # form builder still owns option rendering and selection, so this wraps
  # `form.select` and splits the caller's keywords into the two hashes that helper
  # expects: the choice options (include_blank/prompt/selected) and the HTML
  # attributes (id/class/data/aria/required/...).
  #
  # Pass ready-made choices via `choices:` (anything `form.select` accepts —
  # [label, value] pairs, a Hash, grouped arrays) or yield raw <option> markup as a
  # block for full control.
  class NativeSelect < PanelsUI::BaseComponent
    SIZES = FormField::SIZES

    def initialize(form:, attribute:, choices: nil, id: nil, described_by: nil, invalid: false,
                   required: false, disabled: false, size: :md, include_blank: false, prompt: nil,
                   selected: nil, multiple: false, class: nil, **attributes)
      @form = form
      @attribute = attribute
      @choices = choices
      @id = id
      @described_by = described_by
      @invalid = invalid
      @required = required
      @disabled = disabled
      @size = SIZES.include?(size) ? size : :md
      @include_blank = include_blank
      @prompt = prompt
      @selected = selected
      @multiple = multiple
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    def call
      if content.present?
        @form.select(@attribute, nil, select_options, html_attributes) { content }
      else
        @form.select(@attribute, choices_for_select, select_options, html_attributes)
      end
    end

    private

    # Rails' select helper wants [label, value] pairs; accept the richer
    # { label:, value:, disabled: } hash shape too (matching RadioGroup / SelectMenu)
    # by folding it down to pairs and hoisting disabled values into select_options.
    def choices_for_select
      return @choices unless hash_choices?

      @choices.map do |choice|
        choice.is_a?(Hash) ? [ choice[:label], choice[:value] ] : choice
      end
    end

    def hash_choices?
      @choices.is_a?(Array) && @choices.any? { |choice| choice.is_a?(Hash) && choice.key?(:value) }
    end

    def disabled_choice_values
      return nil unless hash_choices?

      @choices.select { |choice| choice.is_a?(Hash) && choice[:disabled] }.map { |choice| choice[:value] }.presence
    end

    # The ActionView choice options — kept separate from HTML attributes so Rails
    # renders the blank/prompt option and applies the selection. include_blank is
    # only forwarded when truthy: passing `false` explicitly makes Rails raise on a
    # required field (it auto-adds the blank option those need).
    def select_options
      options = {}
      options[:include_blank] = @include_blank if @include_blank
      options[:prompt] = @prompt if @prompt
      options[:selected] = @selected unless @selected.nil?
      options[:disabled] = disabled_choice_values if disabled_choice_values
      options
    end

    def html_attributes
      attributes = @attributes.deep_dup
      data = attributes.delete(:data) || {}
      aria = attributes.delete(:aria) || {}
      described_by = [ aria.delete(:describedby) || aria.delete("describedby"), @described_by ].compact.join(" ").presence

      attributes.merge(
        id: @id || attributes.delete(:id) || @form.field_id(@attribute),
        class: tw_merge("panel-native-select", @class),
        required: @required || attributes.delete(:required),
        disabled: @disabled || attributes.delete(:disabled),
        multiple: @multiple || attributes.delete(:multiple),
        data: data.merge(size: @size),
        aria: aria.merge(describedby: described_by, invalid: (@invalid ? "true" : nil)).compact
      ).compact
    end
  end
end

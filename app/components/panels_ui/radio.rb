# frozen_string_literal: true

module PanelsUI
  # A single radio button with an accessible label, optional description, and
  # whole-card selection. Radios do not emit a hidden companion field and have no
  # mixed state, so they are a thinner ToggleField than the checkbox.
  #
  # A lone radio is rarely useful — prefer RadioGroup, which wires a set of these
  # into an accessible role="radiogroup" and hoists the shared label and error.
  class Radio < PanelsUI::ToggleField
    private

    def css_prefix = "panel-radio"
    def control_noun = "Radio buttons"

    def builder_control
      @form.radio_button(@attribute, @value, builder_options)
    end

    def tag_control
      radio_button_tag(@name, @value, @checked || false, **input_attributes)
    end

    # radio_button has no unchecked/hidden companion, so drop those options.
    def builder_options
      options = input_attributes
      options[:checked] = @checked unless @checked.nil?
      options
    end

    def include_hidden? = false

    # Every radio in a group shares the same attribute/name, so the value must be
    # folded into the id to keep ids (and their label `for`s) unique — matching
    # what Rails' own radio_button / radio_button_tag helpers generate.
    def generated_control_id
      return @form.field_id(@attribute, @value) if builder_source?

      "#{@name}_#{@value}".gsub(/\]\[|\[|\]/, "_").gsub(/[^A-Za-z0-9_:-]/, "_").squeeze("_").delete_suffix("_")
    end
  end
end

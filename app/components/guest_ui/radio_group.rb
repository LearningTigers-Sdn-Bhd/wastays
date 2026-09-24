# frozen_string_literal: true

module GuestUI
  # A small, fixed set of choices, drawn as tiles.
  #
  # The native radio stays in the DOM. It is what makes the group one tab stop
  # with the arrow keys moving inside it, and rebuilding that in script is how
  # a form stops working for a guest on a screen reader. The tile is the
  # `<label>` around it, so the tap target is the whole option rather than a
  # 16px circle beside it.
  #
  # Not a select. DESIGN.md bans a native select in the portal for a styling
  # reason; here the reason is the guest. A select on a phone opens a wheel
  # that hides the form, and these sets are two or three options long.
  class RadioGroup < GuestUI::BaseComponent
    LAYOUTS = %i[inline stacked].freeze

    def initialize(form:, attribute:, choices: [], layout: :inline, id: nil, labelled_by: nil,
                   described_by: nil, invalid: false, required: false, disabled: false,
                   class: nil, **attributes)
      @form = form
      @attribute = attribute
      @choices = normalize(choices)
      @layout = LAYOUTS.include?(layout) ? layout : :inline
      @id = id
      @labelled_by = labelled_by
      @described_by = described_by
      @invalid = invalid
      @required = required
      @disabled = disabled
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    private

    attr_reader :form, :attribute, :choices

    # Takes a list of values, of [label, value] pairs, or of hashes. A bare
    # value is titleized, which is right for a short word a guest reads
    # (savings, current) and wrong for anything longer -- pass a label then.
    # A hash may also carry a hint: one line under the label that helps the
    # guest choose.
    def normalize(choices)
      Array(choices).map do |choice|
        case choice
        when Hash
          { label: choice[:label] || choice["label"], value: choice[:value] || choice["value"],
            hint: choice[:hint] || choice["hint"] }
        when Array then { label: choice.first, value: choice.last }
        else { label: choice.to_s.titleize, value: choice }
        end
      end
    end

    # The first option carries the id the label points at. A radio group has no
    # element of its own to focus, so a label clicked or read out has to land on
    # a radio, and the first one is where the group starts.
    def option_id(index)
      index.zero? ? group_control_id : "#{group_control_id}-#{index}"
    end

    def group_control_id = @id || form.field_id(attribute)

    def group_attributes
      attributes = @attributes.deep_dup
      data = attributes.delete(:data) || {}
      aria = attributes.delete(:aria) || {}

      attributes.merge(
        role: "radiogroup",
        class: tw_merge("guest-radio-group", @class),
        data: data.merge(layout: @layout),
        aria: aria.merge(
          labelledby: @labelled_by,
          describedby: @described_by,
          invalid: (@invalid ? "true" : nil),
          required: (@required ? "true" : nil)
        ).compact
      )
    end

    # The radio names itself with the label alone and reads the hint as its
    # description. Without that, the label that wraps the whole card would
    # read the label and the hint as one long name.
    def radio_attributes(index, hint: false)
      {
        id: option_id(index),
        class: "guest-radio-group__input",
        required: @required,
        disabled: @disabled,
        aria: {
          labelledby: "#{option_id(index)}-label",
          describedby: (hint ? "#{option_id(index)}-hint" : nil)
        }.compact
      }.compact
    end
  end
end

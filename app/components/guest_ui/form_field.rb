# frozen_string_literal: true

module GuestUI
  # A control with its label, and one message under it.
  #
  # It does not draw a `<form>`. Use it inside `form_with`.
  #
  # The field owns the ids. The label's `for`, the control's own id, and the
  # ids the control points at with `aria-describedby` all have to agree, and a
  # page that sets them by hand gets them wrong the first time two forms for
  # one model share a page.
  #
  # Hint or error, never both. A guest reading a field that came back invalid
  # needs the one line that says what to change, and a hint under it is the
  # advice they already followed.
  class FormField < GuestUI::BaseComponent
    SIZES = %i[sm md lg].freeze

    # Tells an error passed as nil apart from one the caller did not mention,
    # which is what lets the field read the model's own errors by default.
    AUTO_ERROR = Object.new.freeze

    renders_one :control, types: {
      input: ->(**attributes) { build(Input, :input, **attributes) },
      text_area: ->(**attributes) { build(TextArea, :text_area, **attributes) },
      radio_group: ->(**attributes) { build_radio_group(**attributes) },
      select: ->(**attributes) { build_select(**attributes) }
    }

    def initialize(form:, attribute:, label: nil, hint: nil, error: AUTO_ERROR, size: :md,
                   required: false, disabled: false, readonly: false, label_hidden: false,
                   id: nil, class: nil, **attributes)
      @form = form
      @attribute = attribute
      @label = label
      @hint = hint
      @error = error
      @size = SIZES.include?(size) ? size : :md
      @required = required
      @disabled = disabled
      @readonly = readonly
      @label_hidden = label_hidden
      @id = id
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    def with_input(...) = with_control_input(...)
    def with_text_area(...) = with_control_text_area(...)
    def with_radio_group(...) = with_control_radio_group(...)
    def with_select(...) = with_control_select(...)

    def control_id = @id || @form.field_id(@attribute)
    def label_id = "#{control_id}-label"
    def hint_id = "#{control_id}-hint"
    def error_id = "#{control_id}-error"

    def error_message
      return @error unless @error.equal?(AUTO_ERROR)
      return unless @form.object.respond_to?(:errors)

      @form.object.errors[@attribute].first
    end

    def invalid? = error_message.present?
    def hint? = @hint.present? && !invalid?

    def before_render
      raise ArgumentError, "Form fields require a control" unless control?
    end

    private

    attr_reader :label, :hint

    def description_ids
      [ (hint_id if hint?), (error_id if invalid?) ].compact.join(" ").presence
    end

    def label_classes
      tw_merge("guest-field__label", (@label_hidden ? "sr-only" : nil))
    end

    def field_attributes
      attributes = @attributes.deep_dup
      data = attributes.delete(:data) || {}

      attributes.merge(
        class: tw_merge("guest-field", @class),
        data: data.merge(size: @size, invalid: invalid?.to_s, disabled: @disabled.to_s)
      )
    end

    # Splatted after the caller's own attributes, so the field stays the
    # authority on what ties a control to its label and its message. `size` is
    # the exception: a control can be sized against what holds it, and dropping
    # the size the caller asked for is worse than letting the two differ.
    def build(component, kind, **attributes)
      @control_kind = kind
      component.new(**attributes, **control_options(attributes))
    end

    # A radio group has no element of its own for a label to point at, so it is
    # given the label's id and names itself with aria-labelledby instead.
    def build_radio_group(**attributes)
      @control_kind = :radio_group
      RadioGroup.new(
        **attributes,
        **control_options(attributes).except(:readonly, :size),
        labelled_by: (label.present? ? label_id : nil)
      )
    end

    # The trigger is a button, and a button takes its name from its text, which
    # is only the value. It is given the label's id, the same as a radio group.
    def build_select(**attributes)
      @control_kind = :select
      Select.new(**attributes, **control_options(attributes), labelled_by: (label.present? ? label_id : nil))
    end

    def control_options(overrides = {})
      {
        form: @form,
        attribute: @attribute,
        id: control_id,
        described_by: description_ids,
        invalid: invalid?,
        required: @required,
        disabled: @disabled,
        readonly: @readonly,
        size: @size
      }.merge(overrides.slice(:size))
    end
  end
end

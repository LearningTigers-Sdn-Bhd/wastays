# frozen_string_literal: true

module PanelsUI
  # A single native checkbox with an accessible label, optional description, and
  # inline validation. Supports whole-card selection and a mixed (indeterminate)
  # state wired to a scoped Stimulus controller. All the label/aria/error
  # scaffolding lives in ToggleField.
  class Checkbox < PanelsUI::ToggleField
    def initialize(indeterminate: false, **options)
      super(**options)
      @indeterminate = indeterminate
    end

    private

    def css_prefix = "panel-checkbox"
    def control_noun = "Checkboxes"

    # Native inputs cannot start indeterminate from markup, so hand the initial
    # state and the clear-on-change behaviour to a scoped Stimulus controller.
    def control_data(data)
      return data unless @indeterminate

      controller = data.delete(:controller) || data.delete("controller")
      action = data.delete(:action) || data.delete("action")
      data.merge(
        controller: [ controller, "panels-ui--checkbox" ].compact.join(" "),
        action: [ action, "change->panels-ui--checkbox#clearIndeterminate" ].compact.join(" "),
        panels_ui__checkbox_indeterminate_value: true,
        panels_ui__checkbox_target: "input"
      )
    end
  end
end

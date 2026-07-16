# frozen_string_literal: true

module PanelsUI
  # A toggle switch. Behaviourally it is a checkbox — same on/off value, hidden
  # companion field, and form/name sourcing — so it inherits all of that from
  # ToggleField. Only the presentation (a track + thumb via panel/switch.css) and
  # the ARIA role differ, giving assistive tech the on/off "switch" semantics.
  class Switch < PanelsUI::ToggleField
    private

    def css_prefix = "panel-switch"
    def control_noun = "Switches"
    def control_role = "switch"
  end
end

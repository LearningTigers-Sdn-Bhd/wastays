# frozen_string_literal: true

module PanelsUI
  # Stacks related form controls (typically PanelsUI::FormField) with consistent
  # vertical spacing. The composition analogue of shadcn's <FieldGroup>: it owns
  # the gap so forms don't sprinkle bare `space-y-*` utilities. Renders nothing
  # semantic on its own — reach for FieldSet when the group needs a legend.
  class FieldGroup < PanelsUI::BaseComponent
    def initialize(class: nil, **attributes)
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    def call
      attributes = @attributes.deep_dup
      tag.div(content, **attributes.merge(class: tw_merge("panel-field-group", @class)))
    end
  end
end

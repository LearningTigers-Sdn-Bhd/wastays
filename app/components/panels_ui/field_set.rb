# frozen_string_literal: true

module PanelsUI
  # Semantic grouping for related fields, mirroring shadcn's <FieldSet>. Renders a
  # native <fieldset> with an optional <legend> and description, then yields to a
  # FieldGroup (or fields directly) for the controls. Use this over FieldGroup when
  # the cluster of fields needs a shared, labelled heading (e.g. "Preferences").
  #
  #   <%= render PanelsUI::FieldSet.new(legend: "Profile", description: "Shown on invoices.") do %>
  #     <%= render PanelsUI::FieldGroup.new do %>
  #       <%= render PanelsUI::FormField.new(...) { |f| f.with_input } %>
  #     <% end %>
  #   <% end %>
  class FieldSet < PanelsUI::BaseComponent
    LEGEND_VARIANTS = %i[legend label].freeze

    def initialize(legend: nil, description: nil, legend_variant: :legend, class: nil, **attributes)
      @legend = legend
      @description = description
      @legend_variant = LEGEND_VARIANTS.include?(legend_variant) ? legend_variant : :legend
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    def call
      attributes = @attributes.deep_dup
      aria = attributes.delete(:aria) || {}
      described_by = [ aria.delete(:describedby) || aria.delete("describedby"), (description_id if @description.present?) ].compact.join(" ").presence

      tag.fieldset(**attributes.merge(class: tw_merge("panel-field-set", @class), aria: aria.merge(describedby: described_by).compact)) do
        safe_join([
          (tag.legend(@legend, class: "panel-field-set__legend", data: { variant: @legend_variant }) if @legend.present?),
          (tag.p(@description, id: description_id, class: "panel-field-set__description") if @description.present?),
          content
        ].compact)
      end
    end

    private

    def description_id
      @description_id ||= "field-set-#{object_id}-description"
    end
  end
end

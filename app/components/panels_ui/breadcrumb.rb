# frozen_string_literal: true

module PanelsUI
  # Renders a breadcrumb trail from the typed `parts` array that the portal
  # navigation helpers already produce (`*_breadcrumb_parts`), so it is a drop-in
  # replacement for `shared/navigation/_breadcrumb_bar` — no helper or controller
  # changes required.
  #
  # Each part is a Hash: `{ type:, label:, path:, siblings:, tab_label:,
  # subtab_label:, hidden: }`. `type` is one of :section, :menu_group, :menu,
  # :breakdown (or nil for appended parts). A part with `siblings:` renders a
  # sibling-menu dropdown; `tab_label:`/`subtab_label:` mark the live labels that
  # PanelsUI::Tabs patches at runtime (see below).
  #
  # ── Tab integration contract ──────────────────────────────────────────────────
  # The root wires the `panels-ui--breadcrumb` controller, which exposes an outlet
  # API (`setTabLabel`, `setSubtabLabel`, `setSubtabSegmentVisible`) for PanelsUI::Tabs
  # to call when the active tab changes. The legacy `data-tabs-breadcrumb-label` /
  # `data-subtabs-breadcrumb-*` attributes are kept alongside the Stimulus targets so
  # the old `tabs`/`subtabs` controllers keep working until they are migrated.
  class Breadcrumb < PanelsUI::BaseComponent
    def initialize(parts:, id: nil, class: nil)
      @parts = Array(parts)
      @id = id || "breadcrumb-#{object_id}"
      @class = binding.local_variable_get(:class)
    end

    def parts? = @parts.any?
    def render? = parts?

    private

    attr_reader :parts

    def last?(index) = index == parts.size - 1

    def menu_id(index) = "#{@id}-menu-#{index}"
    def trigger_id(index) = "#{@id}-trigger-#{index}"

    # Classify a part into a render kind. Mirrors the branching the old
    # `_breadcrumb_bar` partial did inline, kept here so the template stays flat.
    def kind_for(part, index)
      case part[:type]
      when :section, :menu_group
        :static
      when :menu, :breakdown
        return :dropdown if part[:siblings].present?
        return :link if part[:path].present? && !last?(index)

        :current
      else
        return :subtab_current if part[:subtab_label]
        return :tab_current if part[:tab_label]
        return :dropdown if part[:siblings].present?
        return :current if last?(index)

        part[:path].present? ? :link : :static
      end
    end
  end
end

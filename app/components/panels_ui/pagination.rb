# frozen_string_literal: true

module PanelsUI
  class Pagination < PanelsUI::BaseComponent
    def initialize(pagy:, aria_label: "Pagination", hide_when_single_page: false, link_data: {})
      @pagy = pagy
      @aria_label = aria_label
      @hide_when_single_page = hide_when_single_page
      @link_data = link_data
    end

    def render?
      !@hide_when_single_page || @pagy.pages > 1
    end

    private

    def single_page? = @pagy.pages <= 1

    def page_series
      # Pagy 43.6 keeps its series helper protected. Keep this dependency here.
      @pagy.send(:series, slots: 9)
    end

    def control(direction, label, icon)
      target = case direction
      when :first then 1 if @pagy.page > 1
      when :last then @pagy.pages if @pagy.page < @pagy.pages
      else @pagy.public_send(direction)
      end
      target = nil if single_page?
      attributes = {
        class: class_names(
          "panel-button",
          "panel-pagination__control",
          "panel-pagination__#{direction}"
        ),
        aria: { label: label },
        data: {
          slot: "pagination-link",
          pagination_control: direction,
          variant: "ghost",
          size: "icon",
          icon_only: "true",
          state: target ? "available" : "disabled"
        }
      }
      content = helpers.app_icon(icon, aria: { hidden: true })

      if target
        attributes[:data] = @link_data.merge(attributes[:data])
        attributes[:rel] = { previous: "prev", next: "next" }[direction]
        link_to content, @pagy.page_url(target), **attributes.compact
      else
        tag.span content, **attributes.deep_merge(aria: { disabled: true })
      end
    end
  end
end

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

    def control(direction, label, icon, desktop_only: false)
      target = case direction
      when :first then 1 if @pagy.page > 1
      when :last then @pagy.pages if @pagy.page < @pagy.pages
      else @pagy.public_send(direction)
      end
      target = nil if single_page?
      attributes = {
        class: class_names("panel-pagination__item", "panel-pagination__#{direction}", "panel-pagination__desktop": desktop_only),
        aria: { label: label }
      }
      content = helpers.app_icon(icon, class: "size-3.5", aria: { hidden: true })

      if target
        link_to content, @pagy.page_url(target), **attributes, data: @link_data, rel: ({ previous: "prev", next: "next" }[direction])
      else
        tag.span content, **attributes.deep_merge(aria: { disabled: true })
      end
    end
  end
end

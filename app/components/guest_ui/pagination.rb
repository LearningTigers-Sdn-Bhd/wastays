# frozen_string_literal: true

module GuestUI
  # Previous and Next around "Page 2 of 3". A guest pages through a short
  # history on a phone, so a row of page numbers would only crowd the thumb.
  #
  # Draws nothing on a single page.
  class Pagination < GuestUI::BaseComponent
    def initialize(pagy:, class: nil, **attributes)
      @pagy = pagy
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    def render? = @pagy.pages > 1

    def call
      tag.nav(**@attributes, class: tw_merge("guest-pagination", @class), aria: { label: "Pagination" }) do
        safe_join([
          control(@pagy.previous, "Previous", "chevron-left", rel: "prev"),
          tag.span("Page #{@pagy.page} of #{@pagy.pages}", class: "guest-pagination__status", aria: { current: "page" }),
          control(@pagy.next, "Next", "chevron-right", rel: "next")
        ])
      end
    end

    private

    def control(target, label, icon, rel:)
      icon_tag = helpers.app_icon(icon, class: "size-4", aria: { hidden: "true" })
      body = rel == "prev" ? safe_join([ icon_tag, label ]) : safe_join([ label, icon_tag ])
      return tag.span(body, class: "guest-pagination__control", aria: { disabled: "true" }) unless target

      link_to(body, @pagy.page_url(target), class: "guest-pagination__control", rel:)
    end
  end
end

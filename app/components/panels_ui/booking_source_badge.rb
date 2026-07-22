# frozen_string_literal: true

module PanelsUI
  # Renders a booking's source as an uploaded OTA logo, a colored initial badge,
  # or a generic icon (in that priority order), wrapped in a hover/focus tooltip
  # naming the source.
  class BookingSourceBadge < PanelsUI::BaseComponent
    SIZES = {
      sm: { box: "size-5", initial: "text-[9px]", icon: "size-3" },
      md: { box: "size-6", initial: "text-xs", icon: "size-3.5" }
    }.freeze

    def initialize(source:, size: :md, with_tooltip: true, id: nil)
      @presenter = HotelPortal::BookingSourcePresenter.new(source)
      @size = SIZES.key?(size) ? size : :md
      @with_tooltip = with_tooltip
      @id = id
    end

    def call
      content = if @presenter.logo.present?
        logo_badge
      elsif @presenter.ota? && badge_configured?
        initial_badge
      else
        generic_icon
      end
      return content unless @with_tooltip

      render PanelsUI::Tooltip.new(text: "Booking source: #{@presenter.label}", delay: 75, id: @id).with_content(content)
    end

    private

    def badge_configured?
      @presenter.badge_color.present? && @presenter.badge_initial.present?
    end

    def dimensions
      SIZES.fetch(@size)
    end

    def logo_badge
      helpers.image_tag(
        @presenter.logo,
        alt: @presenter.label,
        class: "inline-flex #{dimensions.fetch(:box)} shrink-0 cursor-help rounded-full border border-border object-contain focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring",
        tabindex: "0"
      )
    end

    def initial_badge
      tag.span(
        @presenter.badge_initial,
        class: "inline-flex #{dimensions.fetch(:box)} shrink-0 cursor-help items-center justify-center rounded-full font-bold #{dimensions.fetch(:initial)} focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring",
        style: "background-color: #{@presenter.badge_color}; color: #{@presenter.badge_text_color};",
        tabindex: "0",
        role: "img",
        aria: { label: "Booking source: #{@presenter.label}" }
      )
    end

    def generic_icon
      tag.span(
        class: "inline-flex #{dimensions.fetch(:box)} shrink-0 cursor-help items-center justify-center rounded-md border border-border bg-muted text-muted-foreground focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring",
        tabindex: "0",
        aria: { label: "Booking source: #{@presenter.label}" }
      ) do
        helpers.app_icon(@presenter.icon, class: dimensions.fetch(:icon), aria: { hidden: true })
      end
    end
  end
end

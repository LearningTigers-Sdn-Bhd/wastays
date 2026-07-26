# frozen_string_literal: true

module HotelPortal
  module StayView
    class RoomBookingItem < PanelsUI::BaseComponent
      CONTEXTS = %i[arrival occupied departure].freeze
      SURFACES = %i[standalone joined].freeze
      COMPLETED_STATUSES = %i[completed].freeze
      CHECKED_IN_STATUSES = %i[checked_in review_due_out checkout_required].freeze

      def initialize(segment:, state:, context:, surface: :standalone)
        @segment = segment
        @state = state
        @context = context.to_sym
        @surface = surface.to_sym
      end

      def before_render
        raise ArgumentError, "RoomBookingItem requires a StayView::BookingSegment" unless @segment.is_a?(::StayView::BookingSegment)
        raise ArgumentError, "Unsupported room booking context" unless CONTEXTS.include?(@context)
        raise ArgumentError, "Unsupported room booking surface" unless SURFACES.include?(@surface)
      end

      def call
        attributes = item_attributes.merge(data: { slot: "stay-view-room-booking-item", context: @context })
        if permitted_href
          helpers.link_to(
            permitted_href,
            **attributes.merge(data: helpers.stay_view_booking_action_data.merge(attributes.fetch(:data)))
          ) { item_content }
        else
          tag.div(item_content, **attributes)
        end
      end

      private

      def permitted_href
        return unless @segment.capabilities.view_booking?

        helpers.stay_view_booking_path(
          @segment.booking_id,
          return_to: @state.return_path(helpers.current_hotel),
          source: "stay_view"
        )
      end

      def item_attributes
        surface_classes = if @surface == :joined
          "flex-1 rounded-none bg-card first:rounded-t-md last:rounded-b-md"
        else
          "h-full rounded-md border border-border bg-card"
        end
        {
          class: helpers.tw_merge(
            "group block p-2.5 text-left outline-none transition-colors hover:bg-muted focus-visible:ring-2 focus-visible:ring-ring/30",
            surface_classes
          ),
          aria: { label: "Open booking: #{@segment.accessible_label}" }
        }
      end

      def item_content
        tag.div(class: "space-y-1.5") do
          safe_join([ heading, operational_metadata, boat_metadata, financial_signals ].compact)
        end
      end

      def heading
        tag.div(class: "flex min-w-0 items-start justify-between gap-2") do
          safe_join([
            tag.p(@segment.guest_label, class: "min-w-0 truncate text-sm font-medium text-foreground"),
            heading_indicators
          ])
        end
      end

      def operational_metadata
        tag.p(context_label, class: "text-xs text-muted-foreground tabular-nums")
      end

      def heading_indicators
        tag.div(class: "flex shrink-0 items-center gap-1.5 text-muted-foreground") do
          safe_join([
            source_indicator,
            pax_indicator,
            helpers.app_icon(
              direction_icon,
              class: "size-4 shrink-0 transition-transform group-hover:translate-x-0.5",
              aria: { hidden: true }
            )
          ].compact)
        end
      end

      def source_indicator
        return if @segment.source.blank?

        render PanelsUI::BookingSourceBadge.new(source: @segment.source, size: :sm, id: "#{@segment.dom_id}-source-tooltip")
      end

      def context_label
        case @context
        when :departure
          departure_label
        when :arrival
          arrival_label
        when :occupied
          with_time(
            "#{historical? ? 'Stayed' : 'Stays'} until #{display_check_out.to_fs(:medium)}",
            display_check_out_at
          )
        end
      end

      def departure_label
        return with_time("Departed", @segment.actual_check_out_at || @segment.check_out_at) if historical? || COMPLETED_STATUSES.include?(@segment.status)
        return with_time("Departs today", @segment.check_out_at) if selected_date == operational_date

        with_time("Departs #{selected_date.to_fs(:medium)}", @segment.check_out_at)
      end

      def arrival_label
        return with_time("Arrived", @segment.actual_check_in_at || @segment.check_in_at) if historical? || COMPLETED_STATUSES.include?(@segment.status)
        if selected_date == operational_date
          label = CHECKED_IN_STATUSES.include?(@segment.status) ? "Checked in today" : "Arrives today"
          time = @segment.actual_check_in_at || @segment.check_in_at
          return with_time(label, time)
        end

        with_time("Arrives #{selected_date.to_fs(:medium)}", @segment.check_in_at)
      end

      def display_check_out
        selected_date <= operational_date ? @segment.actual_check_out || @segment.check_out : @segment.check_out
      end

      def display_check_out_at
        selected_date <= operational_date ? @segment.actual_check_out_at || @segment.check_out_at : @segment.check_out_at
      end

      def historical?
        selected_date < operational_date
      end

      def selected_date
        @state.date_window.start_date
      end

      def operational_date
        @state.date_window.operational_date
      end

      def pax_indicator
        return if @segment.adults.nil? && @segment.children.nil?

        label = [
          helpers.pluralize(@segment.adults.to_i, "adult"),
          helpers.pluralize(@segment.children.to_i, "child")
        ].join(", ")
        total = @segment.adults.to_i + @segment.children.to_i

        render PanelsUI::Tooltip.new(
          text: label,
          placement: :top,
          delay: 150,
          id: "#{@segment.dom_id}-pax-tooltip",
          root_class: "shrink-0"
        ) do
          tag.span(
            class: "inline-flex cursor-help items-center gap-1 text-xs tabular-nums",
            aria: { hidden: true },
            data: { slot: "stay-view-room-pax" }
          ) do
            safe_join([
              helpers.app_icon("users", class: "size-3.5", aria: { hidden: true }),
              tag.span(total)
            ])
          end
        end
      end

      def boat_metadata
        time = @context == :arrival ? @segment.boat_in_at : @segment.boat_out_at
        return unless time

        label = @context == :arrival ? "Boat-in" : "Boat-out"
        tag.p("#{label} #{format_time(time)}", class: "text-xs text-muted-foreground tabular-nums")
      end

      def with_time(label, time)
        time ? "#{label} at #{format_time(time)}" : label
      end

      def format_time(time)
        time.strftime("%H:%M")
      end

      def financial_signals
        return if @segment.financial_signals.empty?

        tag.div(class: "flex flex-wrap gap-1") do
          safe_join(@segment.financial_signals.map do |signal|
            render PanelsUI::Badge.new(
              label: signal.label,
              variant: helpers.stay_view_financial_badge_variant(signal),
              size: :sm,
              class: "max-w-full whitespace-normal break-words text-left",
              data: { slot: "stay-view-financial-signal" }
            )
          end)
        end
      end

      def direction_icon
        @context == :departure ? "arrow-left" : "arrow-right"
      end
    end
  end
end

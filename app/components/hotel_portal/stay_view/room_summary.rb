# frozen_string_literal: true

module HotelPortal
  module StayView
    class RoomSummary < PanelsUI::BaseComponent
      STATUS_VARIANTS = ::Rooms::StatusPresentation::BADGE_VARIANTS
      STATUS_ICONS = {
        ready: "circle-check",
        dirty: "spray-can",
        cleaning: "brush-cleaning",
        awaiting_inspection: "search-check",
        inspection_failed: "shield-x",
        out_of_service: "construction",
        unknown: "circle-question-mark"
      }.freeze

      LAYOUTS = %i[inline split_controls].freeze

      def initialize(
        room:, state: nil, actions: [], show_identity: true, show_amenities: true, layout: :inline, class: nil, **attributes
      )
        @room = room
        @state = state
        @actions = actions
        @show_identity = show_identity
        @show_amenities = show_amenities
        @layout = LAYOUTS.include?(layout.to_sym) ? layout.to_sym : :inline
        @class = binding.local_variable_get(:class)
        @attributes = attributes
      end

      def before_render
        raise ArgumentError, "RoomSummary requires a StayView::RoomRow" unless @room.is_a?(::StayView::RoomRow)
      end

      def call
        tag.div(**summary_attributes) do
          @layout == :split_controls ? split_controls_row : identity_row
        end
      end

      def identity_row
        tag.div(class: "flex w-full min-w-0 items-center justify-between gap-2") do
          safe_join([ identity, controls ].compact)
        end
      end

      def split_controls_row
        tag.div(class: "flex w-full min-w-0 items-center justify-between gap-2") do
          safe_join([
            amenity_badges || tag.span,
            tag.div(class: "flex min-w-0 shrink-0 items-center justify-end gap-1") do
              safe_join([
                status_control,
                render(OperationalIndicators.new(room: @room, state: @state, order: %i[dnd priority housekeeping]))
              ].compact)
            end
          ])
        end
      end

      def identity
        return unless @show_identity

        tag.span(@room.room_number, class: "shrink-0 text-sm font-semibold text-foreground")
      end

      def controls
        width = @show_identity ? "shrink-0" : "w-full"
        tag.div(class: tw_merge("flex min-w-0 flex-wrap items-center justify-end gap-1", width)) do
          safe_join([ operational_indicators, status_control, amenity_badges, actions_menu ].compact)
        end
      end

      private

      def summary_attributes
        attributes = @attributes.deep_dup
        data = attributes.delete(:data) || attributes.delete("data") || {}

        attributes.merge(
          class: tw_merge("flex h-full min-w-0 items-center px-3 py-1", @class, attributes.delete(:class)),
          data: data.merge(slot: "stay-view-room-summary", layout: @layout)
        )
      end

      def status_control
        status = @room.current_physical_status || :unknown
        items = @state ? helpers.stay_view_status_menu_actions(@room, @state) : []

        items.any? ? status_menu(status, items) : status_popover(status)
      end

      def status_menu(status, items)
        label = status.to_s.humanize
        render PanelsUI::DropdownMenu.new(
          id: "#{@room.dom_id}-status",
          placement: :bottom_end,
          class: "max-h-64 w-56 overflow-y-auto"
        ) do |menu|
          menu.with_trigger(variant: :ghost, size: :icon_xs, aria_label: status_menu_label(label)) do
            status_badge(status)
          end
          menu.with_header { status_menu_header(label) } if status == :inspection_failed && @room.status_note.present?
          items.each do |item|
            menu.with_item(href: item.fetch(:href), data: item.fetch(:data, {})) do
              safe_join([
                helpers.app_icon(STATUS_ICONS.fetch(item.fetch(:value).to_sym, STATUS_ICONS[:unknown]), class: "size-4", aria: { hidden: true }),
                tag.span(item.fetch(:label)),
                (tag.span("Current", class: "ml-auto text-xs text-muted-foreground") if item[:current])
              ].compact)
            end
          end
        end
      end

      def status_menu_label(label)
        details = @room.current_physical_status == :inspection_failed ? @room.status_note.presence : nil
        [ "Room status: #{label}", details, "change" ].compact.join(" — ")
      end

      def status_menu_header(label)
        tag.div(class: "space-y-1 text-left") do
          safe_join([
            tag.p(label, class: "text-sm font-semibold text-foreground"),
            tag.p("Inspection reason", class: "text-xs text-muted-foreground"),
            tag.p(@room.status_note, class: "break-words text-sm text-foreground")
          ])
        end
      end

      def status_popover(status)
        label = status.to_s.humanize

        render PanelsUI::Popover.new(
          id: "#{@room.dom_id}-status",
          placement: :bottom_end,
          trigger_on: :hover,
          close_delay: 120,
          class: "w-44 p-3"
        ) do |popover|
          popover.with_trigger(
            unstyled: true,
            aria_label: "Room status: #{label}",
            class: "inline-flex rounded-full"
          ) do
            status_badge(status)
          end
          tag.div(class: "text-left") do
            safe_join([
              tag.p("Room status", class: "text-xs text-muted-foreground"),
              tag.p(label, class: "mt-1 text-sm font-semibold text-foreground"),
              status_note(status)
            ].compact)
          end
        end
      end

      def status_note(status)
        return unless status == :inspection_failed && @room.status_note.present?

        tag.p(@room.status_note, class: "mt-2 break-words text-sm text-foreground")
      end

      def status_badge(status)
        render PanelsUI::Badge.new(
          variant: STATUS_VARIANTS.fetch(status, :neutral),
          size: :sm,
          shape: :circular,
          aria: { hidden: true }
        ) do
          helpers.app_icon(STATUS_ICONS.fetch(status, STATUS_ICONS[:unknown]), class: "size-3", aria: { hidden: true })
        end
      end

      def operational_indicators
        render OperationalIndicators.new(room: @room, state: @state)
      end

      # Restriction-only amenities: flag the rooms that do not allow smoking or
      # pets and stay quiet when they are permitted.
      def amenity_badges
        return unless @show_amenities

        badges = [
          (amenity_badge(label: "No pets", icon: "ban", key: :pets) unless @room.pets_allowed),
          (amenity_badge(label: "No smoking", icon: "cigarette-off", key: :smoking) unless @room.smoking_allowed)
        ].compact
        return if badges.empty?

        tag.div(safe_join(badges), class: "flex min-w-0 items-center gap-1", aria: { label: "Room amenities" })
      end

      def amenity_badge(label:, icon:, key:)
        render PanelsUI::Tooltip.new(text: label, id: "#{@room.dom_id}-#{key}-tooltip") do
          render PanelsUI::Badge.new(
            variant: :outline,
            size: :sm,
            shape: :circular,
            class: "shrink-0",
            role: "img",
            tabindex: 0,
            aria: { label: label }
          ) do
            helpers.app_icon(icon, class: "size-3", aria: { hidden: true })
          end
        end
      end

      def actions_menu
        return if @actions.empty?

        render PanelsUI::DropdownMenu.new(id: "#{@room.dom_id}-actions", placement: :bottom_end, class: "max-h-80 overflow-y-auto") do |menu|
          menu.with_trigger(variant: :ghost, size: :icon_xs, aria_label: "Actions for room #{@room.room_number}") do
            helpers.app_icon("ellipsis-vertical", class: "size-4", aria: { hidden: true })
          end
          @actions.each { |action| render_menu_action(menu, action) }
        end
      end

      def render_menu_action(menu, action)
        if action[:children]
          menu.with_submenu(
            label: action.fetch(:label),
            id: action[:id],
            variant: action.fetch(:variant, :default),
            disabled: action.fetch(:disabled, false),
            class: action[:class]
          ) do |submenu|
            action.fetch(:children).each { |child| render_menu_action(submenu, child) }
          end
        else
          menu.with_item(
            href: action.fetch(:href),
            variant: action.fetch(:variant, :default),
            data: action.fetch(:data, {})
          ) do
            safe_join([
              helpers.app_icon(action.fetch(:icon), class: "size-4", aria: { hidden: true }),
              tag.span(action.fetch(:label))
            ])
          end
        end
      end
    end
  end
end

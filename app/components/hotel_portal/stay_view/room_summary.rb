# frozen_string_literal: true

module HotelPortal
  module StayView
    class RoomSummary < PanelsUI::BaseComponent
      STATUS_VARIANTS = {
        ready: :success,
        dirty: :warning,
        cleaning: :info,
        awaiting_inspection: :info,
        inspection_failed: :destructive,
        out_of_service: :destructive
      }.freeze
      STATUS_ICONS = {
        ready: "circle-check",
        dirty: "spray-can",
        cleaning: "brush-cleaning",
        awaiting_inspection: "search-check",
        inspection_failed: "shield-x",
        out_of_service: "construction",
        unknown: "circle-question-mark"
      }.freeze

      def initialize(room:, actions: [], show_identity: true, show_amenities: true, class: nil, **attributes)
        @room = room
        @actions = actions
        @show_identity = show_identity
        @show_amenities = show_amenities
        @class = binding.local_variable_get(:class)
        @attributes = attributes
      end

      def before_render
        raise ArgumentError, "RoomSummary requires a StayView::RoomRow" unless @room.is_a?(::StayView::RoomRow)
      end

      def call
        tag.div(**summary_attributes) do
          identity_row
        end
      end

      def identity_row
        tag.div(class: "flex w-full min-w-0 items-center justify-between gap-2") do
          safe_join([ identity, controls ].compact)
        end
      end

      def identity
        return unless @show_identity

        tag.span(@room.room_number, class: "shrink-0 text-sm font-semibold text-foreground")
      end

      def controls
        tag.div(class: "flex shrink-0 items-center gap-1") do
          safe_join([ amenity_badges, operational_indicators, status_popover, actions_menu ].compact)
        end
      end

      private

      def summary_attributes
        attributes = @attributes.deep_dup
        data = attributes.delete(:data) || attributes.delete("data") || {}

        attributes.merge(
          class: tw_merge("flex h-full min-w-0 items-center px-3 py-1.5", @class, attributes.delete(:class)),
          data: data.merge(slot: "stay-view-room-summary")
        )
      end

      def status_popover
        status = @room.current_physical_status || :unknown
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
            render PanelsUI::Badge.new(
              variant: STATUS_VARIANTS.fetch(status, :neutral),
              size: :sm,
              shape: :rounded,
              aria: { hidden: true }
            ) do
              helpers.app_icon(STATUS_ICONS.fetch(status, STATUS_ICONS[:unknown]), class: "size-3", aria: { hidden: true })
            end
          end
          tag.div(class: "text-left") do
            safe_join([
              tag.p("Room status", class: "text-xs text-muted-foreground"),
              tag.p(label, class: "mt-1 text-sm font-semibold text-foreground")
            ])
          end
        end
      end

      def operational_indicators
        render OperationalIndicators.new(room: @room)
      end

      def amenity_badges
        return unless @show_amenities

        tag.div(class: "flex min-w-0 items-center gap-1", aria: { label: "Room amenities" }) do
          safe_join([
            amenity_badge(
              label: @room.smoking_allowed ? "Smoking" : "No smoking",
              icon: @room.smoking_allowed ? "cigarette" : "cigarette-off",
              key: :smoking
            ),
            amenity_badge(
              label: @room.pets_allowed ? "Pets" : "No pets",
              icon: @room.pets_allowed ? "paw-print" : "ban",
              key: :pets
            )
          ])
        end
      end

      def amenity_badge(label:, icon:, key:)
        render PanelsUI::Tooltip.new(text: label, id: "#{@room.dom_id}-#{key}-tooltip") do
          render PanelsUI::Badge.new(
            variant: :outline,
            size: :sm,
            shape: :rounded,
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

        render PanelsUI::DropdownMenu.new(id: "#{@room.dom_id}-actions", placement: :bottom_end) do |menu|
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

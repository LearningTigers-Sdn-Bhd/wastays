# frozen_string_literal: true

module HotelPortal
  class RequestsBoardPresenter
    attr_reader :board_columns, :board_counts, :current_hotel, :date_window

    def initialize(board_columns:, board_counts:, current_hotel:, view_context:, date_window:, older_open_counts: {})
      @board_columns = board_columns
      @board_counts = board_counts
      @current_hotel = current_hotel
      @view_context = view_context
      @date_window = date_window
      @older_open_counts = older_open_counts
    end

    # Outstanding work the date range is leaving out. The completed column has
    # none by definition: what it shows has already been finished.
    def older_open_count(bucket_key)
      @older_open_counts[bucket_key].to_i
    end

    def older_open?(bucket_key)
      older_open_count(bucket_key).positive?
    end

    def widenable?
      !date_window.widest?
    end

    def widen_path
      @view_context.requests_board_path_for(date_window.widest)
    end

    def window_label
      @view_context.request_window_label(date_window)
    end

    def previous_window_path
      @view_context.requests_board_path_for(date_window.previous)
    end

    def next_window_path
      @view_context.requests_board_path_for(date_window.next)
    end

    def today_window_path
      @view_context.requests_board_path_for(date_window.at_today)
    end

    def columns
      [
        { key: :housekeeping, label: "Housekeeping", accent_class: "border-t-blue-500", draggable: true },
        { key: :complaint, label: "Complaints", accent_class: "border-t-rose-500", draggable: true },
        { key: :completed, label: "Recently Completed", accent_class: "border-t-green-500", draggable: true },
        { key: :checkout, label: "Checkout Requests", accent_class: "border-t-amber-500", draggable: false }
      ]
    end

    def column_count_badge_class(column)
      column[:key] == :checkout ? "bg-amber-100 text-amber-700" : "bg-slate-100 text-slate-700"
    end

    def column_request_label(column)
      column[:key] == :checkout ? "pending request" : "active request"
    end

    def kind_badge_class(card)
      case card[:kind]
      when "housekeeping" then "border-blue-100 bg-blue-50 text-blue-700"
      when "checkout" then "border-amber-100 bg-amber-50 text-amber-700"
      else "border-rose-100 bg-rose-50 text-rose-700"
      end
    end

    def target_status(card)
      card[:kind] == "housekeeping" ? "completed" : "resolved"
    end

    def pagination_param_name(bucket_key)
      :"#{bucket_key}_page"
    end

    def page_params
      @view_context.request.query_parameters.except(:housekeeping_page, :complaint_page, :completed_page, :checkout_page)
    end

    def card_actionable?(card)
      card[:update_url].present? || card[:complete_url].present? || card[:archive_url].present?
    end

    def card_shows_room_number?(card)
      card[:kind] == "checkout" && card[:room_number].present?
    end

    def card_token_label(card)
      label = card[:booking_token].to_s
      label += " · Room #{card[:room_number]}" if card_shows_room_number?(card)
      label
    end

    def formatted_requested_at(card)
      helpers.display_housekeeping_datetime(card[:requested_at])
    end

    def formatted_completed_at(card)
      helpers.display_housekeeping_datetime(card[:completed_at])
    end

    def completed_at?(card)
      card[:completed_at].present?
    end

    def internal_notes_for(card)
      Array(card[:internal_notes])
    end

    def internal_notes?(card)
      internal_notes_for(card).any?
    end

    # Returns the action button config for a card, or nil if no action is available.
    # Each config is a hash with :type, :url, :params, :css, :icon, :label, :title
    def card_action(card, bucket_key)
      if bucket_key == :completed && card[:archive_url].present?
        archive_action(card)
      elsif card[:complete_url].present? && !card[:update_url].present?
        complete_action(card)
      elsif card[:kind] == "housekeeping" && card[:status] == "pending"
        dispatch_action(card)
      elsif card[:status] == "pending"
        dispatch_action(card)
      elsif card[:update_url].present?
        done_action(card)
      end
    end

    private

    def helpers
      ApplicationController.helpers
    end

    def archive_action(card)
      {
        url: card[:archive_url],
        params: {},
        css: "flex size-8 items-center justify-center rounded-lg border border-slate-200 bg-white text-slate-400 " \
             "shadow-sm transition-all hover:border-slate-900 hover:text-slate-900",
        icon: "cube",
        icon_opts: { library: "phosphor", variant: "regular" },
        label: nil,
        title: "Archive Request"
      }
    end

    def dispatch_action(card)
      {
        url: card[:update_url],
        params: { status: "new" },
        css: "flex items-center gap-1.5 rounded-lg border border-blue-100 bg-blue-50 px-3 py-1.5 " \
             "text-[10px] font-black uppercase tracking-wider text-blue-700 shadow-sm transition-all " \
             "hover:border-blue-500 hover:bg-blue-500 hover:text-white",
        icon: "arrow-right",
        icon_opts: { stroke_width: 3 },
        label: "Dispatch",
        title: "Dispatch Request"
      }
    end

    def done_action(card)
      {
        url: card[:update_url],
        params: { status: target_status(card) },
        css: "flex items-center gap-1.5 rounded-lg border border-emerald-100 bg-emerald-50 px-3 py-1.5 " \
             "text-[10px] font-black uppercase tracking-wider text-emerald-700 shadow-sm transition-all " \
             "hover:border-emerald-500 hover:bg-emerald-500 hover:text-white",
        icon: "check",
        icon_opts: { stroke_width: 3 },
        label: "Done",
        title: "Mark as Done"
      }
    end

    def complete_action(card)
      {
        url: card[:complete_url],
        params: {},
        css: "flex items-center gap-1.5 rounded-lg border border-emerald-100 bg-emerald-50 px-3 py-1.5 " \
             "text-[10px] font-black uppercase tracking-wider text-emerald-700 shadow-sm transition-all " \
             "hover:border-emerald-500 hover:bg-emerald-500 hover:text-white",
        icon: "check",
        icon_opts: { stroke_width: 3 },
        label: "Complete",
        title: "Complete Request"
      }
    end
  end
end

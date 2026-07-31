# frozen_string_literal: true

module HotelPortal
  class RequestsBoardPresenter
    attr_reader :board_counts, :current_hotel, :date_window, :pages

    def initialize(pages:, board_counts:, current_hotel:, view_context:, date_window:, older_open_counts: {})
      @pages = pages
      @board_counts = board_counts
      @current_hotel = current_hotel
      @view_context = view_context
      @date_window = date_window
      @older_open_counts = older_open_counts
    end

    def page_for(bucket_key)
      pages.fetch(bucket_key)
    end

    def board_columns
      @board_columns ||= pages.transform_values(&:cards)
    end

    # A frame is named for the cursor it was asked for, so the page that arrives
    # replaces the placeholder that asked for it. The first page has no cursor.
    def column_frame_id(bucket_key, cursor)
      suffix = cursor ? Digest::SHA256.hexdigest(cursor.to_param).first(12) : "start"

      "requests_column_#{bucket_key}_#{suffix}"
    end

    # The rest of a column, carrying the filters the column was read under.
    def column_page_path(bucket_key, cursor)
      @view_context.hotel_requests_column_path(
        current_hotel,
        bucket_key,
        @view_context.preserved_request_filters.merge(date_window.query_params).merge(cursor: cursor.to_param)
      )
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

    # Where a card opens its detail sheet.
    def detail_path(card)
      @view_context.hotel_request_action_show_request_path(
        current_hotel,
        kind: card[:kind],
        request_id: card[:request_id]
      )
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
        { key: :checkout, label: "Checkout Requests", accent_class: "border-t-amber-500", draggable: false },
        # Nothing is dragged into the archive: a request is put away by being
        # archived, which is a button on the card and not a place on the board.
        { key: :archived, label: "Archived", accent_class: "border-t-slate-400", draggable: false }
      ]
    end

    def column_count_badge_class(column)
      column[:key] == :checkout ? "bg-amber-100 text-amber-700" : "bg-slate-100 text-slate-700"
    end

    # What a column counts. The completed column counts work that is finished,
    # so calling those "active" was telling the reader the opposite.
    def column_request_label(column)
      case column[:key]
      when :checkout then "pending request"
      when :completed then "completed request"
      when :archived then "archived request"
      else "active request"
      end
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

    def card_actionable?(card)
      card[:update_url].present? || card[:complete_url].present? || card[:archive_url].present?
    end

    # Dragging a card is how its status is changed, so a card with no status to
    # change is not one to drag. Without this an archived card -- and a completed
    # checkout, which has never had an update_url -- is draggable at an empty
    # URL, and the drop fails silently.
    def card_draggable?(card, bucket_key)
      return false if bucket_key == :archived

      card[:update_url].present?
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
      if bucket_key == :archived
        restore_action(card)
      elsif bucket_key == :completed && card[:archive_url].present?
        archive_action(card)
      elsif card[:complete_url].present? && !card[:update_url].present?
        complete_action(card)
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

    # An archived card's archive_url is the way back out of the archive, which is
    # the only thing left to do with it from here.
    def restore_action(card)
      {
        url: card[:archive_url],
        params: {},
        css: "flex items-center gap-1.5 rounded-lg border border-border bg-card px-3 py-1.5 " \
             "text-[10px] font-black uppercase tracking-wider text-muted-foreground shadow-sm " \
             "transition-all hover:border-border-interactive hover:text-foreground",
        icon: "rotate-ccw",
        icon_opts: { stroke_width: 3 },
        label: "Restore",
        title: "Restore Request"
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

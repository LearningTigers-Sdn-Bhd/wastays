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
        kind: card.record_kind,
        request_id: card.request_id
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

    def columns = Requests::Column.all

    # Where a card is dropped, and what the board calls that column.
    def move_path(column)
      @view_context.hotel_requests_move_path(current_hotel, to: column.to_param)
    end

    def kind_badge_class(card)
      case card.kind
      when "housekeeping" then "border-blue-100 bg-blue-50 text-blue-700"
      when "checkout" then "border-amber-100 bg-amber-50 text-amber-700"
      else "border-rose-100 bg-rose-50 text-rose-700"
      end
    end

    # Where a card's status is written, and where a checkout is completed. These
    # were built into the card by the board and the archive, which meant two
    # services holding url_helpers to do a view's job. The card carries what it
    # is; the path is made here, from that.
    def status_path(card)
      @view_context.hotel_request_status_path(
        current_hotel,
        kind: card.record_kind,
        request_id: card.request_id
      )
    end

    def complete_checkout_path(card)
      @view_context.hotel_complete_checkout_request_path(current_hotel, card.request_id)
    end

    # A card can be dragged when some other lane would take it. Asked of the
    # lanes, because they are what decides: gating this on the card having an
    # update_url instead made a completed checkout undraggable, since completing
    # a checkout has an endpoint of its own and no status URL to show for it.
    def card_draggable?(card, column)
      Requests::Column.all.any? { |other| other.key != column.key && other.accepts?(card.kind) }
    end

    def card_shows_room_number?(card)
      card.kind == "checkout" && card.room_number.present?
    end

    def card_token_label(card)
      label = card.booking_token.to_s
      label += " · Room #{card.room_number}" if card_shows_room_number?(card)
      label
    end

    def formatted_requested_at(card)
      helpers.display_housekeeping_datetime(card.requested_at)
    end

    def formatted_completed_at(card)
      helpers.display_housekeeping_datetime(card.completed_at)
    end

    def completed_at?(card)
      card.completed_at.present?
    end

    def internal_notes_for(card)
      card.internal_notes_list
    end

    def internal_notes?(card)
      internal_notes_for(card).any?
    end

    # Returns the action button config for a card, or nil if no action is available.
    # Each config is a hash with :type, :url, :params, :css, :icon, :label, :title
    def card_action(card, column)
      if column.archives?
        restore_action(card)
      elsif column.key == :completed
        archive_action(card)
      elsif card.checkout_record?
        complete_action(card)
      elsif card.status == "pending"
        dispatch_action(card)
      elsif card.status_updatable?
        done_action(card)
      end
    end

    private

    def helpers
      ApplicationController.helpers
    end

    def archive_action(card)
      {
        url: move_path(Requests::Column.find(:archived)),
        params: move_params(card),
        css: "flex size-8 items-center justify-center rounded-lg border border-slate-200 bg-white text-slate-400 " \
             "shadow-sm transition-all hover:border-slate-900 hover:text-slate-900",
        icon: "cube",
        icon_opts: { library: "phosphor", variant: "regular" },
        label: nil,
        title: "Archive Request"
      }
    end

    # Carrying a card back out of the archive is the only thing left to do with
    # it from here.
    def restore_action(card)
      {
        url: move_path(restored_column_for(card)),
        params: move_params(card),
        css: "flex items-center gap-1.5 rounded-lg border border-border bg-card px-3 py-1.5 " \
             "text-[10px] font-black uppercase tracking-wider text-muted-foreground shadow-sm " \
             "transition-all hover:border-border-interactive hover:text-foreground",
        icon: "rotate-ccw",
        icon_opts: { stroke_width: 3 },
        label: "Restore",
        title: "Restore Request"
      }
    end

    def move_params(card)
      { kind: card.record_kind, display_kind: card.kind, request_id: card.request_id }
    end

    # Where restoring puts a card back: the lane it would have been in had it
    # never been archived.
    def restored_column_for(card)
      Requests::Column.for_record(kind: card.kind, status: card.status, archived: false)
    end

    def dispatch_action(card)
      {
        url: status_path(card),
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
        url: status_path(card),
        params: { status: card.kind == "complaint" ? "resolved" : "completed" },
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
        url: complete_checkout_path(card),
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

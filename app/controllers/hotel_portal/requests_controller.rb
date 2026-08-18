# frozen_string_literal: true

module HotelPortal
  class RequestsController < HotelPortal::BaseController
    include HotelPortal::HousekeepingTaskAuthorization

    # Housekeeping and checkout work is advanced from the housekeeping board as
    # well, and reaching it from here must not be the way around the line that
    # board draws. Complaints are nobody's to hold, so they are not guarded.
    ADVANCE_GUARDED_KINDS = %w[housekeeping checkout].freeze

    before_action :authorize_manage_requests!
    before_action -> { require_feature!("task_assignment_minibar_log") }
    before_action :authorize_advance_request!, only: [ :update_status ]

    rescue_from ActiveRecord::RecordNotFound, with: :handle_record_not_found

    def index
      @board = ::HotelPortal::RequestsBoard.new(current_hotel, params)
      @presenter = board_presenter(@board, pages: @board.pages)
    end

    # The rest of one column, from where it got to. Rendered into the lazy frame
    # that asked for it rather than as a page of its own.
    def column
      @column = ::HotelPortal::Requests::Column.find(params[:column])
      raise ActiveRecord::RecordNotFound if @column.nil?

      @board = ::HotelPortal::RequestsBoard.new(current_hotel, params)
      @cursor = ::HotelPortal::Requests::Cursor.parse(params[:cursor])
      @page = @board.page(@column.key, cursor: @cursor)
      @presenter = board_presenter(@board, pages: { @column.key => @page })

      render :column, layout: false
    end

    # A card put in a lane, however it was asked for. The board answers with the
    # two lanes that changed rather than a redirect: a redirect can only refill
    # the one frame the request came from, and a move always leaves one lane and
    # joins another.
    def move
      result = ::HotelPortal::Requests::Move.new(
        hotel: current_hotel,
        kind: params[:kind],
        display_kind: params[:display_kind],
        request_id: params[:request_id],
        to: params[:to]
      ).call

      @board = ::HotelPortal::RequestsBoard.new(current_hotel, board_filters)
      @presenter = board_presenter(@board, pages: @board.pages)
      @result = result

      respond_to do |format|
        format.turbo_stream do
          if result.ok?
            render :move, status: :ok
          else
            render turbo_stream: toast_stream(
              "Request cannot be moved",
              type: :error,
              description: result.error
            ), status: :unprocessable_entity
          end
        end
        format.html do
          redirect_to board_path_with_filters,
                      notice: (result.ok? ? "Request moved." : nil),
                      alert: result.error
        end
        format.json { render json: { ok: result.ok?, error: result.error }, status: (result.ok? ? :ok : :unprocessable_entity) }
      end
    end

    def cancel_request
      updater = ::HotelPortal::Requests::CancelUpdater.new(
        hotel: current_hotel,
        kind: params[:kind],
        request_id: params[:request_id],
        note: params[:internal_note]
      )

      if (request = updater.call)
        redirect_target = safe_redirect_target(hotel_requests_path(current_hotel))
        respond_to do |format|
          format.html { redirect_to redirect_target, notice: "Request cancelled successfully." }
          format.json { render json: { ok: true, status: request.status, archived_at: request.archived_at } }
        end
      else
        redirect_target = safe_redirect_target(hotel_requests_path(current_hotel))
        respond_to do |format|
          format.html { redirect_to redirect_target, alert: "Cancellation note is required." }
          format.json { render json: { ok: false }, status: :unprocessable_entity }
        end
      end
    end

    # This board hands out guest requests; room work belongs to the housekeeping
    # board and is reached through its own routes.
    def update_status
      updater = ::HotelPortal::Requests::StatusUpdater.new(
        hotel: current_hotel,
        kind: params[:kind],
        request_id: params[:request_id],
        status: params[:status],
        work_contexts: %w[guest_request]
      )

      redirect_target = safe_redirect_target(hotel_requests_path(current_hotel))
      if (request = updater.call)
        respond_to do |format|
          format.turbo_stream do
            @board = ::HotelPortal::RequestsBoard.new(current_hotel, board_filters)
            @presenter = board_presenter(@board, pages: @board.pages)
            from_column = ::HotelPortal::Requests::Column.for_record(kind: params[:kind], status: "pending", archived: false)
            to_column = ::HotelPortal::Requests::Column.for_record(kind: params[:kind], status: request.status, archived: request.archived_at.present?)
            @result = ::HotelPortal::Requests::Move::Result.new(request: request, from_column: from_column, to_column: to_column)
            render :move, status: :ok
          end
          format.html { redirect_to redirect_target, notice: "Request updated successfully." }
          format.json { render json: { ok: true, status: request.status } }
        end
      else
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: toast_stream("Failed to update request", type: :error), status: :unprocessable_entity
          end
          format.html { redirect_to redirect_target, alert: "Failed to update request." }
          format.json { render json: { ok: false }, status: :unprocessable_entity }
        end
      end
    end

    def archive_request
      updater = ::HotelPortal::Requests::ArchiveUpdater.new(
        hotel: current_hotel,
        kind: params[:kind],
        request_id: params[:request_id]
      )

      redirect_target = safe_redirect_target(hotel_requests_path(current_hotel))
      if (request = updater.archive)
        respond_to do |format|
          format.html { redirect_to redirect_target, notice: "Request archived successfully." }
          format.json { render json: { ok: true, archived_at: request.archived_at } }
        end
      else
        respond_to do |format|
          format.html { redirect_to redirect_target, alert: "Failed to archive request." }
          format.json { render json: { ok: false }, status: :unprocessable_entity }
        end
      end
    end

    def unarchive_request
      updater = ::HotelPortal::Requests::ArchiveUpdater.new(
        hotel: current_hotel,
        kind: params[:kind],
        request_id: params[:request_id]
      )

      redirect_target = safe_redirect_target(hotel_requests_path(current_hotel))
      if (request = updater.unarchive)
        respond_to do |format|
          format.html { redirect_to redirect_target, notice: "Request restored successfully." }
          format.json { render json: { ok: true, archived_at: request.archived_at } }
        end
      else
        respond_to do |format|
          format.html { redirect_to redirect_target, alert: "Failed to restore request." }
          format.json { render json: { ok: false }, status: :unprocessable_entity }
        end
      end
    end

    private

    # What the board was being read under when the card was moved, so the lanes
    # sent back are the ones the operator is actually looking at rather than an
    # unfiltered board.
    def board_filters
      params.permit(
        *::HotelPortal::RequestsHelper::PRESERVED_FILTER_KEYS,
        :date, :days,
        **::HotelPortal::RequestsHelper::PRESERVED_ARRAY_FILTER_KEYS
      ).to_h.symbolize_keys
    end

    def board_path_with_filters
      hotel_requests_path(current_hotel, board_filters.compact_blank)
    end

    def board_presenter(board, pages:)
      ::HotelPortal::RequestsBoardPresenter.new(
        pages: pages,
        board_counts: board.board_counts,
        current_hotel: current_hotel,
        view_context: view_context,
        date_window: board.date_window,
        selected_lanes: Array(params[:lanes])
      )
    end

    def handle_record_not_found
      redirect_target = safe_redirect_target(hotel_requests_path(current_hotel))
      respond_to do |format|
        format.html { redirect_to redirect_target, alert: "Request not found." }
        format.json { render json: { ok: false }, status: :not_found }
      end
    end

    def authorize_advance_request!
      return unless ADVANCE_GUARDED_KINDS.include?(params[:kind].to_s)

      authorize_advance!(
        ::HotelPortal::Requests::Finder.new(
          hotel: current_hotel,
          kind: params[:kind],
          request_id: params[:request_id]
        ).call
      )
    end

    def authorize_manage_requests!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_requests", hotel: current_hotel)
    end
  end
end

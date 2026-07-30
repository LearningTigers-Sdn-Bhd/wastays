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
    before_action :set_breadcrumbs, only: [ :archive ]
    before_action :authorize_advance_request!, only: [ :update_status ]

    rescue_from ActiveRecord::RecordNotFound, with: :handle_record_not_found

    def index
      @board = ::HotelPortal::RequestsBoard.new(current_hotel, params)
      @board_columns = @board.board_columns
      @board_counts = @board.board_counts
      @board_columns = {
        housekeeping: Kaminari.paginate_array(@board_columns[:housekeeping]).page(params[:housekeeping_page]).per(25),
        complaint: Kaminari.paginate_array(@board_columns[:complaint]).page(params[:complaint_page]).per(25),
        completed: Kaminari.paginate_array(@board_columns[:completed]).page(params[:completed_page]).per(25),
        checkout: Kaminari.paginate_array(@board_columns[:checkout]).page(params[:checkout_page]).per(25)
      }
      @presenter = ::HotelPortal::RequestsBoardPresenter.new(
        board_columns: @board_columns,
        board_counts: @board_counts,
        current_hotel: current_hotel,
        view_context: view_context
      )
    end

    def archive
      archive = ::HotelPortal::RequestsArchive.new(current_hotel, params)
      archive_rows = Kaminari.paginate_array(archive.rows).page(params[:page]).per(25)

      @presenter = ::HotelPortal::RequestsArchivePresenter.new(
        archive_rows: archive_rows,
        archive_counts: archive.summary_counts
      )
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

    def update_status
      updater = ::HotelPortal::Requests::StatusUpdater.new(
        hotel: current_hotel,
        kind: params[:kind],
        request_id: params[:request_id],
        status: params[:status]
      )

      redirect_target = safe_redirect_target(hotel_requests_path(current_hotel))
      if (request = updater.call)
        respond_to do |format|
          format.html { redirect_to redirect_target, notice: "Request updated successfully." }
          format.json { render json: { ok: true, status: request.status } }
        end
      else
        respond_to do |format|
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

      redirect_target = safe_redirect_target(hotel_request_archive_path(current_hotel))
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

    def handle_record_not_found
      redirect_target = safe_redirect_target(
        action_name == "unarchive_request" ? hotel_request_archive_path(current_hotel) : hotel_requests_path(current_hotel)
      )
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

    def set_breadcrumbs
      append_breadcrumb "Archive", hotel_request_archive_path(current_hotel)
    end
  end
end

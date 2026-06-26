class HotelPortal::RequestsController < HotelPortal::BaseController
  before_action :authorize_manage_requests!
  before_action -> { require_feature!("task_assignment_minibar_log") }
  before_action :set_breadcrumbs, only: [ :archive ]

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
    @archive = ::HotelPortal::RequestsArchive.new(current_hotel, params)
    @archive_rows = Kaminari.paginate_array(@archive.rows).page(params[:page]).per(25)
    @archive_counts = @archive.summary_counts
  end

  def cancel_request
    updater = ::HotelPortal::Requests::CancelUpdater.new(
      hotel: current_hotel,
      kind: params[:kind],
      request_id: params[:request_id],
      note: params[:internal_note]
    )

    if (request = updater.call)
      redirect_target = params[:redirect_to].presence || hotel_requests_path(current_hotel)
      respond_to do |format|
        format.html { redirect_to redirect_target, notice: "Request cancelled successfully." }
        format.json { render json: { ok: true, status: request.status, archived_at: request.archived_at } }
      end
    else
      redirect_target = params[:redirect_to].presence || hotel_requests_path(current_hotel)
      respond_to do |format|
        format.html { redirect_to redirect_target, alert: "Cancellation note is required." }
        format.json { render json: { ok: false }, status: :unprocessable_entity }
      end
    end
  rescue ActiveRecord::RecordNotFound
    redirect_target = params[:redirect_to].presence || hotel_requests_path(current_hotel)
    respond_to do |format|
      format.html { redirect_to redirect_target, alert: "Request not found." }
      format.json { render json: { ok: false }, status: :not_found }
    end
  end

  def update_status
    updater = ::HotelPortal::Requests::StatusUpdater.new(
      hotel: current_hotel,
      kind: params[:kind],
      request_id: params[:request_id],
      status: params[:status]
    )

    if (request = updater.call)
      respond_to do |format|
        format.html { redirect_to hotel_requests_path(current_hotel), notice: "Request updated successfully." }
        format.json { render json: { ok: true, status: request.status } }
      end
    else
      respond_to do |format|
        format.html { redirect_to hotel_requests_path(current_hotel), alert: "Failed to update request." }
        format.json { render json: { ok: false }, status: :unprocessable_entity }
      end
    end
    rescue ActiveRecord::RecordNotFound
      respond_to do |format|
        format.html { redirect_to hotel_requests_path(current_hotel), alert: "Request not found." }
        format.json { render json: { ok: false }, status: :not_found }
      end
  end

  def archive_request
    updater = ::HotelPortal::Requests::ArchiveUpdater.new(
      hotel: current_hotel,
      kind: params[:kind],
      request_id: params[:request_id]
    )

    if (request = updater.archive)
      respond_to do |format|
        format.html { redirect_to hotel_requests_path(current_hotel), notice: "Request archived successfully." }
        format.json { render json: { ok: true, archived_at: request.archived_at } }
      end
    else
      respond_to do |format|
        format.html { redirect_to hotel_requests_path(current_hotel), alert: "Failed to archive request." }
        format.json { render json: { ok: false }, status: :unprocessable_entity }
      end
    end
  rescue ActiveRecord::RecordNotFound
    respond_to do |format|
      format.html { redirect_to hotel_requests_path(current_hotel), alert: "Request not found." }
      format.json { render json: { ok: false }, status: :not_found }
    end
  end

  def unarchive_request
    updater = ::HotelPortal::Requests::ArchiveUpdater.new(
      hotel: current_hotel,
      kind: params[:kind],
      request_id: params[:request_id]
    )

    if (request = updater.unarchive)
      respond_to do |format|
        format.html { redirect_to hotel_request_archive_path(current_hotel), notice: "Request restored successfully." }
        format.json { render json: { ok: true, archived_at: request.archived_at } }
      end
    else
      respond_to do |format|
        format.html { redirect_to hotel_request_archive_path(current_hotel), alert: "Failed to restore request." }
        format.json { render json: { ok: false }, status: :unprocessable_entity }
      end
    end
  rescue ActiveRecord::RecordNotFound
    respond_to do |format|
      format.html { redirect_to hotel_request_archive_path(current_hotel), alert: "Request not found." }
      format.json { render json: { ok: false }, status: :not_found }
    end
  end

  private

  def authorize_manage_requests!
    raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_requests", hotel: current_hotel)
  end

  def set_breadcrumbs
    append_breadcrumb "Archive", hotel_request_archive_path(current_hotel)
  end
end

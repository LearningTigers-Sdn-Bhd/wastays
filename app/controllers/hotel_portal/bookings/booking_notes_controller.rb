class HotelPortal::Bookings::BookingNotesController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_hotel_access!
  before_action :set_booking
  before_action :set_note, only: [ :update, :destroy ]

  def create
    @note = @booking.booking_notes.build(note_params)
    @note.user = current_user

    if persist_note_with_audit("note_added", old_value: {}, new_value: { "body" => @note.body }) { @note.save! }
      respond_to do |format|
        format.turbo_stream { render_notes_update("Note added.", :notice) }
        format.html { redirect_to hotel_booking_control_panel_path(current_hotel, @booking, tab: "booking_details"), notice: "Note added." }
      end
    else
      respond_to do |format|
        format.turbo_stream { render_notes_update("Failed to add note.", :alert, status: :unprocessable_content) }
        format.html { redirect_to hotel_booking_control_panel_path(current_hotel, @booking, tab: "booking_details"), alert: "Failed to add note." }
      end
    end
  end

  def update
    updated_body = note_params[:body].to_s.strip

    if updated_body.blank?
      respond_to do |format|
        format.turbo_stream { render_notes_update("Note body cannot be blank.", :alert, status: :unprocessable_content) }
        format.html { redirect_to hotel_booking_control_panel_path(current_hotel, @booking, tab: "booking_details"), alert: "Note body cannot be blank." }
      end
      return
    end

    if updated_body != @note.body
      @note.edit_history = Array(@note.edit_history) + [
        {
          body: @note.body,
          edited_at: Time.current.iso8601,
          edited_by_name: current_user.name
        }
      ]
    end

    old_body = @note.body
    if persist_note_with_audit("note_updated", old_value: { "body" => old_body }, new_value: { "body" => updated_body }) { @note.update!(body: updated_body) }
      respond_to do |format|
        format.turbo_stream { render_notes_update("Note updated.", :notice) }
        format.html { redirect_to hotel_booking_control_panel_path(current_hotel, @booking, tab: "booking_details"), notice: "Note updated." }
      end
    else
      respond_to do |format|
        format.turbo_stream { render_notes_update("Failed to update note.", :alert, status: :unprocessable_content) }
        format.html { redirect_to hotel_booking_control_panel_path(current_hotel, @booking, tab: "booking_details"), alert: "Failed to update note." }
      end
    end
  end

  def destroy
    old_body = @note.body
    if persist_note_with_audit("note_deleted", old_value: { "body" => old_body }, new_value: {}) { @note.destroy! }
      respond_to do |format|
        format.turbo_stream { render_notes_update("Note deleted.", :notice) }
        format.html { redirect_to hotel_booking_control_panel_path(current_hotel, @booking, tab: "booking_details"), notice: "Note deleted." }
      end
    else
      respond_to do |format|
        format.turbo_stream { render_notes_update("Failed to delete note.", :alert, status: :unprocessable_content) }
        format.html { redirect_to hotel_booking_control_panel_path(current_hotel, @booking, tab: "booking_details"), alert: "Failed to delete note." }
      end
    end
  end

  private

  def persist_note_with_audit(action_type, old_value:, new_value:)
    Booking.transaction do
      yield
      Bookings::RecordAuditLog.call!(
        auditable: @booking,
        user: current_user,
        action_type: action_type,
        old_value: old_value,
        new_value: new_value,
        metadata: { "note_id" => @note.id }
      )
    end
    true
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed
    false
  end

  def set_booking
    @booking = current_hotel.bookings.find(params[:booking_id])
  end

  def set_note
    @note = @booking.booking_notes.find(params[:id])
  end

  def note_params
    params.require(:booking_note).permit(:body)
  end

  def render_notes_update(message, key, status: :ok)
    render turbo_stream: [
      turbo_stream.update(
        "booking_notes_panel",
        partial: "hotel_portal/bookings/show/internal_notes",
        locals: { booking: @booking }
      ),
      toast_stream_for_flash(message, key)
    ], status: status
  end
end

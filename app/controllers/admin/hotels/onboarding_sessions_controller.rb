class Admin::Hotels::OnboardingSessionsController < Admin::BaseController
  before_action :set_hotel
  before_action :set_session, only: [ :show, :edit, :update, :complete, :cancel, :destroy ]

  def index
    @sessions = @hotel.onboarding_sessions.ordered
  end

  def create
    @session = @hotel.onboarding_sessions.new(onboarding_session_params)
    @session.status = "scheduled"
    @session.notes = "TRAINING_SESSION"

    if @session.save
      respond_to do |format|
        format.html { redirect_to onboarding_admin_hotel_path(@hotel), notice: "Training session scheduled successfully." }
        format.turbo_stream do
          @sessions = @hotel.onboarding_sessions.ordered
          render turbo_stream: [
            turbo_stream.replace(
              "new_onboarding_session_form",
              partial: "admin/hotels/onboarding_session_form",
              locals: { session: OnboardingSession.new }
            ),
            turbo_stream.replace(
              "onboarding_sessions_list",
              partial: "admin/hotels/onboarding_sessions_list",
              locals: { sessions: @sessions, hotel: @hotel }
            ),
            turbo_stream.prepend(
              "flash_toasts",
              partial: "shared/toast",
              locals: { key: "notice", value: "Training session scheduled successfully." }
            )
          ]
        end
      end
    else
      respond_to do |format|
        format.html { redirect_to onboarding_admin_hotel_path(@hotel), alert: "Failed to schedule session: #{@session.errors.full_messages.to_sentence}" }
        format.turbo_stream do
          @sessions = @hotel.onboarding_sessions.ordered
          render turbo_stream: [
            turbo_stream.replace(
              "new_onboarding_session_form",
              partial: "admin/hotels/onboarding_session_form",
              locals: { session: @session }
            ),
            turbo_stream.prepend(
              "flash_toasts",
              partial: "shared/toast",
              locals: { key: "alert", value: "Failed to schedule session: #{@session.errors.full_messages.to_sentence}" }
            )
          ], status: :unprocessable_content
        end
      end
    end
  end

  def edit
    respond_to do |format|
      format.html { render partial: "admin/hotels/onboarding_session", locals: { session: @session, hotel: @hotel, editing: true } }
      format.turbo_stream
    end
  end

  def show
    render partial: "admin/hotels/onboarding_session", locals: { session: @session, hotel: @hotel, editing: false }
  end

  def update
    if @session.update(onboarding_session_params)
      respond_to do |format|
        format.html { redirect_to onboarding_admin_hotel_path(@hotel), notice: "Training session updated successfully." }
        format.turbo_stream { render_onboarding_sessions_list("Training session updated successfully.") }
      end
    else
      respond_to do |format|
        format.html { redirect_to onboarding_admin_hotel_path(@hotel), alert: "Failed to update session: #{@session.errors.full_messages.to_sentence}" }
        format.turbo_stream { render_onboarding_sessions_list("Failed to update session: #{@session.errors.full_messages.to_sentence}", :alert, status: :unprocessable_content) }
      end
    end
  end

  def complete
    if @session.scheduled_at.blank? || @session.scheduled_at > Time.current
      redirect_to onboarding_admin_hotel_path(@hotel), alert: "This training session cannot be marked completed until its scheduled time."
      return
    end

    if @session.complete!
      respond_to do |format|
        format.html { redirect_to onboarding_admin_hotel_path(@hotel), notice: "Training session marked as completed." }
        format.turbo_stream { render_onboarding_sessions_list("Training session marked as completed.") }
      end
    else
      respond_to do |format|
        format.html { redirect_to onboarding_admin_hotel_path(@hotel), alert: "Failed to update session." }
        format.turbo_stream { render_onboarding_sessions_list("Failed to update session.", :alert, status: :unprocessable_content) }
      end
    end
  end

  def cancel
    unless @session.status == "scheduled"
      redirect_to onboarding_admin_hotel_path(@hotel), alert: "Only scheduled sessions can be cancelled."
      return
    end

    cancel_reason = params[:cancel_reason].to_s.strip
    if cancel_reason.blank?
      redirect_to onboarding_admin_hotel_path(@hotel), alert: "Please provide a reason before cancelling the session."
      return
    end

    @session.update!(
      status: "cancelled",
      notes: [ @session.notes.presence, "CANCELLED: #{cancel_reason}" ].compact.join("\n")
    )

    respond_to do |format|
      format.html { redirect_to onboarding_admin_hotel_path(@hotel), notice: "Training session cancelled successfully." }
      format.turbo_stream { render_onboarding_sessions_list("Training session cancelled successfully.") }
    end
  rescue ActiveRecord::RecordInvalid => e
    respond_to do |format|
      format.html { redirect_to onboarding_admin_hotel_path(@hotel), alert: "Failed to cancel session: #{e.message}" }
      format.turbo_stream { render_onboarding_sessions_list("Failed to cancel session: #{e.message}", :alert, status: :unprocessable_content) }
    end
  end

  def destroy
    if @session.destroy
      respond_to do |format|
        format.html { redirect_to onboarding_admin_hotel_path(@hotel), notice: "Training session deleted successfully." }
        format.turbo_stream { render_onboarding_sessions_list("Training session deleted successfully.") }
      end
    else
      respond_to do |format|
        format.html { redirect_to onboarding_admin_hotel_path(@hotel), alert: "Failed to delete session." }
        format.turbo_stream { render_onboarding_sessions_list("Failed to delete session.", :alert, status: :unprocessable_content) }
      end
    end
  rescue ActiveRecord::RecordInvalid => e
    respond_to do |format|
      format.html { redirect_to onboarding_admin_hotel_path(@hotel), alert: "Failed to delete session: #{e.message}" }
      format.turbo_stream { render_onboarding_sessions_list("Failed to delete session: #{e.message}", :alert, status: :unprocessable_content) }
    end
  end

  private

  def set_hotel
    @hotel = Hotel.friendly.find(params[:hotel_id])
  end

  def set_session
    @session = @hotel.onboarding_sessions.find(params[:id])
  end

  def onboarding_session_params
    params.permit(:trainer_name, :scheduled_at, :meeting_link)
  end

  def render_onboarding_sessions_list(message, key = :notice, status: :ok)
    @sessions = @hotel.onboarding_sessions.ordered

    render turbo_stream: [
      turbo_stream.replace(
        "onboarding_sessions_list",
        partial: "admin/hotels/onboarding_sessions_list",
        locals: { sessions: @sessions, hotel: @hotel }
      ),
      turbo_stream.prepend(
        "flash_toasts",
        partial: "shared/toast",
        locals: { key: key.to_s, value: message }
      )
    ], status: status
  end
end

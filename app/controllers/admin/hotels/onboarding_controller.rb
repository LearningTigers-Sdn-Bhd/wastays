class Admin::Hotels::OnboardingController < Admin::BaseController
  before_action :set_hotel, only: [ :show, :complete, :save_period ]

  def index
    @hotels = Hotel.pending_review_onboarding
  end

  def show
    @sessions = @hotel.onboarding_sessions
                      .order(scheduled_at: :asc, created_at: :asc)
  end

  def complete
    start_date = params[:start_date].presence ? Time.zone.parse(params[:start_date]) : @hotel.onboarding_start_date.beginning_of_day
    end_date = params[:end_date].presence ? Time.zone.parse(params[:end_date]).end_of_day : @hotel.onboarding_end_date.end_of_day

    result = Admin::CompleteOnboarding.new(
      hotel: @hotel,
      start_date: start_date,
      end_date: end_date
    ).call

    if result.success?
      redirect_to onboarding_admin_hotels_path, notice: "Onboarding for #{@hotel.name} completed successfully."
    else
      redirect_to onboarding_admin_hotels_path, alert: "Failed to complete onboarding: #{result.error}"
    end
  end

  def save_period
    start_date = params[:start_date].presence ? Date.parse(params[:start_date]) : @hotel.created_at.to_date
    end_date = params[:end_date].presence ? Date.parse(params[:end_date]) : Date.current

    if @hotel.update(onboarding_start_date: start_date, onboarding_end_date: end_date)
      respond_to do |format|
        format.json { render json: { success: true } }
        format.turbo_stream do
          @hotels = Hotel.pending_review_onboarding
          render turbo_stream: turbo_stream.replace(
            "onboarding_tracker_table",
            partial: "admin/hotels/onboarding_tracker_table",
            locals: { hotels: @hotels }
          )
        end
      end
    else
      respond_to do |format|
        format.json { render json: { success: false, errors: @hotel.errors.full_messages }, status: :unprocessable_entity }
        format.turbo_stream do
          @hotels = Hotel.pending_review_onboarding
          render turbo_stream: turbo_stream.replace(
            "onboarding_tracker_table",
            partial: "admin/hotels/onboarding_tracker_table",
            locals: { hotels: @hotels }
          ), status: :unprocessable_content
        end
      end
    end
  end

  private

  def set_hotel
    @hotel = Hotel.find(params[:id])
  end
end

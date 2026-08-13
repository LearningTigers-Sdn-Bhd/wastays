class Admin::Hotels::OnboardingController < Admin::BaseController
  before_action :set_hotel, only: [ :show, :request_changes, :approve, :save_period ]

  def index
    @hotels = Hotel.pending_review_onboarding
  end

  def show
    @sessions = @hotel.onboarding_sessions
                      .order(scheduled_at: :asc, created_at: :asc)
    @submission = @hotel.onboarding_submissions.includes(:submitted_by, :reviewed_by, :deliveries).newest_first.first
    @readiness = Onboarding::Readiness.new(hotel: @hotel).call
    @configuration_unchanged = configuration_unchanged?
    @audit_events = @hotel.onboarding_audit_events.includes(:user).order(occurred_at: :desc, id: :desc)
  end

  def request_changes
    result = Onboarding::RequestChanges.call(
      hotel: @hotel,
      actor: current_user,
      section_keys: params[:section_keys],
      explanation: params[:explanation]
    )

    redirect_to onboarding_admin_hotel_path(@hotel),
                (result.success? ? { notice: "Changes requested from the property owner." } : { alert: result.error })
  end

  def approve
    result = Onboarding::ApproveOnboarding.call(hotel: @hotel, actor: current_user)

    redirect_to onboarding_admin_hotel_path(@hotel),
                (result.success? ? { notice: "#{@hotel.name} is now live." } : { alert: result.error })
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
    @hotel = Hotel.friendly.find(params[:id])
  end

  def configuration_unchanged?
    return false unless @submission

    current_digest = Onboarding::SubmissionSnapshot.call(hotel: @hotel).digest
    ActiveSupport::SecurityUtils.secure_compare(current_digest, @submission.configuration_digest)
  end
end

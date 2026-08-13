class Admin::Hotels::OnboardingController < Admin::BaseController
  before_action :set_hotel, only: [ :show, :request_changes, :approve, :save_period ]

  def show
    @sessions = @hotel.onboarding_sessions
                      .order(scheduled_at: :asc, created_at: :asc)
    @submission = @hotel.onboarding_submissions.includes(:submitted_by, :reviewed_by, :deliveries).newest_first.first
    rates_coverage = Rates::SetupCoverage.call(hotel: @hotel)
    @readiness = Onboarding::Readiness.new(hotel: @hotel, rates_coverage:).call
    @configuration_unchanged = configuration_unchanged?(rates_coverage:)
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
    start_date = parse_period_date(params[:start_date])
    end_date = parse_period_date(params[:end_date])

    if start_date.nil? || end_date.nil?
      redirect_to onboarding_admin_hotel_path(@hotel), alert: "Enter a valid start and end date."
      return
    end

    if end_date < start_date
      redirect_to onboarding_admin_hotel_path(@hotel), alert: "The end date must be on or after the start date."
      return
    end

    if @hotel.update(onboarding_start_date: start_date, onboarding_end_date: end_date)
      redirect_to onboarding_admin_hotel_path(@hotel), notice: "Onboarding period updated."
    else
      redirect_to onboarding_admin_hotel_path(@hotel), alert: @hotel.errors.full_messages.to_sentence
    end
  end

  private

  def set_hotel
    @hotel = Hotel.friendly.find(params[:id])
  end

  def parse_period_date(value)
    Date.iso8601(value.to_s)
  rescue Date::Error
    nil
  end

  def configuration_unchanged?(rates_coverage:)
    return false unless @submission

    current_digest = Onboarding::SubmissionSnapshot.call(hotel: @hotel, rates_coverage:).digest
    ActiveSupport::SecurityUtils.secure_compare(current_digest, @submission.configuration_digest)
  end
end

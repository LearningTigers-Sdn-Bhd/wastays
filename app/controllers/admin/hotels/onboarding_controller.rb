class Admin::Hotels::OnboardingController < Admin::BaseController
  TAB_LABELS = {
    "overview" => "Overview",
    "history" => "History",
    "training" => "Training"
  }.freeze

  before_action :set_hotel, only: [ :show, :request_changes, :approve, :save_period, :toggle_setup_lock ]

  def show
    @active_tab = TAB_LABELS.keys.find { |tab| tab == params[:tab] } || "overview"
    @submission = submission_scope.newest_first.first

    case @active_tab
    when "overview"
      rates_coverage = Rates::SetupCoverage.call(hotel: @hotel)
      @readiness = Onboarding::Readiness.new(hotel: @hotel, rates_coverage:).call
      @configuration_unchanged = configuration_unchanged?(rates_coverage:)
      @overview_presenter = Admin::Hotels::OnboardingOverviewPresenter.new(submission: @submission) if @submission
    when "history"
      @audit_events = @hotel.onboarding_audit_events.includes(:user).order(occurred_at: :desc, id: :desc)
    when "training"
      @sessions = @hotel.onboarding_sessions.order(scheduled_at: :asc, created_at: :asc)
    end
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

  # The setup lock is rolled out one property at a time, so it needs a switch that is
  # not the Rails console.
  def toggle_setup_lock
    enabled = !@hotel.setup_lock_enabled?
    @hotel.update!(setup_lock_enabled: enabled)

    redirect_to onboarding_admin_hotel_path(@hotel),
                notice: enabled ? "Setup lock enabled. Staff are kept inside onboarding." : "Setup lock disabled."
  end

  def save_period
    start_date = parse_period_date(params[:start_date])
    end_date = parse_period_date(params[:end_date])
    return_path = onboarding_path_for(params[:tab])

    if start_date.nil? || end_date.nil?
      redirect_to return_path, alert: "Enter a valid start and end date."
      return
    end

    if end_date < start_date
      redirect_to return_path, alert: "The end date must be on or after the start date."
      return
    end

    if @hotel.update(onboarding_start_date: start_date, onboarding_end_date: end_date)
      redirect_to return_path, notice: "Onboarding period updated."
    else
      redirect_to return_path, alert: @hotel.errors.full_messages.to_sentence
    end
  end

  private

  def set_hotel
    @hotel = Hotel.locate!(params[:id])
  end

  def parse_period_date(value)
    Date.iso8601(value.to_s)
  rescue Date::Error
    nil
  end

  def submission_scope
    scope = @hotel.onboarding_submissions
    return scope.includes(:submitted_by, :deliveries) if @active_tab == "overview"

    scope
  end

  def onboarding_path_for(tab)
    return onboarding_admin_hotel_path(@hotel) unless TAB_LABELS.key?(tab) && tab != "overview"

    onboarding_tab_admin_hotel_path(@hotel, tab:)
  end

  def configuration_unchanged?(rates_coverage:)
    return false unless @submission

    current_digest = Onboarding::SubmissionSnapshot.call(hotel: @hotel, rates_coverage:).digest
    ActiveSupport::SecurityUtils.secure_compare(current_digest, @submission.configuration_digest)
  end
end

module Admin
  class CompleteOnboarding
    Result = Struct.new(:success?, :error)

    def initialize(hotel:, start_date:, end_date:)
      @hotel = hotel
      @start_date = start_date
      @end_date = end_date
    end

    def call
      ActiveRecord::Base.transaction do
        # 1. Ensure status is moved forward
        @hotel.update!(status: "approved") if @hotel.onboarding? || @hotel.status == "pending_review"

        # 2. Update or create the final onboarding session record
        final_session = @hotel.onboarding_sessions.find_or_initialize_by(notes: "FINAL_ONBOARDING_COMPLETION")
        final_session.update!(
          trainer_name: "Onboarding System",
          status: "completed",
          scheduled_at: @start_date,
          completed_at: @end_date
        )
      end
      Result.new(true, nil)
    rescue ActiveRecord::RecordInvalid => e
      Result.new(false, e.message)
    end
  end
end

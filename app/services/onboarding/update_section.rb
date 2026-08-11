# frozen_string_literal: true

module Onboarding
  class UpdateSection
    Result = ApplicationResult.define(:section)
    EVENTS = {
      "in_progress" => "started",
      "complete" => "completed",
      "skipped" => "skipped",
      "needs_attention" => "invalidated"
    }.freeze

    def initialize(hotel:, section_key:, state:, actor: nil, metadata: {})
      @hotel = hotel
      @definition = SectionCatalog.fetch(section_key)
      @state = state.to_s
      @actor = actor
      @metadata = metadata.to_h
    end

    def call
      unless EVENTS.key?(@state)
        return Result.failure("Unsupported onboarding section transition.", section: nil)
      end
      if @state == "skipped" && @definition.required
        return Result.failure("Required onboarding sections cannot be skipped.", section: section)
      end
      if %w[in_progress complete skipped].include?(@state) && !prerequisites_resolved?
        return Result.failure("Complete the prerequisite sections first.", section: section)
      end

      HotelOnboardingSection.transaction do
        section.update!(transition_attributes)
        @hotel.onboarding_audit_events.create!(
          user: @actor,
          event_type: EVENTS.fetch(@state),
          section_key: @definition.key,
          metadata: @metadata,
          occurred_at: Time.current
        )
      end

      Result.success(section: section)
    rescue ActiveRecord::RecordInvalid => e
      Result.failure(e.record.errors.full_messages.to_sentence, section: section)
    end

    private

    def section
      @section ||= begin
        InitializeProgress.new(hotel: @hotel, actor: @actor).call
        @hotel.onboarding_sections.find_by!(section_key: @definition.key)
      end
    end

    def prerequisites_resolved?
      return true if @definition.prerequisites.empty?

      @hotel.onboarding_sections
            .where(section_key: @definition.prerequisites, state: %w[complete skipped])
            .distinct
            .count == @definition.prerequisites.size
    end

    def transition_attributes
      {
        state: @state,
        completed_at: (@state == "complete" ? Time.current : nil),
        skipped_at: (@state == "skipped" ? Time.current : nil),
        decision_metadata: @metadata
      }
    end
  end
end

# frozen_string_literal: true

module Onboarding
  class SaveStaffDrafts
    Result = ApplicationResult.define(:section, :entries)

    def initialize(hotel:, actor:, entries:, complete:)
      @hotel = hotel
      @actor = actor
      @raw_entries = entries
      @complete = complete
    end

    def call
      # Continuing with an empty table is itself the answer: nobody else needs
      # access yet. Making the owner press a separate button to say what the empty
      # table already says would be asking twice.
      return decide_no_additional_staff if @complete && entries.empty?
      return failure(validation_errors.to_sentence) if validation_errors.any?

      transition_result = nil
      OnboardingStaffDraft.transaction do
        @hotel.onboarding_staff_drafts.delete_all
        drafts.each(&:save!)
        transition_result = UpdateSection.new(
          hotel: @hotel,
          section_key: "staff_setup",
          state: @complete ? "complete" : "in_progress",
          actor: @actor,
          metadata: { source: "staff_draft_setup", staff_count: drafts.size }
        ).call
        raise ActiveRecord::Rollback unless transition_result.success?
      end
      return failure(transition_result.error, section: transition_result.section) unless transition_result.success?

      Result.success(section: transition_result.section, entries: serialized_entries)
    end

    private

    # The same decision the skip button used to record, including discarding any
    # drafts left behind, so an owner who empties the table leaves no invitations
    # queued for people they just removed.
    def decide_no_additional_staff
      result = DecideNoAdditionalStaff.new(hotel: @hotel, actor: @actor).call
      return failure(result.error, section: result.section) unless result.success?

      Result.success(section: result.section, entries: [])
    end

    def entries
      @entries ||= begin
        collection = if @raw_entries.respond_to?(:to_unsafe_h)
                       @raw_entries.to_unsafe_h.values
        elsif @raw_entries.is_a?(Hash)
                       @raw_entries.values
        else
                       Array(@raw_entries)
        end
        collection.filter_map do |entry|
        values = entry.respond_to?(:to_unsafe_h) ? entry.to_unsafe_h : entry.to_h
        normalized = values.stringify_keys.slice("name", "email", "role_id").transform_values { |value| value.to_s.strip }
        normalized["email"] = normalized["email"].downcase
          normalized unless normalized.values.all?(&:blank?)
        end
      end
    end

    def roles
      @roles ||= @hotel.account.roles.where(slug: ConfirmRolePresets::PRESET_SLUGS).index_by { |role| role.id.to_s }
    end

    def drafts
      @drafts ||= entries.map do |entry|
        OnboardingStaffDraft.new(
          hotel: @hotel,
          name: entry["name"],
          email: entry["email"],
          role: roles[entry["role_id"]]
        )
      end
    end

    def validation_errors
      @validation_errors ||= begin
        errors = drafts.each_with_index.flat_map do |draft, index|
          next [] if draft.valid?

          draft.errors.full_messages.map { |message| "Staff member #{index + 1}: #{message}" }
        end
        duplicates = entries.map { |entry| entry["email"] }.reject(&:blank?).tally.select { |_email, count| count > 1 }.keys
        errors << "Each staff email can only be added once: #{duplicates.to_sentence}" if duplicates.any?
        conflicts = entries.map { |entry| entry["email"] }.compact & unavailable_emails
        errors << "These emails already have access or a pending invitation: #{conflicts.to_sentence}" if conflicts.any?
        errors
      end
    end

    def unavailable_emails
      @unavailable_emails ||= begin
        active = @hotel.user_hotel_accesses.active.includes(:user).map { |access| access.user.email.downcase }
        pending = @hotel.staff_invitations.unaccepted.pluck(:email).map(&:downcase)
        (active + pending).uniq
      end
    end

    def serialized_entries
      entries.each_with_index.map do |entry, index|
        role = drafts[index].role
        entry.merge("role_slug" => role&.slug, "role_name" => role&.name)
      end
    end

    def failure(message, section: nil)
      Result.failure(message, section: section || @hotel.onboarding_sections.find_by(section_key: "staff_setup"), entries: serialized_entries)
    end
  end
end

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
      return failure(delivered_removal_error) if delivered_removal_error.present?
      return failure(validation_errors.to_sentence) if validation_errors.any?

      transition_result = nil
      OnboardingStaffDraft.transaction do
        discarded_drafts.each(&:destroy!)
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
          # The switch always submits — off included — so it cannot join the
          # emptiness test, or an untouched row would look like a real record.
          next if normalized.values.all?(&:blank?)

          normalized.merge("send_invitation" => ActiveModel::Type::Boolean.new.cast(values.stringify_keys["send_invitation"]).present?)
        end
      end
    end

    def roles
      @roles ||= @hotel.account.roles.where(slug: ConfirmRolePresets::PRESET_SLUGS).index_by { |role| role.id.to_s }
    end

    # Rows are matched to existing drafts by email rather than rebuilt from
    # scratch. A draft that has already produced an invitation carries the
    # marker that keeps delivery idempotent, and recreating the row would throw
    # it away and invite the person a second time. Reuse also means an unchanged
    # row validates its uniqueness against itself instead of against its own
    # database record.
    # Read straight from the table rather than through the association, which
    # may have been loaded before delivery stamped these rows — and which would
    # otherwise collect the unsaved records built below as though they had
    # already been added.
    def existing_drafts
      @existing_drafts ||= OnboardingStaffDraft.where(hotel_id: @hotel.id).index_by { |draft| draft.email.to_s.downcase }
    end

    def drafts
      @drafts ||= entries.map do |entry|
        draft = existing_drafts[entry["email"]] || OnboardingStaffDraft.new(hotel: @hotel)
        draft.assign_attributes(
          name: entry["name"],
          email: entry["email"],
          role: roles[entry["role_id"]],
          send_invitation: entry["send_invitation"]
        )
        draft
      end
    end

    def discarded_drafts
      @discarded_drafts ||= existing_drafts.values - drafts
    end

    # Mirrors SaveCorporateDrafts: once someone has been invited, taking their
    # row out of the table cannot unsend the email, so the table stops pretending
    # it can.
    def delivered_removal_error
      @delivered_removal_error ||= begin
        blocked = discarded_drafts.select(&:delivered?)
        "#{blocked.map { |draft| draft.name.presence || draft.email }.to_sentence} has already been invited and cannot be removed here." if blocked.any?
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
        # A draft that has already been delivered owns the pending invitation
        # bearing its address. Counting that against itself would make the step
        # unsaveable after a changes-requested review.
        (active + pending).uniq - existing_drafts.values.select(&:delivered?).map(&:email)
      end
    end

    def serialized_entries
      entries.each_with_index.map do |entry, index|
        role = drafts[index].role
        # The views read these as strings, matching what the controller builds
        # from persisted drafts, so a re-render after a failed save redraws the
        # switch the owner left rather than resetting it.
        entry.merge(
          "role_slug" => role&.slug,
          "role_name" => role&.name,
          "send_invitation" => entry["send_invitation"].to_s
        )
      end
    end

    def failure(message, section: nil)
      Result.failure(message, section: section || @hotel.onboarding_sections.find_by(section_key: "staff_setup"), entries: serialized_entries)
    end
  end
end

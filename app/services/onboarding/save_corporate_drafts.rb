# frozen_string_literal: true

module Onboarding
  # Companies that will be billed directly, queued for invitation.
  #
  # Nothing is sent here. CorporateInvitations::CreateService emails as it
  # creates, so setup stores drafts and submission delivers them — the one
  # sanctioned onboarding-only record besides staff drafts.
  #
  # Unlike SaveStaffDrafts this does not delete and rebuild the collection.
  # A draft that has already produced an invitation carries the marker that
  # makes delivery idempotent, so an owner editing this page after a
  # changes-requested review must not be able to erase it and cause a resend.
  class SaveCorporateDrafts
    include CommercialRows

    Result = ApplicationResult.define(:section, :entries)

    ENTRY_FIELDS = %w[
      id client_key _destroy
      email company_name account_type
      credit_limit credit_currency payment_terms_days
    ].freeze

    RECORD_LABEL = "Corporate account"
    FAILURE_MESSAGE = "Corporate accounts could not be saved."

    def self.call(...) = new(...).call

    def initialize(hotel:, actor:, entries:, complete:)
      @hotel = hotel
      @actor = actor
      @entries = entries
      @complete = complete
    end

    def call
      return failure(foreign_reference_error) if foreign_reference_error.present?
      return failure(duplicate_email_error) if duplicate_email_error.present?
      # Continuing with an empty table is the same statement as pressing the skip
      # button: this property bills no companies directly. Making the owner press
      # a particular button to say it would be asking twice.
      return decide_no_accounts if complete && retained_rows.empty?

      transition = nil

      Hotel.transaction do
        destroy_rows!
        save_rows!

        transition = transition_section
        fail_transaction!(transition.error) unless transition.success?
      end

      return failure(@error) if @error.present?

      Result.success(section: transition.section, entries: persisted_entries)
    rescue ActiveRecord::RecordNotFound
      failure("One or more submitted corporate accounts do not belong to this property.")
    end

    private

    attr_reader :hotel, :actor, :complete

    # The same decision the skip button records, including discarding queued
    # drafts, so an owner who empties the table does not leave invitations behind
    # waiting to be sent.
    def decide_no_accounts
      result = DecideNoCorporateAccounts.call(hotel: hotel, actor: actor)
      return failure(result.error, section: result.section) unless result.success?

      Result.success(section: result.section, entries: persisted_entries)
    end

    def destroy_rows!
      discarded_rows.each do |row|
        draft = existing_drafts.fetch(row["id"].to_s)
        fail_transaction!("#{draft.company_name.presence || draft.email} has already been invited and cannot be removed here.") if draft.delivered?

        draft.destroy!
      end
    end

    def save_rows!
      retained_rows.each_with_index do |row, index|
        draft = row["id"].present? ? existing_drafts.fetch(row["id"].to_s) : hotel.onboarding_corporate_drafts.new
        draft.assign_attributes(row.slice(*ENTRY_FIELDS).except("id", "client_key", "_destroy"))
        # A corporate account added during property setup is, by definition,
        # billed to the company. The normal settings portal can support other
        # relationships later; onboarding should not ask the owner to restate
        # the decision that brought the account here.
        draft.relationship_type = "direct_bill"

        # What submission will ask before it sends. Failing here means the owner
        # can fix it now instead of after review.
        eligibility = CorporateInvitations::CheckEligibility.call(hotel: hotel, email: draft.email)
        fail_transaction!(row_error(index, eligibility.error)) unless eligibility.success?

        fail_transaction!(row_error(index, draft.errors.full_messages.to_sentence)) unless draft.save
      end
    end

    # A row the owner never filled in. Corporate drafts are identified by email
    # rather than the name/code pair the charge tables use.
    def blank_row?(row) = row["id"].blank? && row["email"].to_s.strip.blank?

    def foreign_reference_error
      submitted_ids = rows.filter_map { |row| row["id"].presence&.to_s }
      "One or more submitted corporate accounts do not belong to this property." if submitted_ids.any? { |id| !existing_drafts.key?(id) }
    end

    def duplicate_email_error
      emails = retained_rows.map { |row| row["email"].to_s.strip.downcase }.reject(&:blank?)
      duplicate = emails.tally.find { |_email, count| count > 1 }&.first
      "Each corporate account needs its own email. #{duplicate} is used more than once." if duplicate
    end

    def transition_section
      drafts = hotel.onboarding_corporate_drafts.reload
      UpdateSection.new(
        hotel: hotel,
        section_key: "corporate_accounts",
        state: complete ? "complete" : "in_progress",
        actor: actor,
        metadata: {
          source: "corporate_account_setup",
          draft_count: drafts.size,
          delivered_count: drafts.count(&:delivered?)
        }
      ).call
    end

    def existing_drafts
      @existing_drafts ||= hotel.onboarding_corporate_drafts.index_by { |draft| draft.id.to_s }
    end

    def persisted_entries
      hotel.onboarding_corporate_drafts.reload.order(:created_at, :id).map do |draft|
        {
          "id" => draft.id.to_s,
          "client_key" => "corporate-draft-#{draft.id}",
          "email" => draft.email,
          "company_name" => draft.company_name,
          "account_type" => draft.account_type,
          "relationship_type" => draft.relationship_type,
          "credit_limit" => draft.credit_limit&.to_s,
          "credit_currency" => draft.credit_currency,
          "payment_terms_days" => draft.payment_terms_days&.to_s,
          "delivered" => draft.delivered?.to_s
        }
      end
    end

    def failure(message, section: nil)
      Result.failure(message.presence || FAILURE_MESSAGE, section: section, entries: rows)
    end
  end
end

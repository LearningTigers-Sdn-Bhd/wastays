# frozen_string_literal: true

module Onboarding
  # The OTA extranet logins an owner hands over so their channels can be
  # connected after approval.
  #
  # Nothing is connected here and nothing is sent. The rows are stored for the
  # WAStays team to act on later, which is the whole contract of this section:
  # an owner who fills it in has finished their part of connecting a channel
  # manager, and one who skips it has still finished setup.
  class SaveOtaCredentials
    include CommercialRows

    Result = ApplicationResult.define(:section, :entries)

    ENTRY_FIELDS = %w[
      id client_key _destroy
      channel_name property_code username password
      market_manager_name market_manager_phone market_manager_email
    ].freeze

    RECORD_LABEL = "OTA login"
    FAILURE_MESSAGE = "OTA logins could not be saved."

    def self.call(...) = new(...).call

    def initialize(hotel:, actor:, entries:, complete:)
      @hotel = hotel
      @actor = actor
      @entries = entries
      @complete = complete
    end

    def call
      return failure(foreign_reference_error) if foreign_reference_error.present?
      return failure(duplicate_channel_error) if duplicate_channel_error.present?

      transition = nil

      Hotel.transaction do
        destroy_rows!
        save_rows!

        transition = complete && retained_rows.empty? ? decide_no_channel_manager : transition_section
        fail_transaction!(transition.error) unless transition.success?
      end

      return failure(@error) if @error.present?

      Result.success(section: transition.section, entries: persisted_entries)
    rescue ActiveRecord::RecordNotFound
      failure("One or more submitted OTA logins do not belong to this property.")
    end

    private

    attr_reader :hotel, :actor, :complete

    # Continuing with an empty table is itself the answer: this property has no
    # OTA logins to hand over yet. Making the owner press a separate button to
    # say what the empty table already says would be asking twice.
    #
    # Recorded as a decision rather than a completion, so review sees that this
    # property answered "none for now" rather than reading it as connected.
    def decide_no_channel_manager
      SkipOptionalSection.call(hotel: hotel, actor: actor, section_key: "channel_manager")
    end

    def destroy_rows!
      discarded_rows.each { |row| existing_records.fetch(row["id"].to_s).destroy! }
    end

    def save_rows!
      retained_rows.each_with_index do |row, index|
        record = row["id"].present? ? existing_records.fetch(row["id"].to_s) : hotel.hotel_ota_credentials.new
        record.assign_attributes(row.slice(*ENTRY_FIELDS).except("id", "client_key", "_destroy", "password"))
        # A stored password is never rendered back into the field, so a blank one
        # means "leave it alone" rather than "clear it". Without this, every save
        # of a section the owner only came back to fix a phone number would wipe
        # the credentials the whole section exists to collect.
        record.password = row["password"] if row["password"].to_s.present?

        fail_transaction!(row_error(index, record.errors.full_messages.to_sentence)) unless record.save
      end
    end

    # A row the owner never filled in. The channel is what identifies one of
    # these — a login with no extranet named is nothing.
    def blank_row?(row) = row["id"].blank? && row["channel_name"].to_s.strip.blank?

    def foreign_reference_error
      submitted_ids = rows.filter_map { |row| row["id"].presence&.to_s }
      "One or more submitted OTA logins do not belong to this property." if submitted_ids.any? { |id| !existing_records.key?(id) }
    end

    # Named back as the owner typed it. Channel names are brands — "Booking.com",
    # "Goibibo" — and any normalising this message did to compare them would show
    # up in it as a misspelling of someone's product.
    def duplicate_channel_error
      typed = retained_rows.map { |row| row["channel_name"].to_s.strip }.reject(&:blank?)
      duplicate = typed.group_by(&:downcase).values.find { |group| group.size > 1 }&.first
      "Each channel needs its own row. #{duplicate} is listed more than once." if duplicate
    end

    def transition_section
      records = hotel.hotel_ota_credentials.reload
      UpdateSection.new(
        hotel: hotel,
        section_key: "channel_manager",
        state: complete ? "complete" : "in_progress",
        actor: actor,
        metadata: {
          source: "channel_manager_setup",
          credential_count: records.size,
          preferred_channel_manager: hotel.preferred_channel_manager
        }
      ).call
    end

    def existing_records
      @existing_records ||= hotel.hotel_ota_credentials.index_by { |record| record.id.to_s }
    end

    # The password is deliberately absent. Handing it back would put it in the
    # HTML of every re-render, which is exactly what storing it encrypted is
    # meant to avoid; the table shows whether one is on file instead.
    def persisted_entries
      hotel.hotel_ota_credentials.reload.ordered.map do |record|
        {
          "id" => record.id.to_s,
          "client_key" => "ota-credential-#{record.id}",
          "channel_name" => record.channel_name,
          "property_code" => record.property_code,
          "username" => record.username,
          "password_saved" => record.password_saved?.to_s,
          "market_manager_name" => record.market_manager_name,
          "market_manager_phone" => record.market_manager_phone,
          "market_manager_email" => record.market_manager_email
        }
      end
    end

    def failure(message, section: nil)
      Result.failure(message.presence || FAILURE_MESSAGE, section: section, entries: redacted_rows)
    end

    # A failed save hands back what the owner typed so they can fix it — except
    # the password, which would then sit in the value attribute of a re-rendered
    # form. Storing it encrypted and echoing it in HTML cancel each other out.
    #
    # The cost is real: a row whose password was typed and not saved has to be
    # typed again. `password_typed` is what lets the field say so rather than
    # silently looking untouched.
    def redacted_rows
      rows.map do |row|
        typed = row["password"].to_s.present?
        stored = row["id"].present? && existing_records[row["id"].to_s]&.password_saved?
        row.except("password").merge("password_typed" => typed.to_s, "password_saved" => stored.to_s)
      end
    end
  end
end

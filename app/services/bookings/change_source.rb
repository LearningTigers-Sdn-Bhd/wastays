# frozen_string_literal: true

module Bookings
  # Corrects the channel a booking was recorded under, e.g. a Booking.com
  # reservation keyed at the desk as "Phone".
  #
  # Most of what depends on the source (OTA pricing, commission, reports) is
  # derived from `booking.source` on read, so the column is all that changes.
  # The exceptions are records that were built *for* the old source: a channel
  # manager owns its bookings' source, and settlements, OTA billing parties and
  # issued e-invoices were all made against it. Those bookings are refused.
  #
  # A Travel Agent source names the agent, the same as on the New Booking sheet:
  # the booking is put under that agent and its package (the room and the
  # hotel's package extras) bills to them. Only charges still to come can be
  # routed, so a booking whose package charges have already posted is left for
  # the Billing tab. Moving off Travel Agent leaves
  # the agent's billing alone; that is a Billing tab decision too.
  #
  # From a group room, `apply_to_group` corrects every room of the group at once.
  class ChangeSource
    Result = Data.define(:success?, :booking, :errors)

    BLOCKING_E_INVOICE_STATUSES = %w[pending submitted valid].freeze
    TRAVEL_AGENT = "travel_agent"

    class Refused < StandardError; end

    def self.call(booking:, actor:, source:, travel_agent_account_id: nil, apply_to_group: false)
      new(booking:, actor:, source:, travel_agent_account_id:, apply_to_group:).call
    end

    # Why the source cannot be changed, or nil when it can. Public so the
    # workspace can hide the action instead of offering one that will fail.
    def self.locked_reason(booking)
      if booking.channel_manager_reference.present?
        "This booking came from the channel manager, which owns its source."
      elsif booking.channel_settlements.exists?
        "This booking has channel settlements recorded against its source."
      elsif booking.booking_billing_parties.active.where(party_kind: "ota").exists?
        "This booking has an OTA billing party for its current source."
      elsif booking.e_invoice_submissions.guest_facing.where(status: BLOCKING_E_INVOICE_STATUSES).exists?
        "An e-invoice has already been issued for this booking."
      end
    end

    def initialize(booking:, actor:, source:, travel_agent_account_id: nil, apply_to_group: false)
      @booking = booking
      @actor = actor
      @source = BookingSource.normalize(source)
      @travel_agent_account_id = travel_agent_account_id
      @apply_to_group = ActiveModel::Type::Boolean.new.cast(apply_to_group) && booking.group_booking_id?
    end

    def call
      return failure("Choose a booking source.") if @source.blank?
      return failure("#{@source.tr('_', ' ').titleize} is not an available booking source.") unless selectable_source?
      return failure("Choose the travel agent this booking is under.") if travel_agent? && agent.nil?

      bookings = target_bookings.select { |booking| changes?(booking) }
      return failure(unchanged_message) if bookings.empty?

      Booking.transaction do
        bookings.each do |booking|
          refuse!(booking, self.class.locked_reason(booking))
          change!(booking)
        end
      end
      Result.new(true, @booking.reload, [])
    rescue Refused => e
      failure(e.message)
    rescue ActiveRecord::RecordInvalid => e
      failure(*e.record.errors.full_messages)
    end

    private

    def change!(booking)
      previous = audit_values(booking)
      booking.update!(source: @source)
      bill_agent!(booking) if moves_agent?(booking)
      Bookings::RecordAuditLog.call!(
        auditable: booking,
        user: @actor,
        action_type: "source_changed",
        old_value: previous,
        new_value: audit_values(booking)
      )
    end

    def bill_agent!(booking)
      refuse!(booking, "Charges the agent pays for have already been posted. Move them to the agent from the Billing tab.") if package_charges_posted?(booking)

      result = Folios::Routing::BillTravelAgentPackage.call(booking:, actor: @actor, hotel_corporate_account_id: agent.id)
      refuse!(booking, result.error) unless result.success?

      # The corporate portal lists a booking by this column, not by the billing party.
      booking.update!(hotel_corporate_account_id: agent.id)
    end

    def refuse!(booking, reason)
      return if reason.blank?

      raise Refused, @apply_to_group ? "Booking No. #{booking_reference(booking)}: #{reason}" : reason
    end

    def target_bookings
      return [ @booking ] unless @apply_to_group

      @booking.group_booking.bookings.where.not(status: "voided").order(:group_position, :id).to_a
    end

    def changes?(booking)
      booking.source != @source || moves_agent?(booking)
    end

    def moves_agent?(booking)
      travel_agent? && booking.hotel_corporate_account_id != agent.id
    end

    def travel_agent? = @source == TRAVEL_AGENT

    def agent
      return if @travel_agent_account_id.blank?

      @agent ||= @booking.hotel.hotel_corporate_accounts.active.where(account_type: TRAVEL_AGENT)
        .includes(:corporate_account).find_by(id: @travel_agent_account_id)
    end

    def package_charges_posted?(booking)
      @package_codes ||= Folios::Routing::BillTravelAgentPackage.codes_for(booking.hotel)
      FolioTransaction.where(booking_folio: booking.booking_folios, transaction_code: @package_codes).exists?
    end

    def audit_values(booking)
      values = { "source" => booking.source }
      values["travel_agent"] = booking.hotel_corporate_account&.corporate_account&.name if travel_agent?
      values
    end

    # Only sources staff could have picked when creating the booking: system
    # sources are reserved for integrations and are hidden from dropdowns.
    def selectable_source?
      record = BookingSource.registry[@source]
      record.present? && record.active? && record.kind != "system"
    end

    def unchanged_message
      return "The booking is already under #{agent.corporate_account.name}." if travel_agent?

      "The booking is already recorded as #{source_label(@source)}."
    end

    def booking_reference(booking)
      booking.formatted_reservation_number.presence || booking.id
    end

    def source_label(key)
      BookingSource.find_by_source(key)&.label || key.to_s.tr("_", " ").titleize
    end

    def failure(*errors)
      Result.new(false, @booking, errors)
    end
  end
end

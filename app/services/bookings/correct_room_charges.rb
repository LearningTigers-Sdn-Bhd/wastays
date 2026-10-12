# frozen_string_literal: true

require "digest"
require "ostruct"

module Bookings
  class CorrectRoomCharges
    PURPOSE = "completed-room-charge-correction"
    PERMISSIONS = %w[manage_bookings override_booking_rate post_folio_corrections manage_night_audit override_financial_date_lock].freeze
    Failure = Class.new(StandardError)

    def self.available?(booking:, user:)
      unavailable_reason(booking: booking, user: user).nil?
    end

    # Plain-language reason the correction cannot start, or nil when it can.
    def self.unavailable_reason(booking:, user:)
      return "Only checked-out bookings can use room-charge correction." unless booking.status == "completed"
      return "Imported OTA charges need a separate folio correction." if ota_charges?(booking)
      return "Only bookings with one room can be corrected here." unless booking.booking_rooms.size == 1

      missing = PERMISSIONS.reject { |permission| user&.superadmin? || user&.has_permission?(permission, hotel: booking.hotel) }
      "Needs the #{missing.map { |permission| "\"#{permission.tr('_', ' ')}\"" }.to_sentence} permission." if missing.any?
    end

    def self.ota_charges?(booking)
      booking.ota_booking? || booking.ota_financial_components.exists? ||
        OtaFinancialSnapshot.where(booking_id: booking.id).exists? ||
        (booking.group_booking_id.present? && OtaFinancialSnapshot.where(group_booking_id: booking.group_booking_id).exists?)
    end

    def self.call(**attributes)
      new(**attributes).call
    end

    def initialize(booking:, user:, nightly_amounts: nil, correction_reason: nil, correction_review_token: nil, confirm: false)
      @booking = booking
      @hotel = booking.hotel
      @user = user
      @amounts = nightly_amounts.to_h.transform_keys(&:to_s).transform_values { |value| value.to_s.strip }.reject { |_date, value| value.empty? }
      @reason = correction_reason.to_s.strip
      @token = correction_review_token.to_s
      @confirm = confirm
    end

    def call
      validate_context!
      result = nil
      ActiveRecord::Base.transaction(requires_new: true) do
        lock_context!
        validate_context!
        payload = verifier.verified(@token, purpose: PURPOSE) if @confirm
        if payload && payload.slice("actor_id", "hotel_id", "booking_id", "amounts", "reason") == scope_payload && completed_operation?(payload)
          result = success
          next
        end

        @snapshot = BuildRoomChargeCorrectionSnapshot.new(booking: @booking, nightly_amounts: @amounts).call
        @old_values = financial_values
        prepare_plans!
        @review = review_details
        digest = fingerprint
        same_review = payload && payload.except("operation_key") == scope_payload.merge("fingerprint" => digest)
        @payload = scope_payload.merge("fingerprint" => digest, "operation_key" => same_review ? payload.fetch("operation_key") : SecureRandom.uuid)
        if !@confirm || payload != @payload
          result = review_result(message: (@confirm ? "The correction details changed or expired. Review them again before confirming." : nil))
          next
        end

        apply_correction!
        result = success
      end
      result
    rescue Failure, ArgumentError, NightAudits::OperationalChangeGuard::OperationalChangeBlocked => e
      @booking.reload
      OpenStruct.new(success?: false, errors: [ e.message ], review: nil, correction_review_token: nil)
    rescue StandardError => e
      @booking.reload
      Rails.error.report(e, handled: true, context: { booking_id: @booking.id, operation: PURPOSE })
      OpenStruct.new(success?: false, errors: [ "The correction could not be completed. Nothing was changed." ], review: nil, correction_review_token: nil)
    end

    private

    def allowed?(permission)
      @user&.superadmin? || @user&.has_permission?(permission, hotel: @hotel)
    end

    def validate_context!
      raise Failure, "Only checked-out bookings can use room-charge correction." unless @booking.status == "completed"
      PERMISSIONS.each do |permission|
        raise Failure, "You do not have permission to correct room charges (#{permission})." unless allowed?(permission)
      end
      raise Failure, "A correction reason is required." if @reason.blank?
      raise Failure, "Imported OTA charges require source reconciliation. Use a separate folio correction." if self.class.ota_charges?(@booking)
      raise Failure, "This action requires exactly one recorded room booking." unless @booking.booking_rooms.size == 1
      NightAudits::OperationalChangeGuard.call!(hotel: @hotel, action: :correct_room_charges)
    end

    def lock_context!
      dates = ScheduledStay.stay_dates(hotel: @hotel, check_in: @booking.check_in, check_out: @booking.check_out)
      records = @hotel.hotel_business_dates.where(business_date: dates + [ @hotel.current_business_date ]).order(:business_date).lock.to_a
      @current_date = records.find { |record| record.id == @hotel.current_business_date_record&.id }
      raise Failure, "Hotel has no current accounting business date." unless @current_date
      raise Failure, "Resolve Night Audit before correcting room charges." unless @current_date.open?

      @booking.lock!
      @booking.booking_rooms.reload.each(&:lock!)
      @date_records = records.index_by(&:business_date)
      booking_ids = @booking.group_booking_id ? @booking.group_booking.bookings.order(:id).pluck(:id) : [ @booking.id ]
      @folios = @hotel.booking_folios.where(booking_id: booking_ids).order(:id).lock.to_a
      @booking.folio_routing_rules.order(:id).lock.load
      @transactions = FolioTransaction.joins(:booking_folio).where(booking_folios: { id: @folios.map(&:id) }).order(:id).lock("FOR UPDATE OF folio_transactions").to_a
      Invoice.where(booking_folio_id: @folios.map(&:id)).order(:id).lock.load
      ArInvoice.where(booking_folio_id: @folios.map(&:id)).order(:id).lock.load
      @hotel.night_audits.where(business_date: dates).order(:business_date).lock.load
    end

    def prepare_plans!
      # Derive both sides from the same locked ledger. Assign only in memory for
      # preview; no invoice, folio, snapshot, or audit record is written.
      before = reports
      validate_original_reports!(before)
      @booking.assign_attributes(@snapshot.booking_attributes)
      @booking.booking_rooms.first.assign_attributes(@snapshot.room_attributes)
      after = reports
      @booking.assign_attributes(@old_values.fetch(:booking))
      @booking.booking_rooms.first.assign_attributes(@old_values.fetch(:room))

      @plans = after.map do |date, report|
        old_report = before.fetch(date)
        removed = old_report.entries.flat_map { |entry| entry[:transactions] }.reject do |transaction|
          report.entries.any? { |entry| entry[:transactions].include?(transaction) }
        end
        changed = report.entries.select { |entry| entry[:issues].any? }
        reverse = removed + changed.flat_map { |entry| entry[:transactions] - [ entry[:valid_transactions].min_by(&:id) ] }
        post = changed.reject { |entry| entry[:valid_transactions].any? }
        { date: date, report: report, removed: removed, reverse: reverse, post: post }
      end
      @affected_folios = @folios.select do |folio|
        @plans.any? { |plan| plan[:reverse].any? { |row| row.booking_folio_id == folio.id } || plan[:post].any? { |entry| entry[:route].folio.id == folio.id } }
      end
      validate_folios!
    ensure
      if @old_values
        @booking.assign_attributes(@old_values.fetch(:booking))
        @booking.booking_rooms.first.assign_attributes(@old_values.fetch(:room))
      end
    end

    def reports
      @snapshot.nights.to_h do |night|
        date = Date.iso8601(night.fetch(:date))
        record = @date_records[date]
        audit = @hotel.night_audits.find_by(business_date: date, status: "completed")
        unless record && ((record.open? && record.id == @current_date.id) || (record.closed_like? && audit))
          raise Failure, "Resolve Night Audit for #{date} before correcting room charges."
        end
        report = Folios::Charges::NightlyChargeReconciliation.call(booking: @booking, business_date: date, allow_closed_folio: true, charge_keys: @snapshot.charge_keys)
        report.entries.each { |entry| raise Failure, entry[:route].error unless entry[:route].success? }
        [ date, report ]
      end
    end

    def validate_original_reports!(reports)
      relevant = @transactions.select do |row|
        row.source_booking_id == @booking.id && row.voided_by_transaction_id.nil? && @snapshot.charge_keys.include?(transaction_key(row))
      end
      if relevant.any? { |row| row.moved_from_transaction_id || row.split_from_transaction_id || row.transfer_group_id }
        raise Failure, "Moved or split nightly charges require a separate folio correction."
      end
      reports.each do |date, report|
        report.entries.each do |entry|
          raise Failure, "Existing room charges do not reconcile or their routing changed. Use a separate folio correction." if entry[:issues].any?
          if entry[:transactions].any? { |row| row.posting_date != date }
            raise Failure, "Room charges posted outside their stay dates require a separate folio correction."
          end
        end
      end
      expected_ids = reports.values.flat_map { |report| report.entries.flat_map { |entry| entry[:transactions].map(&:id) } }
      raise Failure, "Ambiguous nightly charges require a separate folio correction." if relevant.any? { |row| !expected_ids.include?(row.id) }
    end

    def validate_folios!
      @affected_folios.each do |folio|
        raise Failure, "Affected folios must be open or closed." unless folio.open? || folio.closed?
        raise Failure, "You do not have permission to reopen affected folios." if folio.closed? && !allowed?("manage_folio_windows")
        correction = folio.ar_invoice_corrections.unresolved.first
        if correction && (folio.closed? || !correction.editing?)
          raise Failure, "The previous invoice correction must finish before correcting room charges."
        end
        invoice = folio.invoice
        if invoice && (invoice.voided? || invoice.current_revision.blank? || !invoice.current_revision.snapshot.key?("transactions") || !invoice.current_revision.snapshot.key?("totals"))
          raise Failure, "This legacy or voided invoice requires a separate folio correction."
        end
        if invoice && folio.open? && !invoice.under_correction?
          raise Failure, "Reopen the invoiced folio through its correction workflow before changing charges."
        end
        if folio.receivable_history.exists? && folio.open? && !folio.ar_invoice_corrections.editing.exists?
          raise Failure, "Reopen the AR folio for correction before changing its charges."
        end
      end
    end

    def review_details
      {
        nights: @snapshot.nights,
        folios: @affected_folios.map do |folio|
          delta = @plans.sum do |plan|
            plan[:post].select { |entry| entry[:route].folio.id == folio.id }.sum { |entry| entry[:line][:amount].to_d } -
              plan[:reverse].select { |row| row.booking_folio_id == folio.id }.sum(&:amount)
          end
          { id: folio.id, reference: folio.folio_reference_display, reopen: folio.closed?, invoice: folio.invoice&.invoice_reference,
            current_balance: folio.outstanding_balance.to_d.to_s("F"), corrected_balance: (folio.outstanding_balance.to_d + delta).to_s("F") }
        end
      }
    end

    def apply_correction!
      @affected_folios.select(&:closed?).each do |folio|
        result = Folios::Lifecycle::ReopenFolio.call(folio: folio, user: @user, reason: @reason)
        raise Failure, result.error unless result.success?
      end
      @booking.association(:booking_folio).reset
      @booking.association(:booking_folios).reset
      @booking.booking_rooms.first.update!(@snapshot.room_attributes)
      @booking.update!(@snapshot.booking_attributes)
      @plans.each do |plan|
        audit = @hotel.night_audits.find_by(business_date: plan[:date], status: "completed")
        result = NightAudits::Financials::RepairCompletedNightlyCharges.new(night_audit: audit, business_date: plan[:date], booking: @booking, actor: @user, reason: @reason)
          .call_for_room_correction(charge_keys: @snapshot.charge_keys, removed_transactions: plan[:removed])
        raise Failure, result.error unless result.success?
      end
      Bookings::RecordAuditLog.call!(auditable: @booking, user: @user, action_type: "rate_override", category: "financial",
        old_value: @old_values, new_value: financial_values, reason: @reason,
        metadata: { correction_type: "completed_room_charges", operation_key: @payload.fetch("operation_key") })
      FolioOperationLog.create!(hotel: @hotel, booking: @booking, actor: @user, operation_type: "correction", currency: @booking.currency,
        operation_key: @payload.fetch("operation_key"), reason: @reason,
        metadata: { correction_type: "completed_room_charges", review_scope: scope_payload, review: @review, old_values: @old_values, new_values: financial_values })
    end

    def financial_values
      { booking: @booking.attributes.slice("total_amount", "manual_rate_override", "tax_lines", "tax_posting_snapshot"),
        room: @booking.booking_rooms.first.attributes.slice("subtotal", "nightly_rate_snapshot") }
    end

    def transaction_key(transaction)
      transaction.metadata["nightly_charge_key"].presence || transaction.metadata["reconciles_nightly_charge_key"].presence ||
        (transaction.catch_up_key.presence || transaction.metadata["catch_up_key"].presence)&.delete_prefix("catch_up:")
    end

    def fingerprint
      Digest::SHA256.hexdigest(JSON.generate({ old_values: @old_values, proposed: @snapshot.to_h, review: @review,
        ledger: @transactions.map { |row| row.attributes },
        dates: @date_records.values.map(&:attributes), folios: @folios.map(&:attributes),
        invoices: Invoice.where(booking_folio_id: @folios.map(&:id)).order(:id).map(&:attributes),
        receivables: ArInvoice.where(booking_folio_id: @folios.map(&:id)).order(:id).map(&:attributes),
        routes: @booking.folio_routing_rules.order(:id).map(&:attributes) }))
    end

    def scope_payload
      { "actor_id" => @user.id, "hotel_id" => @hotel.id, "booking_id" => @booking.id, "amounts" => @amounts, "reason" => @reason }
    end

    def completed_operation?(payload)
      FolioOperationLog.where(hotel: @hotel, booking: @booking, operation_type: "correction", operation_key: payload.fetch("operation_key"))
        .where("metadata->>'correction_type' = ?", "completed_room_charges")
        .where("metadata->'review_scope' = ?::jsonb", scope_payload.to_json).exists?
    end

    def verifier
      Rails.application.message_verifier(PURPOSE)
    end

    def review_result(message: nil)
      OpenStruct.new(success?: false, errors: [], review: @review,
        correction_review_token: verifier.generate(@payload, expires_in: 15.minutes, purpose: PURPOSE), review_message: message)
    end

    def success
      OpenStruct.new(success?: true, errors: [], booking: @booking)
    end
  end
end

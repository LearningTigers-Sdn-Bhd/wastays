# frozen_string_literal: true

module Bookings
  class PostClosedStayCharges
    CORRECTION_REQUIRED = "These changes affect charges already posted to a closed business date. Ask an authorized manager to complete an accounting correction before changing the stay."

    def self.call(**attributes)
      new(**attributes).call
    end

    def initialize(booking:, previous_check_in:, previous_check_out:, user:, correction_context: nil)
      @booking = booking
      @hotel = booking.hotel
      @previous_check_in = previous_check_in
      @previous_check_out = previous_check_out
      @user = user
      @correction_context = correction_context
    end

    def call
      unless @booking.status.in?(Booking::IN_HOUSE_STATUSES)
        @correction_context&.add(review([]), required: false)
        return
      end
      raise "Hotel has no current accounting business date." unless @hotel.current_business_date

      plans = closed_night_plans
      needs_correction = plans.any? { |plan| plan[:reverse].any? }
      if @correction_context
        @correction_context.add(review(plans), required: needs_correction)
        return if @correction_context.preview?
      elsif needs_correction
        raise CORRECTION_REQUIRED
      end

      plans.each do |plan|
        next if plan[:report].valid? && plan[:removed].empty?

        service = NightAudits::Financials::RepairCompletedNightlyCharges.new(
          night_audit: plan[:audit], booking: @booking, actor: @user,
          reason: @correction_context&.reason.presence || automatic_reason
        )
        result = if needs_correction && @correction_context
          service.call_for_stay_correction(removed_transactions: plan[:removed])
        else
          service.call_for_stay_update
        end
        raise result.error unless result.success?
      end
    end

    private

    def closed_night_plans
      (previous_dates | stay_dates).sort.filter_map do |date|
        record = @hotel.hotel_business_dates.find_by(business_date: date)
        if record.nil?
          raise "Missing accounting record for #{date}. Ask a manager to review Night Audit." if date < @hotel.current_business_date
          next
        end
        next if record.open?
        raise "Night Audit must be resolved for #{date} before changing this stay." unless record.closed_like?

        posted = nightly_transactions.includes(:booking_folio).where(posting_date: date).order(:id).to_a
        if @correction_context
          posted.select! { |transaction| charge_key(transaction).split(":", 4)[2].in?(%w[accommodation tax]) }
        end
        next if !stay_dates.include?(date) && posted.empty?
        raise "Closed folios cannot be corrected through stay dates." if posted.any? { |transaction| !transaction.booking_folio.open? }

        audit = @hotel.night_audits.find_by(business_date: date, status: "completed")
        raise "Completed Night Audit is missing for #{date}. Ask a manager to review Night Audit." unless audit

        report = Folios::Charges::NightlyChargeReconciliation.call(booking: @booking, business_date: date)
        report.entries.each do |entry|
          raise entry[:route].error unless entry[:route].success?
          if @correction_context && entry[:issues].any? && (!entry[:line][:charge_kind].in?(%w[accommodation tax]) || entry[:line][:transaction_type].to_s != "charge")
            raise "These charges require a separate folio correction. Only nightly room and tax charges can be corrected here."
          end
        end
        expected_ids = report.entries.flat_map { |entry| entry[:transactions].map(&:id) }
        removed = posted.reject { |transaction| expected_ids.include?(transaction.id) }
        reverse = removed + report.entries.flat_map do |entry|
          entry[:issues].empty? ? [] : entry[:transactions] - [ entry[:valid_transactions].min_by(&:id) ]
        end
        if reverse.any? { |transaction| !transaction.category.in?(%w[accommodation tax]) || !charge_key(transaction).split(":", 4)[2].in?(%w[accommodation tax]) }
          raise "These changes affect charges that require a separate folio correction. Only nightly room and tax charges can be corrected here."
        end
        { date: date, audit: audit, report: report, removed: removed, reverse: reverse }
      end
    end

    def review(plans)
      actions = plans.flat_map do |plan|
        reversed = plan[:reverse].map do |transaction|
          action("reverse", plan[:date], transaction.description, transaction.amount,
            folio_id: transaction.booking_folio_id, transaction_id: transaction.id,
            transaction_code_id: transaction.transaction_code_id, key: charge_key(transaction))
        end
        replacements = plan[:report].entries.filter_map do |entry|
          next if entry[:valid_transactions].any?
          line = entry[:line]
          action("post", plan[:date], line[:description], line[:amount],
            folio_id: entry[:route].folio.id, transaction_code_id: line[:transaction_code]&.id, key: entry[:nightly_charge_key])
        end
        reversed + replacements
      end
      forecasts = FolioForecastedCharge.where(source_booking_id: @booking.id)
        .nightly_financial.forecast.order(:stay_date, :charge_kind, :identity)
      actions += forecasts.filter_map do |forecast|
        next unless forecast.stay_date >= @hotel.current_business_date
        action("schedule", forecast.stay_date, forecast.description, forecast.amount,
          folio_id: forecast.booking_folio_id, key: [ forecast.charge_kind, forecast.identity ].join(":"))
      end
      {
        booking_id: @booking.id, status: @booking.status, reference: @booking.reservation_reference.presence || @booking.confirmation_token,
        currency: @booking.currency,
        proposed_room_total: @booking.booking_rooms.first&.subtotal.to_d.to_s("F"),
        proposed_tax_total: Booking.non_tourism_tax_total_for(@booking.tax_lines).to_d.to_s("F"),
        proposed_total_amount: @booking.total_amount.to_d.to_s("F"), old_dates: [ @previous_check_in.iso8601, @previous_check_out.iso8601 ],
        new_dates: [ @booking.check_in.iso8601, @booking.check_out.iso8601 ], actions: actions
      }
    end

    def action(kind, date, description, amount, **details)
      { action: kind, date: date.iso8601, description: description, amount: amount.to_d.to_s("F") }.merge(details)
    end

    def previous_dates
      @previous_dates ||= ScheduledStay.stay_dates(hotel: @hotel, check_in: @previous_check_in, check_out: @previous_check_out)
    end

    def stay_dates
      @stay_dates ||= ScheduledStay.stay_dates(hotel: @hotel, check_in: @booking.check_in, check_out: @booking.check_out)
    end

    def nightly_transactions
      FolioTransaction.joins(:booking_folio)
        .where(source_booking_id: @booking.id)
        .charge.where(voided_by_transaction_id: nil)
        .where("metadata ? 'nightly_charge_key' OR metadata ? 'reconciles_nightly_charge_key' OR catch_up_key IS NOT NULL OR metadata ? 'catch_up_key'")
    end

    def charge_key(transaction)
      transaction.metadata["nightly_charge_key"].presence || transaction.metadata["reconciles_nightly_charge_key"].presence ||
        (transaction.catch_up_key.presence || transaction.metadata["catch_up_key"].presence).to_s.delete_prefix("catch_up:")
    end

    def automatic_reason
      reference = @booking.reservation_reference.presence || @booking.confirmation_token
      "Automatically post missing closed-night charges after stay update for #{reference}: " \
        "#{previous_dates.join(', ')} to #{stay_dates.join(', ')}."
    end
  end
end

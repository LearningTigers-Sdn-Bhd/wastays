# frozen_string_literal: true

require "ostruct"

module Bookings
  class CreateStaffBooking
    class CreationFailed < StandardError; end

    def initialize(hotel:, common_params:, room_rows:, user:, booking_type: "reservation", posting_date: nil)
      @hotel = hotel
      @common_params = common_params.to_h.symbolize_keys
      @backdate_reason = @common_params.delete(:backdate_reason)
      @retroactive_reason = @common_params.delete(:retroactive_reason)
      @hotel_corporate_account_id = @common_params.delete(:hotel_corporate_account_id)
      @bill_tourism_tax_to_company = @common_params.delete(:bill_tourism_tax_to_company)
      @room_rows = Array(room_rows).map { |row| row.to_h.symbolize_keys }
      @user = user
      @booking_type = booking_type.presence || "reservation"
      @posting_date = posting_date
    end

    def call
      return failure("Unknown booking type.") unless @booking_type.in?(%w[reservation walk_in backdated_check_in])
      return failure("Add at least one room.") if @room_rows.empty?
      if @booking_type == "reservation"
        return failure("Each reservation row requires a room category.") if @room_rows.any? { |row| row[:room_type_id].blank? }
      elsif @room_rows.any? { |row| row[:room_type_id].blank? || row[:room_number].blank? }
        return failure("Each room row requires a room category and room number.")
      end
      room_numbers = @room_rows.pluck(:room_number).compact_blank.map(&:to_s)
      return failure("The same room cannot be selected twice.") if room_numbers.uniq.size != room_numbers.size

      bookings = []
      group_booking = nil

      ActiveRecord::Base.transaction do
        @room_rows.each do |row|
          result = CreateManualBooking.new(
            hotel: @hotel,
            params: child_params(row),
            user: @user,
            rate_tier: rate_tier(row[:rate_plan_id])
          ).call
          raise CreationFailed, Array(result.errors).to_sentence unless result.success?

          bookings << result.booking
        end

        if bookings.many?
          group_result = GroupBookings::CreateFromBookings.call(
            hotel: @hotel,
            bookings: bookings,
            attributes: group_attributes(bookings),
            actor: @user
          )
          raise CreationFailed, group_result.error unless group_result.success?

          group_booking = group_result.group_booking
          receive_group_payment!(group_booking, bookings) if record_payment?
        end

        transition_children!(bookings) unless @booking_type == "reservation"
        bill_room_charges_to_company!(bookings)
      end

      OpenStruct.new(success?: true, booking: bookings.first, bookings: bookings, group_booking: group_booking, errors: [])
    rescue CreationFailed, ActiveRecord::RecordInvalid => e
      Rails.logger.warn("Staff booking creation rolled back: #{e.message}")
      failure(e.message)
    end

    private

    def child_params(row)
      params = @common_params.merge(
        room_type_id: row[:room_type_id], room_number: row[:room_number], rate_plan_id: normalized_rate_plan_id(row[:rate_plan_id]),
        adults: row[:adults].presence || 1, children: row[:children].presence || 0,
        manual_rate_override: row[:manual_rate_override], posting_date: @posting_date,
        source: @booking_type == "reservation" ? @common_params[:source] : "walk_in",
        require_room_number: @booking_type != "reservation"
      )
      params[:record_payment] = false if @room_rows.many?
      params
    end

    def normalized_rate_plan_id(value)
      value.to_s.start_with?("tier_") ? value.to_s.split("_").last : value
    end

    def rate_tier(value)
      return :standard unless value.to_s.start_with?("tier_")

      value.to_s.split("_")[1] == "walk" ? :walk_in : value.to_s.split("_")[1].to_sym
    end

    def group_attributes(bookings)
      {
        name: @common_params[:guest_name].presence || "Group booking",
        status: "active", default_check_in: bookings.first.check_in, default_check_out: bookings.first.check_out,
        organizer_guest: bookings.first.booking_guests.find_by(is_primary: true)&.guest
      }
    end

    def record_payment?
      @common_params[:record_payment].to_s == "1" || @common_params[:record_payment] == true
    end

    def receive_group_payment!(group, bookings)
      amount = @common_params[:payment_amount].presence&.to_d || bookings.sum(&:total_amount)
      raise CreationFailed, "Payment amount must be greater than 0." unless amount.positive?

      receipt = GroupDeposits::Receive.call(
        group_booking: group, amount: amount, currency: bookings.first.currency || "MYR",
        payment_method: @common_params[:payment_method].presence || "cash", received_by: @user,
        external_reference: @common_params[:payment_reference].presence,
        metadata: { source: "staff_booking_creation" }
      )
      raise CreationFailed, receipt.error unless receipt.success?

      folios = bookings.map(&:booking_folio)
      weights = folios.index_with { |folio| [ folio.projected_outstanding_balance.to_d, 0.to_d ].max }
      total_weight = weights.values.sum
      raise CreationFailed, "Group payment cannot be allocated until room charges are available." unless total_weight.positive?

      remaining = amount
      manual_amounts = folios.each_with_index.to_h do |folio, index|
        value = index == folios.length - 1 ? remaining : ((amount * weights.fetch(folio)) / total_weight).round(2).clamp(0, remaining)
        remaining -= value
        [ folio.id.to_s, value ]
      end
      allocation = GroupDeposits::AllocateAcrossFolios.call(
        deposit: receipt.deposit, folios: folios, amount: amount, strategy: "manual", actor: @user, manual_amounts: manual_amounts
      )
      raise CreationFailed, allocation.error unless allocation.success?

      bookings.each do |booking|
        allocated = manual_amounts.fetch(booking.booking_folio.id.to_s, 0).to_d
        booking.update!(payment_status: allocated >= booking.total_amount.to_d ? "captured" : "partial") if allocated.positive?
      end
    end

    def transition_children!(bookings)
      bookings.each do |booking|
        result = TransitionStatus.new(
          booking: booking, status: "checked_in", timestamp: booking.check_in, user: @user,
          options: backdated? ? { override_night_audit: true, reason: @retroactive_reason.presence || @backdate_reason, backdate_reason_category: @backdate_reason, backdate_reason_details: @retroactive_reason } : {}
        ).call
        raise CreationFailed, result.error unless result.success?
      end
    end

    def backdated? = @booking_type == "backdated_check_in"

    # Bill room charges to the selected billing party. Room revenue is
    # *routed* to the party's folio; the guest's primary folio is never
    # reassigned, so it keeps incidentals and tourism tax.
    def bill_room_charges_to_company!(bookings)
      account_id = @hotel_corporate_account_id
      return if account_id.blank?

      bookings.each do |booking|
        result = FolioRouting::BillRoomChargesToCompany.call(
          booking: booking, actor: @user, hotel_corporate_account_id: account_id,
          bill_tourism_tax_to_company: @bill_tourism_tax_to_company
        )
        raise CreationFailed, result.error unless result.success?
      end
    end

    def failure(message)
      OpenStruct.new(success?: false, booking: nil, bookings: [], group_booking: nil, errors: [ message.presence || "Booking could not be created." ])
    end
  end
end

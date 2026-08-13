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
            user: @user
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
          if record_payment?
            receive_group_payment!(group_booking, bookings)
            bookings.each(&:reload)
          end
        end

        transition_children!(bookings) unless @booking_type == "reservation"
        receive_check_in_payment!(bookings) if collect_check_in_payment?
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
        room_type_id: row[:room_type_id], room_number: row[:room_number], rate_plan_id: row[:rate_plan_id],
        adults: row[:adults].presence || 1, children: row[:children].presence || 0,
        manual_rate_override: row[:manual_rate_override], posting_date: @posting_date,
        source: @booking_type == "reservation" ? @common_params[:source] : "walk_in",
        require_room_number: @booking_type != "reservation"
      )
      params[:record_payment] = record_payment? && !@room_rows.many?
      if backdated?
        params[:financial_posting_options] = {
          override_night_audit: true,
          reason: @retroactive_reason.presence || @backdate_reason
        }
      end
      params
    end

    def group_attributes(bookings)
      {
        name: @common_params[:guest_name].presence || "Group booking",
        status: "active", default_check_in: bookings.first.check_in, default_check_out: bookings.first.check_out,
        organizer_guest: bookings.first.booking_guests.find_by(is_primary: true)&.guest
      }
    end

    # One switch drives every collection on the sheet. Which service posts it
    # depends only on the booking type: reservations prepay (guest_advance),
    # walk-in and backdated check-ins collect on arrival (direct).
    def collect_payment?
      ActiveModel::Type::Boolean.new.cast(@common_params[:collect_payment])
    end

    def record_payment?
      @booking_type == "reservation" && collect_payment?
    end

    def receive_group_payment!(group, bookings)
      method_result = PaymentMethods::Eligibility.call(
        hotel: @hotel,
        id: @common_params[:hotel_payment_method_id],
        purpose: :guest_advance
      )
      raise CreationFailed, method_result.error unless method_result.success?

      result = Deposits::ConfiguredPrepayment.call(
        owner: group,
        folios: bookings.map(&:booking_folio),
        base_amount: bookings.sum(&:total_amount),
        payment_method_id: method_result.payment_method.id,
        actor: @user,
        external_reference: @common_params[:payment_reference].presence,
        posting_date: @posting_date,
        operation_key: "staff-group-booking:#{group.id}:payment"
      )
      raise CreationFailed, result.error unless result.success?
    end

    def transition_children!(bookings)
      bookings.each do |booking|
        options = backdated? ? {
          override_night_audit: true,
          reason: @retroactive_reason.presence || @backdate_reason,
          backdate_reason_category: @backdate_reason,
          backdate_reason_details: @retroactive_reason
        } : {}
        if immediate_check_in_collection?
          options[:attributes] = { tourism_tax_collected: tourism_tax_collected?(booking) }
          options[:security_deposit] = security_deposit_options if security_deposit_requested?
        end

        result = TransitionStatus.new(
          booking: booking, status: "checked_in", timestamp: booking.check_in, user: @user,
          options:
        ).call
        raise CreationFailed, result.error unless result.success?
      end
    end

    def backdated? = @booking_type == "backdated_check_in"

    def immediate_check_in_collection?
      @booking_type.in?(%w[walk_in backdated_check_in])
    end

    def tourism_tax_collected?(booking)
      return booking.tourism_tax? unless @common_params.key?(:tourism_tax_collected)

      ActiveModel::Type::Boolean.new.cast(@common_params[:tourism_tax_collected])
    end

    # The deposit shares the booking's single payment method; only the amount and
    # reference are its own.
    def security_deposit_options
      return unless security_deposit_requested?

      @common_params[:security_deposit].to_h.symbolize_keys
        .slice(:amount, :external_reference)
        .reverse_merge(amount: nil, external_reference: nil)
        .merge(hotel_payment_method_id: @common_params[:hotel_payment_method_id])
    end

    def security_deposit_requested?
      ActiveModel::Type::Boolean.new.cast(@common_params[:collect_security_deposit])
    end

    def collect_check_in_payment?
      immediate_check_in_collection? && collect_payment?
    end

    def check_in_payment_options
      {
        hotel_payment_method_id: @common_params[:hotel_payment_method_id],
        payment_reference: @common_params[:payment_reference]
      }
    end

    def receive_check_in_payment!(bookings)
      options = check_in_payment_options
      method_result = PaymentMethods::Eligibility.call(
        hotel: @hotel, id: options[:hotel_payment_method_id], purpose: :direct
      )
      raise CreationFailed, method_result.error unless method_result.success?

      bookings.each do |booking|
        result = Folios::Payments::PostConfiguredPayment.call(
          folio: booking.booking_folio,
          user: @user,
          payment_method_id: method_result.payment_method.id,
          base_amount: booking.total_amount,
          description: "Payment collected at check-in",
          posting_date: @posting_date,
          options: check_in_payment_posting_options(booking, options)
        )
        raise CreationFailed, result.error unless result.success?

        Deposits::SyncBookingPaymentStatus.call(booking)
      end
    end

    def check_in_payment_posting_options(booking, options)
      metadata = {
        source: "check_in_payment",
        reference: options[:payment_reference].to_s.strip.presence
      }.compact
      return { operation_key: "staff-check-in:#{booking.id}:payment", metadata: } unless backdated?

      {
        operation_key: "staff-check-in:#{booking.id}:payment",
        override_night_audit: true,
        correction_reason: "check_in_payment_on_retroactive_booking",
        correction_note: @retroactive_reason.presence || @backdate_reason.presence || "Payment collected for a backdated check-in.",
        metadata:
      }
    end

    # Bill room charges to the selected billing party. Room revenue is
    # *routed* to the party's folio; the guest's primary folio is never
    # reassigned, so it keeps incidentals and tourism tax.
    def bill_room_charges_to_company!(bookings)
      account_id = @hotel_corporate_account_id
      return if account_id.blank?

      bookings.each do |booking|
        result = Folios::Routing::BillRoomChargesToCompany.call(
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

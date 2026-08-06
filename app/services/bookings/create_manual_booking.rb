# frozen_string_literal: true

require "ostruct"

module Bookings
  class CreateManualBooking
    def initialize(hotel:, params:, user: nil, rate_tier: :standard)
      @hotel = hotel
      @params = params.dup
      @room_type_id = @params.delete(:room_type_id)
      @room_number = @params.delete(:room_number)
      @require_room_number = @params.delete(:require_room_number) != false

      @record_payment = @params.delete(:record_payment)
      @params.delete(:payment_method)
      @params.delete(:payment_amount) # Legacy input is intentionally ignored.
      @hotel_payment_method_id = @params.delete(:hotel_payment_method_id)
      @params.delete(:payment_method_type)
      @payment_reference = @params.delete(:payment_reference)
      @params.delete(:collect_payment)
      @params.delete(:tourism_tax_collected)
      @params.delete(:collect_security_deposit)
      @params.delete(:security_deposit)
      @existing_guest_id = @params.delete(:existing_guest_id)
      @guest_update_intent = @params.delete(:guest_update_intent)
      @rate_plan_id = @params.delete(:rate_plan_id)
      @apply_stop_sell_restriction = @params.delete(:apply_stop_sell_restriction)
      @apply_arrival_departure_restrictions = @params.delete(:apply_arrival_departure_restrictions)
      @apply_stay_length_restrictions = @params.delete(:apply_stay_length_restrictions)
      @posting_date = @params.delete(:posting_date)
      @financial_posting_options = @params.delete(:financial_posting_options).to_h.symbolize_keys

      @user = user
      @rate_tier = rate_tier
    end

    def call
      NightAudits::OperationalChangeGuard.call!(hotel: @hotel, action: :create_manual_booking)
      normalize_scheduled_stay!
      booking = @hotel.bookings.build(@params)
      selected_guest = selected_guest_from_param
      room_type = @hotel.room_types.find(@room_type_id)
      rate_plan = rate_plan_from_param(room_type)

      if @existing_guest_id.present? && selected_guest.blank?
        return OpenStruct.new(success?: false, errors: [ "Selected guest could not be found for this hotel." ])
      end

      if create_new_guest_intent?
        create_new_guest_error = validate_create_new_guest_intent(booking, selected_guest)
        return OpenStruct.new(success?: false, errors: [ create_new_guest_error ]) if create_new_guest_error.present?

        selected_guest = nil
      end

      if @rate_plan_id.present? && rate_plan.blank?
        return OpenStruct.new(success?: false, errors: [ "Selected rate plan could not be found for this room category." ])
      end

      unless rate_plan_allowed?(room_type, booking, rate_plan)
        return OpenStruct.new(success?: false, errors: [ "Selected rate plan is restricted for these stay dates." ])
      end

      apply_existing_guest_fields(booking, selected_guest) if selected_guest

      # 1. Validate Room Availability based on Grid Selection
      available_rooms = AvailableRoomNumbers.new(
        hotel: @hotel,
        room_type: room_type,
        check_in: booking.check_in,
        check_out: booking.check_out
      ).call

      unless @room_number.blank? && !@require_room_number || available_rooms.include?(@room_number.to_s)
        return OpenStruct.new(success?: false, errors: [ "Room #{@room_number} is no longer available for these dates." ])
      end

      # 1.1 Check for locks by others
      lock = @hotel.room_locks.active.find_by(room_number: @room_number) if @room_number.present?
      if lock && lock.user_id != @user&.id
        return OpenStruct.new(success?: false, errors: [ "Room #{@room_number} is currently being assigned by another staff member." ])
      end

      begin
        financial_snapshot = BuildFinancialSnapshot.new(
          hotel: @hotel,
          room_type: room_type,
          rate_plan: rate_plan,
          rate_tier: @rate_tier,
          check_in: booking.check_in,
          check_out: booking.check_out,
          guest_country: booking.guest_country,
          manual_total_amount: booking.manual_rate_override
        ).call
      rescue ArgumentError => e
        return OpenStruct.new(success?: false, errors: [ e.message ])
      end

      booking.total_amount = financial_snapshot.room_total + Booking.non_tourism_tax_total_for(financial_snapshot.tax_lines)
      booking.tax_lines = financial_snapshot.tax_lines
      booking.tax_posting_snapshot = financial_snapshot.tax_posting_snapshot
      tourism_tax = booking.tax_lines.find { |tax| tax["type"].to_s == "tourism_tax" }
      booking.tourism_tax_amount = tourism_tax ? tourism_tax["amount"].to_d : 0
      booking.tourism_tax_applied = booking.tourism_tax_amount.positive?
      # The creation service saves before the immediate check-in transition. Keep
      # the persisted booking valid while that transition decides whether the
      # applicable tourism tax was collected.
      booking.tourism_tax_collected = false

      booking.status = "confirmed"
      booking.hotel_snapshot = @hotel.booking_snapshot.merge("room_number" => @room_number)

      if record_payment?
        if booking.total_amount.to_d <= 0
          return OpenStruct.new(success?: false, errors: [ "Payment amount must be greater than 0." ])
        end

        payment_method_result = PaymentMethods::Eligibility.call(
          hotel: @hotel, id: @hotel_payment_method_id, purpose: :guest_advance
        )
        return OpenStruct.new(success?: false, errors: [ payment_method_result.error ]) unless payment_method_result.success?

        @hotel_payment_method_id = payment_method_result.payment_method.id
        booking.payment_status = "pending"
      else
        booking.payment_status = "pending"
      end

      begin
        ActiveRecord::Base.transaction do
          booking.booking_rooms.build(
            room_type: room_type,
            rate_plan: rate_plan,
            subtotal: financial_snapshot.room_total,
            room_type_snapshot: room_type.as_json,
            nightly_rate_snapshot: financial_snapshot.nightly_rate_snapshot
          )

          if booking.save
            if @room_number.present?
              assignment_result = Bookings::AssignRoom.new(
                booking: booking,
                room_number: @room_number,
                user: @user
              ).call

              raise assignment_result.error unless assignment_result.success?
            end

            InventoryManager.new(booking).deduct
            sync_guest(booking, selected_guest)
            Folios::Lifecycle::InitializeForBooking.call(booking: booking, user: @user, lock: false)
            record_prepayment!(booking) if record_payment?
            booking.reload if record_payment?

            # Record Audit Log
            Bookings::RecordAuditLog.call!(
              auditable: booking,
              user: @user,
              action_type: "create",
              source: "staff"
            )

            # Trigger Webhooks
            Bookings::WebhookTriggerService.new(booking).trigger(:booking_confirmed)
            Notifications::Dispatcher.new(event: :booking_confirmed, booking: booking).call

            # Trigger Channex CRS Sync if connected
            if @hotel.preferred_channel_manager.present?
              adapter = ChannelManagers::SyncOrchestrator.adapter_for(@hotel)
              adapter.push_booking(booking)
            end
          else
            raise booking.errors.full_messages.to_sentence
          end
        end
        OpenStruct.new(success?: true, booking: booking)
      rescue => e
        OpenStruct.new(success?: false, errors: [ e.message ])
      end
    rescue NightAudits::OperationalChangeGuard::OperationalChangeBlocked => e
      OpenStruct.new(success?: false, errors: [ e.message ])
    end

    private

    def record_prepayment!(booking)
      result = Deposits::ConfiguredPrepayment.call(
        owner: booking,
        folios: [ booking.booking_folio ],
        base_amount: booking.total_amount,
        payment_method_id: @hotel_payment_method_id,
        actor: @user,
        external_reference: @payment_reference.presence,
        posting_date: @posting_date,
        operation_key: "manual-booking:#{booking.id}:prepayment"
      )
      raise result.error unless result.success?
    end

    def record_payment?
      @record_payment == "1" || @record_payment == true
    end

    def normalize_scheduled_stay!
      %i[check_in check_out].each do |kind|
        next if @params[kind].blank?

        @params[kind] = ScheduledStay.at_hotel_time(hotel: @hotel, value: @params[kind], kind: kind)
      end
    end

    def selected_guest_from_param
      return if @existing_guest_id.blank?

      Guest
        .left_outer_joins(:bookings)
        .where(id: @existing_guest_id)
        .where("guests.created_by_hotel_id = :hotel_id OR bookings.hotel_id = :hotel_id", hotel_id: @hotel.id)
        .distinct
        .first
    end

    def rate_plan_from_param(room_type)
      return if @rate_plan_id.blank?

      room_type.rate_plans.find_by(id: @rate_plan_id)
    end

    def rate_plan_allowed?(room_type, booking, rate_plan)
      return true if rate_plan.blank?

      RateOptions.new(
        room_type: room_type,
        check_in: booking.check_in,
        check_out: booking.check_out,
        apply_stop_sell: @apply_stop_sell_restriction,
        apply_arrival_departure: @apply_arrival_departure_restrictions,
        apply_stay_length: @apply_stay_length_restrictions
      ).allowed?(rate_plan)
    end

    def apply_existing_guest_fields(booking, guest)
      booking.assign_attributes(
        guest_name: booking.guest_name.presence || guest.name,
        guest_email: booking.guest_email.presence || guest.email,
        guest_phone: booking.guest_phone.presence || guest.phone,
        guest_country: booking.guest_country.presence || guest.country,
        guest_gender: booking.guest_gender.presence || guest.gender,
        guest_document_type: booking.guest_document_type.presence || guest.document_type,
        guest_government_id: booking.guest_government_id.presence || guest.government_id,
        guest_date_of_birth: booking.guest_date_of_birth.presence || guest.date_of_birth
      )
    end

    def sync_guest(booking, guest = nil)
      explicitly_selected = guest.present?

      if create_new_guest_intent?
        guest = create_new_guest!(booking)
      elsif !guest
        guest = automatically_matched_guest(booking) || create_new_guest!(booking)
      end

      if guest && explicitly_selected && update_existing_guest_intent?
        update_guest_from_booking!(guest, booking)
      end

      if guest && !booking.booking_guests.exists?(guest: guest)
        booking.booking_guests.create!(guest: guest, is_primary: true)
      end
    end

    def create_new_guest_intent?
      @guest_update_intent == "create_new"
    end

    def automatically_matched_guest(booking)
      email = normalized_email(booking.guest_email)
      guest = Guest.find_by(email: email) if email.present?
      return guest if guest

      phone = normalized_phone(booking.guest_phone)
      Guest.find_by(phone: phone) if phone.present?
    end

    def update_existing_guest_intent?
      @guest_update_intent == "update_existing"
    end

    def validate_create_new_guest_intent(booking, selected_guest)
      if selected_guest && matching_identity_with_selected_guest?(booking, selected_guest)
        return "This guest has the same email, phone, or IC/passport number as the selected guest. Update the existing guest information instead."
      end

      conflict = identity_conflict_guest(booking, exclude_guest: selected_guest)
      return "Another guest already exists with this email, phone, or IC/passport number. Select that guest instead." if conflict

      nil
    end

    def matching_identity_with_selected_guest?(booking, selected_guest)
      normalized_email(booking.guest_email).present? && normalized_email(booking.guest_email) == normalized_email(selected_guest.email) ||
        normalized_phone(booking.guest_phone).present? && normalized_phone(booking.guest_phone) == normalized_phone(selected_guest.phone) ||
        normalized_government_id(booking.guest_government_id).present? && normalized_government_id(booking.guest_government_id) == normalized_government_id(selected_guest.government_id)
    end

    def identity_conflict_guest(booking, exclude_guest: nil)
      candidates = []
      candidates << Guest.find_by(email: normalized_email(booking.guest_email)) if normalized_email(booking.guest_email).present?
      candidates << Guest.find_by(phone: normalized_phone(booking.guest_phone)) if normalized_phone(booking.guest_phone).present?
      if normalized_government_id(booking.guest_government_id).present?
        candidates << Guest.find_by(government_id: normalized_government_id(booking.guest_government_id))
      end

      candidates.compact.find { |guest| exclude_guest.blank? || guest.id != exclude_guest.id }
    end

    def create_new_guest!(booking)
      Guest.create!(
        name: booking.guest_name,
        email: booking.guest_email,
        phone: booking.guest_phone,
        country: booking.guest_country.presence || @hotel.country,
        gender: booking.guest_gender,
        document_type: booking.guest_document_type,
        government_id: booking.guest_government_id,
        date_of_birth: booking.guest_date_of_birth,
        created_by_hotel_id: @hotel.id
      )
    end

    def update_guest_from_booking!(guest, booking)
      updates = {}
      updates[:name] = booking.guest_name if booking.guest_name.present? && guest.name != booking.guest_name
      updates[:email] = booking.guest_email if booking.guest_email.present? && guest.email != booking.guest_email
      updates[:phone] = booking.guest_phone if booking.guest_phone.present? && guest.phone != booking.guest_phone
      updates[:country] = booking.guest_country if booking.guest_country.present? && guest.country != booking.guest_country
      updates[:gender] = booking.guest_gender if booking.guest_gender.present? && guest.gender != booking.guest_gender
      if booking.guest_date_of_birth.present? && guest.date_of_birth != booking.guest_date_of_birth
        updates[:date_of_birth] = booking.guest_date_of_birth
      end

      guest.update!(updates) if updates.any?
    end
    def normalized_email(value)
      value.to_s.downcase.strip
    end

    def normalized_phone(value)
      value.to_s.strip
    end

    def normalized_government_id(value)
      value.to_s.downcase.strip
    end
  end
end

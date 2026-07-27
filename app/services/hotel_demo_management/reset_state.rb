# frozen_string_literal: true

module HotelDemoManagement
  class ResetState
    Result = Struct.new(:success?, :hotel, :error, keyword_init: true)

    NoopLogger = Struct.new do
      def puts(*) = nil
    end

    def self.delete_ai_concierge_data(hotel, logger: NoopLogger.new)
      prospect_count = hotel.prospects.count
      logger.puts "Deleting #{prospect_count} prospects with their conversation states and messages..."
      hotel.prospects.destroy_all
    end

    def initialize(hotel:, logger: NoopLogger.new, embed: false)
      @hotel = hotel
      @logger = logger
      @embed = embed
    end

    def call
      setup_error = validate_room_setup
      return failure(setup_error) if setup_error

      with_manual_embedding_control do
        ActiveRecord::Base.transaction do
          reset_hotel_settings
          reset_hotel_taxes
          reset_gl_mappings
          delete_audit_logs
          delete_journal_batches
          delete_night_audits
          reset_business_date_authority
          delete_bookings
          delete_group_bookings
          reset_rates_and_inventories
          reset_room_statuses
          self.class.delete_ai_concierge_data(@hotel, logger: @logger)
          reset_nearby_attractions
          seed_knowledge_documents
          enqueue_embeddings
          enqueue_channel_manager_sync
        end
      end

      success
    rescue StandardError => e
      failure(e.message)
    end

    private

    def success
      Result.new(success?: true, hotel: @hotel)
    end

    def failure(error)
      Result.new(success?: false, hotel: @hotel, error: error)
    end

    def with_manual_embedding_control
      previous_value = Thread.current[:skip_hotel_knowledge_embedding_enqueue]
      Thread.current[:skip_hotel_knowledge_embedding_enqueue] = true
      yield
    ensure
      Thread.current[:skip_hotel_knowledge_embedding_enqueue] = previous_value
    end

    def validate_room_setup
      room_types = @hotel.room_types.to_a
      return "Hotel must have at least one room type before demo state can be reset." if room_types.empty?

      invalid_room_type = room_types.find { |room_type| room_type.room_numbers.blank? }
      return "Room type '#{invalid_room_type.name}' must have at least one room number." if invalid_room_type

      invalid_base_price = room_types.find { |room_type| room_type.base_price.blank? || room_type.base_price.negative? }
      return "Room type '#{invalid_base_price.name}' must have a valid base price." if invalid_base_price

      invalid_quantity = room_types.find { |room_type| room_type.quantity.blank? || room_type.quantity.negative? }
      return "Room type '#{invalid_quantity.name}' must have a valid quantity." if invalid_quantity

      nil
    end

    def reset_hotel_settings
      @logger.puts "Resetting business hours, grace period, amenities, and taxes..."
      @hotel.update!(
        time_zone: "Kuala Lumpur",
        business_starts_at: "08:00",
        business_ends_at: "02:00",
        arrival_grace_period: 7200,
        amenities: %w[wifi swimming_pool fitness_center spa_wellness_centre laundry],
        tourism_tax_enabled: true,
        tourism_tax_amount: 10.0,
        sst_enabled: true
      )
    end

    def reset_hotel_taxes
      @logger.puts "Resetting hotel taxes..."
      BookingTaxInclusionOverride.where(hotel_id: @hotel.id).delete_all
      @hotel.hotel_taxes.destroy_all
      @hotel.hotel_taxes.create!([
        { name: "Service Tax", rate_type: "percentage", amount: 8.0, enabled: true, foreign_guests_only: false },
        { name: "Service Charge", rate_type: "percentage", amount: 10.0, enabled: true, foreign_guests_only: false }
      ])
    end

    def reset_gl_mappings
      @logger.puts "Resetting General Ledger mappings..."
      Financials::EnsureDefaultGlMaps.call(@hotel)
    end

    def delete_audit_logs
      @logger.puts "Force deleting #{FinancialAuditEvent.where(hotel_id: @hotel.id).count} immutable audit events..."
      FinancialAuditEvent.where(hotel_id: @hotel.id).delete_all

      @logger.puts "Deleting operational and audit logs..."
      BookingAuditLog.where(hotel_id: @hotel.id).delete_all
      InventoryAuditLog.where(hotel_id: @hotel.id).delete_all
      RoomOperationalAuditLog.where(hotel_id: @hotel.id).delete_all
      NotificationDelivery.where(hotel_id: @hotel.id).delete_all
    end

    def delete_journal_batches
      journal_batch_count = @hotel.journal_batches.count
      @logger.puts "Destroying #{journal_batch_count} journal batches..."
      @hotel.journal_batches.destroy_all
    end

    def delete_night_audits
      night_audit_ids = @hotel.night_audits.ids
      night_audit_count = night_audit_ids.size

      linked_transactions = FolioTransaction.where(night_audit_id: night_audit_ids)
      linked_transaction_count = linked_transactions.count
      if linked_transaction_count > 0
        @logger.puts "Clearing night audit links from #{linked_transaction_count} immutable transactions..."
        linked_transactions.update_all(night_audit_id: nil, updated_at: Time.current)
      end

      @logger.puts "Destroying #{night_audit_count} night audits..."
      @hotel.night_audits.destroy_all
    end

    def reset_business_date_authority
      business_date_count = @hotel.hotel_business_dates.count
      @logger.puts "Resetting #{business_date_count} business dates and restoring accounting-date authority..."
      BusinessDates::ResetAuthority.call!(hotel: @hotel)
    end

    def delete_bookings
      booking_ids = @hotel.bookings.pluck(:id)
      folio_ids = BookingFolio.where(booking_id: booking_ids).pluck(:id)
      billing_party_ids = BookingBillingParty.where(booking_id: booking_ids).pluck(:id)

      operation_log_count = FolioOperationLog.where(booking_id: booking_ids).count
      if operation_log_count > 0
        @logger.puts "Force deleting #{operation_log_count} immutable folio operation logs..."
        FolioOperationLog.where(booking_id: booking_ids).delete_all
      end

      routing_rule_count = FolioRoutingRule.where(booking_id: booking_ids).count
      if routing_rule_count > 0
        @logger.puts "Deleting #{routing_rule_count} folio routing rules..."
        FolioRoutingRule.where(booking_id: booking_ids).delete_all
      end

      delete_accounts_receivable_data
      delete_deposit_data

      forecasted_count = FolioForecastedCharge.where(booking_folio_id: folio_ids).count
      if forecasted_count > 0
        @logger.puts "Destroying #{forecasted_count} forecasted charges..."
        FolioForecastedCharge.where(booking_folio_id: folio_ids).delete_all
      end

      @logger.puts "Force deleting #{FolioTransaction.where(booking_folio_id: folio_ids).count} immutable transactions..."
      FolioTransaction.where(booking_folio_id: folio_ids).delete_all

      @logger.puts "Deleting #{PaymentTransaction.where(booking_id: booking_ids).count} payment transactions..."
      PaymentTransaction.where(booking_id: booking_ids).destroy_all

      folio_count = BookingFolio.where(id: folio_ids).count
      @logger.puts "Force deleting #{folio_count} booking folios..."
      BookingFolio.where(id: folio_ids).delete_all

      billing_party_count = billing_party_ids.size
      if billing_party_count > 0
        @logger.puts "Deleting #{billing_party_count} booking billing parties..."
        BookingBillingTerms.where(booking_billing_party_id: billing_party_ids).delete_all
        BookingBillingParty.where(id: billing_party_ids).delete_all
      end

      lineage_scope = LegacyBookingSplitLineage.where(legacy_booking_id: booking_ids)
        .or(LegacyBookingSplitLineage.where(child_booking_id: booking_ids))
      lineage_count = lineage_scope.count
      if lineage_count > 0
        @logger.puts "Force deleting #{lineage_count} immutable legacy booking split lineages..."
        lineage_scope.delete_all
      end

      booking_count = @hotel.bookings.count
      @logger.puts "Destroying #{booking_count} bookings..."
      @hotel.bookings.destroy_all
    end

    def delete_group_bookings
      group_booking_ids = @hotel.group_bookings.ids
      return if group_booking_ids.empty?

      GroupBillingChangeBatch.where(group_booking_id: group_booking_ids).delete_all
      @logger.puts "Destroying #{group_booking_ids.size} group bookings..."
      @hotel.group_bookings.destroy_all
    end

    def delete_accounts_receivable_data
      invoice_ids = @hotel.ar_invoices.ids
      payment_ids = @hotel.ar_payments.ids
      submission_ids = @hotel.ar_payment_submissions.ids
      intent_ids = CorporateArPaymentIntent.where(hotel_id: @hotel.id).ids
      allocation_ids = ArPaymentAllocation.where(ar_invoice_id: invoice_ids)
        .or(ArPaymentAllocation.where(ar_payment_id: payment_ids)).ids

      ar_record_count = invoice_ids.size + payment_ids.size + submission_ids.size + intent_ids.size
      return if ar_record_count.zero?

      @logger.puts "Force deleting accounts receivable operations..."
      ArPaymentAllocationReversal.where(ar_payment_allocation_id: allocation_ids).delete_all
      ArPaymentSubmissionAllocation.where(ar_payment_submission_id: submission_ids).delete_all
      ArPaymentSubmissionAllocation.where(ar_invoice_id: invoice_ids).delete_all
      ArPaymentAllocation.where(id: allocation_ids).delete_all
      @hotel.ar_payment_submissions.destroy_all
      PaymentTransaction.where(ar_payment_id: payment_ids)
        .or(PaymentTransaction.where(corporate_ar_payment_intent_id: intent_ids)).delete_all
      CorporateArPaymentIntent.where(id: intent_ids).delete_all
      ArPayment.where(id: payment_ids).delete_all
      ArInvoice.where(id: invoice_ids).delete_all
    end

    def delete_deposit_data
      deposit_ids = Deposit.where(hotel_id: @hotel.id).ids
      return if deposit_ids.empty?

      movement_count = DepositMovement.where(deposit_id: deposit_ids).count
      @logger.puts "Force deleting #{movement_count} immutable deposit movements..."
      DepositMovement.where(deposit_id: deposit_ids).delete_all

      @logger.puts "Deleting #{deposit_ids.size} deposits..."
      Deposit.where(id: deposit_ids).delete_all
    end

    def reset_rates_and_inventories
      hotel_date = Time.current.in_time_zone(@hotel.hotel_time_zone).to_date
      @start_date = hotel_date - 1.year
      @end_date = hotel_date + 1.year

      @logger.puts "Resetting rates and inventories from #{@start_date} to #{@end_date}..."
      @hotel.room_types.each do |room_type|
        standard_plan = ensure_rate_plan(room_type, "Standard Rate")
        non_ref_plan = ensure_rate_plan(room_type, "Non-Refundable Rate")

        base_price = room_type.base_price
        @logger.puts "  -> Configuring rates and inventories for #{room_type.name} (Base: #{base_price})..."

        RoomRate.where(room_type_id: room_type.id, date: @start_date..@end_date).delete_all
        RoomInventory.where(room_type_id: room_type.id, date: @start_date..@end_date).delete_all

        rates_to_insert = []
        inventories_to_insert = []
        (@start_date..@end_date).each do |date|
          now = Time.current
          rates_to_insert << {
            room_type_id: room_type.id,
            rate_plan_id: standard_plan.id,
            date: date,
            price: base_price,
            currency: standard_plan.currency,
            created_at: now,
            updated_at: now
          }
          rates_to_insert << {
            room_type_id: room_type.id,
            rate_plan_id: non_ref_plan.id,
            date: date,
            price: (base_price * 0.9).round(2),
            currency: non_ref_plan.currency,
            created_at: now,
            updated_at: now
          }
          inventories_to_insert << {
            room_type_id: room_type.id,
            date: date,
            quantity: room_type.quantity,
            status: "open",
            available_room_numbers: room_type.room_numbers,
            created_at: now,
            updated_at: now
          }
        end

        RoomRate.insert_all(rates_to_insert) if rates_to_insert.any?
        RoomInventory.insert_all(inventories_to_insert) if inventories_to_insert.any?
      end
    end

    def ensure_rate_plan(room_type, name)
      rate_plan = @hotel.rate_plans.find_or_create_by!(name: name) do |plan|
        plan.sell_mode = "per_room"
        plan.currency = @hotel.default_currency || "MYR"
      end

      room_type.room_type_rate_plans.find_or_create_by!(rate_plan: rate_plan)

      rate_plan
    end

    def reset_room_statuses
      @logger.puts "Resetting room statuses..."
      @hotel.room_types.each do |room_type|
        room_type.room_statuses.update_all(status: "ready", last_changed_at: Time.current, updated_at: Time.current)

        expected_room_numbers = room_type.room_numbers.map(&:to_s)
        existing_statuses = room_type.room_statuses.pluck(:room_number)

        missing_numbers = expected_room_numbers - existing_statuses
        if missing_numbers.any?
          @logger.puts "  -> #{room_type.name}: Adding statuses for #{missing_numbers.join(', ')}"
          missing_numbers.each do |num|
            room_type.room_statuses.create!(
              hotel: @hotel,
              room_number: num,
              status: "ready"
            )
          end
        end

        orphan_numbers = existing_statuses - expected_room_numbers
        next if orphan_numbers.blank?

        @logger.puts "  -> #{room_type.name}: Removing orphaned statuses for #{orphan_numbers.join(', ')}"
        room_type.room_statuses.where(room_number: orphan_numbers).destroy_all
      end
    end

    def reset_nearby_attractions
      @logger.puts "Resetting nearby attractions..."
      @hotel.nearby_attractions.destroy_all
      @hotel.nearby_attractions.create!([
        { name: "City Centre", description: "Explore the vibrant city centre with shops, restaurants, and cultural landmarks.", address: "City Centre", city: @hotel.city, country: @hotel.country },
        { name: "Local Market", description: "Experience local life and find unique souvenirs at the bustling market.", address: "Market Street", city: @hotel.city, country: @hotel.country },
        { name: "City Park", description: "Enjoy a relaxing day surrounded by nature.", address: "Park Avenue", city: @hotel.city, country: @hotel.country }
      ])
    end

    def seed_knowledge_documents
      @logger.puts "Deleting knowledge documents..."
      @hotel.knowledge_documents.destroy_all

      @logger.puts "Seeding sample FAQ and policy documents..."
      seed_faq_document("Booking & Reservations", booking_qa)
      seed_faq_document("Amenities & Services", amenities_qa)
      seed_faq_document("Transportation", transport_qa)
      seed_policy_document("Check-in & Check-out", "Check-in time: 3:00 PM. Check-out time: 11:00 AM. A valid government-issued ID and credit card are required at check-in. Late check-out may be available upon request and is subject to additional charges. Early check-in is based on availability.")
      seed_policy_document("Cancellation Policy", "Free cancellation up to 24 hours before arrival. Cancellations made within 24 hours of arrival will be charged the first night's stay. No-show reservations will be charged the full booking amount.")
      seed_policy_document("House Rules", "Quiet hours are from 10:00 PM to 8:00 AM. Smoking is prohibited in all indoor areas. Pets are not allowed. Visitors must register at the front desk. The hotel reserves the right to refuse service to any guest.")

      @logger.puts "Seeded #{@hotel.knowledge_documents.count} knowledge documents."
    end

    def seed_faq_document(title, qa_pairs)
      document = @hotel.knowledge_documents.create!(
        title: title,
        source_type: "text",
        category: "faq",
        language: "en",
        embedding_status: "pending",
        tags: [],
        effective_date: nil,
        metadata: { "qa_pairs" => qa_pairs },
        content: qa_pairs.values.map { |pair| "Q: #{pair['question']}\nA: #{pair['answer']}" }.join("\n\n")
      )
      document.chunks.create!(qa_pairs.values.each_with_index.map { |pair, index|
        { content: "Q: #{pair['question']}\nA: #{pair['answer']}", chunk_index: index }
      })
    end

    def seed_policy_document(title, content)
      document = @hotel.knowledge_documents.create!(
        title: title,
        source_type: "text",
        category: "policy",
        language: "en",
        embedding_status: "pending",
        tags: [],
        effective_date: nil,
        content: content
      )
      document.chunks.create!(content: document.content, chunk_index: 0)
    end

    def enqueue_embeddings
      return unless @embed && @hotel.ai_concierge_enabled?

      pending_docs = @hotel.knowledge_documents.where(embedding_status: "pending")
      return if pending_docs.none?

      @logger.puts "Enqueuing embedding generation for #{pending_docs.count} knowledge documents..."
      pending_docs.find_each do |doc|
        HotelKnowledges::GenerateEmbeddingsJob.perform_later(doc.id)
      end
    end

    def enqueue_channel_manager_sync
      return if @hotel.preferred_channel_manager.blank?

      @logger.puts "Triggering Channel Manager Sync..."
      ChannelManagers::SyncJob.perform_later(@hotel.id, @start_date, @end_date)
    end

    def booking_qa
      {
        "0" => { "question" => "What are your check-in and check-out times?",
                 "answer" => "Check-in is from 3:00 PM and check-out is by 11:00 AM. Early check-in and late check-out are subject to availability." },
        "1" => { "question" => "Can I modify or cancel my reservation?",
                 "answer" => "Yes, modifications and cancellations are accepted up to 24 hours before arrival without charge. Late cancellations may incur a one-night fee." },
        "2" => { "question" => "Do you accommodate early check-in requests?",
                 "answer" => "Early check-in is subject to availability. You may request it at the time of booking or contact the front desk on the day of arrival." }
      }
    end

    def amenities_qa
      {
        "0" => { "question" => "What are the swimming pool operating hours?",
                 "answer" => "Our swimming pool is open daily from 7:00 AM to 9:00 PM." },
        "1" => { "question" => "Is Wi-Fi available for guests?",
                 "answer" => "Yes, complimentary high-speed Wi-Fi is available throughout the property. Simply connect to the 'Guest Network' and enter your room number." },
        "2" => { "question" => "Do you have a spa or fitness centre?",
                 "answer" => "Yes, we offer a full-service spa (open 10:00 AM to 8:00 PM) and a 24-hour fitness centre. Spa appointments are recommended." },
        "3" => { "question" => "Is room service available?",
                 "answer" => "Yes, room service is available from 6:30 AM to 10:30 PM daily. A menu is available in your room or via the in-room tablet." }
      }
    end

    def transport_qa
      {
        "0" => { "question" => "Do you offer airport transfers?",
                 "answer" => "Yes, we provide airport transfer services. Please arrange at least 24 hours in advance by contacting our concierge." },
        "1" => { "question" => "Is parking available?",
                 "answer" => "Yes, complimentary valet and self-parking are available for all guests." },
        "2" => { "question" => "Is there a shuttle service to nearby attractions?",
                 "answer" => "Yes, we operate a complimentary shuttle to the city centre and popular attractions. The schedule is available at the concierge desk." }
      }
    end
  end
end

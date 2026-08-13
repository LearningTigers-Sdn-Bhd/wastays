# frozen_string_literal: true

module Onboarding
  class SubmissionSnapshot
    Result = Data.define(:data, :digest)

    def self.call(hotel:, rates_coverage: nil)
      new(hotel:, rates_coverage:).call
    end

    def initialize(hotel:, rates_coverage: nil)
      @hotel = hotel
      @rates_coverage = rates_coverage
    end

    def call
      data = deep_sort(snapshot)
      Result.new(data:, digest: Digest::SHA256.hexdigest(JSON.generate(data)))
    end

    private

    attr_reader :hotel

    def snapshot
      {
        "version" => OnboardingSubmission::SNAPSHOT_VERSION,
        "property" => property_snapshot,
        "sections" => section_snapshot,
        "staff" => staff_snapshot,
        "taxes" => tax_snapshot,
        "room_revenue" => room_revenue_snapshot,
        "rooms" => room_snapshot,
        "rates" => rate_snapshot,
        "commercial" => commercial_snapshot,
        "ota_handover" => ota_snapshot
      }
    end

    def property_snapshot
      hotel.attributes.slice(
        "name", "address", "city", "country", "star_rating", "time_zone",
        "default_currency", "contact_email", "contact_phone", "fixed_line_number", "whatsapp_number",
        "sell_mode", "preferred_channel_manager"
      ).merge(
        "amenities" => Array(hotel.amenities).sort,
        "photo_count" => hotel.photos.attachments.size,
        "featured_photo_supplied" => hotel.featured_photo_attachment_id.present?
      )
    end

    def section_snapshot
      hotel.onboarding_sections.in_journey_order.to_h do |section|
        [ section.section_key, {
          "state" => section.state,
          "decision" => section.decision_metadata.except("placeholder")
        } ]
      end
    end

    def staff_snapshot
      hotel.onboarding_staff_drafts.includes(:role).order(:created_at, :id).map do |draft|
        {
          "name" => draft.name,
          "email" => draft.email,
          "role" => draft.role.name,
          "send_invitation" => draft.send_invitation
        }
      end
    end

    def tax_snapshot
      hotel.hotel_taxes.order(:created_at, :id).map do |tax|
        tax.attributes.slice("name", "code", "charge_type", "rate_type", "amount", "enabled", "foreign_guests_only")
      end
    end

    def room_revenue_snapshot
      code = TransactionCodes::Resolver.for(hotel).room_revenue
      {
        "tax_rule_keys" => code&.tax_rule_keys.to_a.sort,
        "tax_rule_application" => hotel.hotel_transaction_configuration&.room_revenue_tax_rule_application
      }
    end

    def room_snapshot
      hotel.room_types.order(:created_at, :id).map do |room|
        room.attributes.slice(
          "name", "quantity", "max_adults", "max_children", "base_price",
          "room_number_mode", "smoking_allowed", "pets_allowed"
        ).merge("amenities" => Array(room.amenities).sort, "room_numbers" => room.room_numbers.sort)
      end
    end

    def rate_snapshot
      coverage = @rates_coverage || Rates::SetupCoverage.call(hotel: hotel)
      {
        "coverage" => {
          "start_date" => coverage.start_date.iso8601,
          "end_date" => coverage.end_date.iso8601,
          "expires_on" => coverage.expires_on&.iso8601,
          "configured_percentage" => coverage.configured_percentage.to_s,
          "sellable_percentage" => coverage.sellable_percentage.to_s,
          "complete" => coverage.complete?
        },
        "plans" => hotel.rate_plans.active.order(:created_at, :id).map do |plan|
          plan.attributes.slice("name", "kind", "currency", "sell_mode", "base_occupancy")
        end
      }
    end

    def commercial_snapshot
      {
        "extra_charges" => hotel.hotel_extra_charges.includes(:transaction_code).ordered.map do |charge|
          { "name" => charge.name, "code" => charge.code, "charging_unit" => charge.charging_unit,
            "rate_value" => charge.rate_value&.to_s, "active" => charge.active? }
        end,
        "discounts" => hotel.hotel_discounts.includes(:transaction_code).ordered.map do |discount|
          { "name" => discount.name, "code" => discount.code, "pricing_type" => discount.pricing_type,
            "rate_value" => discount.rate_value&.to_s, "application_scope" => discount.application_scope }
        end,
        "payment_methods" => hotel.hotel_payment_methods.includes(:transaction_code).ordered.map do |method|
          { "name" => method.name, "code" => method.code, "type" => method.payment_method_type,
            "active" => method.active?, "guest_advance" => method.guest_advance? }
        end,
        "corporate_accounts" => hotel.onboarding_corporate_drafts.order(:created_at, :id).map do |draft|
          { "company_name" => draft.company_name, "email" => draft.email, "account_type" => draft.account_type,
            "send_invitation" => draft.send_invitation }
        end
      }
    end

    # Deliberately never read the encrypted username or password. Admin review
    # only needs to know which handovers exist; the later connection tool owns
    # sensitive credential access.
    def ota_snapshot
      hotel.hotel_ota_credentials.ordered.pluck(:channel_name).map do |channel_name|
        { "channel_name" => channel_name, "credentials_supplied" => true }
      end
    end

    def deep_sort(value)
      case value
      when Hash then value.to_h { |key, nested| [ key.to_s, deep_sort(nested) ] }.sort.to_h
      when Array then value.map { |nested| deep_sort(nested) }
      when BigDecimal then value.to_s("F")
      when Date, Time, ActiveSupport::TimeWithZone then value.iso8601
      else value
      end
    end
  end
end

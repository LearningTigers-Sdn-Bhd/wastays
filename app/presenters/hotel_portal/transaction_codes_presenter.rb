# frozen_string_literal: true

module HotelPortal
  class TransactionCodesPresenter
    TABS = [
      { name: "default_codes", label: "Default Codes", icon: "badge-percent" },
      { name: "additional_service_codes", label: "Additional Service Codes", icon: "plus" },
      { name: "configuration", label: "Configuration", icon: "settings-2" }
    ].freeze

    DEFAULT_CODE_SECTIONS = [
      {
        title: "Hotel Operations",
        description: "Core hotel revenue codes used for room, food and beverage, parking, and miscellaneous postings.",
        system_keys: %w[room_revenue fnb_revenue parking_revenue damage_revenue cleaning_revenue misc_revenue],
        test_id: "transaction-codes-hotel-operations-list",
        empty_message: "No hotel operations transaction codes found."
      },
      {
        title: "Booking Operations",
        description: "Booking lifecycle codes used for no-shows, cancellations, deposits, late checkouts, and early departures.",
        system_keys: %w[no_show_revenue cancel_revenue late_checkout_revenue early_departure_revenue security_deposit],
        test_id: "transaction-codes-booking-operations-list",
        empty_message: "No booking operations transaction codes found."
      },
      {
        title: "Utility Operations",
        description: "Payment, refund, adjustment, and rebate codes used to balance guest folios.",
        system_keys: %w[cash_payment card_payment bank_payment gateway_manual_recovery_payment ota_collected_payment refund adjustment rebate],
        test_id: "transaction-codes-utility-operations-list",
        empty_message: "No utility operations transaction codes found."
      },
      {
        title: "Taxes and Fees Operations",
        description: "Transaction codes generated from primary taxes and configured taxes and fees.",
        system_keys: %w[sst_tax tourism_tax],
        kind: "tax",
        test_id: "transaction-codes-tax-operations-list",
        empty_message: "No tax operations transaction codes found.",
        action: :taxes_fees
      }
    ].freeze

    attr_reader :hotel, :active_tab, :current_user

    def initialize(hotel:, active_tab:, current_user:)
      @hotel = hotel
      @active_tab = active_tab
      @current_user = current_user
    end

    def tabs
      TABS
    end

    def default_codes
      @default_codes ||= hotel.transaction_codes.where(system_required: true)
        .or(hotel.transaction_codes.where(kind: "tax"))
        .or(hotel.transaction_codes.where(id: hotel_tax_transaction_code_ids))
        .order(:kind, :code)
    end

    def default_code_sections
      @default_code_sections ||= DEFAULT_CODE_SECTIONS.map do |section|
        section.merge(transaction_codes: transaction_codes_for_section(section))
      end
    end

    def additional_service_codes
      @additional_service_codes ||= hotel.transaction_codes.where(system_required: false).where.not(kind: "tax")
        .where.not(id: hotel_tax_transaction_code_ids)
        .where.not(id: extra_charge_transaction_code_ids)
        .order(:kind, :code)
    end

    def transaction_configuration
      @transaction_configuration ||= hotel.transaction_configuration
    end

    private

    def transaction_codes_for_section(section)
      relation = hotel.transaction_codes.where(system_key: section[:system_keys])
      relation = relation.or(hotel.transaction_codes.where(kind: section[:kind])) if section[:kind]
      relation = relation.or(hotel.transaction_codes.where(id: hotel_tax_transaction_code_ids)) if section[:action] == :taxes_fees
      relation = relation.where.not(id: extra_charge_transaction_code_ids)

      order_by_system_keys(relation, section[:system_keys])
    end

    def hotel_tax_transaction_code_ids
      @hotel_tax_transaction_code_ids ||= hotel.hotel_taxes.where.not(transaction_code_id: nil).select(:transaction_code_id)
    end

    def extra_charge_transaction_code_ids
      @extra_charge_transaction_code_ids ||= hotel.hotel_extra_charges.select(:transaction_code_id)
    end

    def order_by_system_keys(relation, system_keys)
      relation.to_a.sort_by do |transaction_code|
        [ system_keys.index(transaction_code.system_key) || system_keys.length, transaction_code.code ]
      end
    end
  end
end

# frozen_string_literal: true

module HotelPortal
  # Room Revenue is one revenue concept billed through five paths — the nightly
  # charge plus the four stay events. The page therefore has exactly two things to
  # say: how that revenue is taxed (ROOM's rules, which every path inherits), and
  # what the hotel charges when the stay does not run as booked.
  class RoomRevenuePresenter
    TABS = [
      { name: "tax_rules", label: "Tax rules", icon: "receipt" },
      { name: "reservation_policies", label: "Reservation policies", icon: "calendar-x" }
    ].freeze

    PREVIEW_AMOUNT = 50.to_d

    attr_reader :hotel, :active_tab

    def initialize(hotel:, active_tab: nil)
      @hotel = hotel
      @active_tab = TABS.map { |tab| tab[:name] }.include?(active_tab.to_s) ? active_tab.to_s : "tax_rules"
    end

    def tabs = TABS
    def preview_amount = PREVIEW_AMOUNT

    def room_revenue_code
      @room_revenue_code ||= ::TransactionCodes::Resolver.for(hotel).room_revenue
    end

    def transaction_configuration
      @transaction_configuration ||= hotel.transaction_configuration
    end

    def selected_tax_rule_keys
      @selected_tax_rule_keys ||= room_revenue_code&.tax_rule_keys.to_a
    end

    def tax_rules
      @tax_rules ||= primary_tax_rules + custom_tax_rules
    end

    def tax_rule_choices
      tax_rules.map do |rule|
        { label: "#{rule[:name]} · #{rate_label(rule)}#{rule[:enabled] ? '' : ' (inactive)'}", value: rule[:key] }
      end
    end

    def selected_tax_rules
      tax_rules.select { |rule| selected_tax_rule_keys.include?(rule[:key]) }
    end

    def rate_label(rule)
      if rule[:rate_type] == "percentage"
        "#{ActiveSupport::NumberHelper.number_to_rounded(rule[:amount], precision: 2, strip_insignificant_zeros: true)}%"
      else
        "#{currency} #{ActiveSupport::NumberHelper.number_to_rounded(rule[:amount], precision: 2)}"
      end
    end

    # What a MYR 50 room charge would post as, given the rules currently saved.
    # Inactive rules are stored but skipped at posting time, so they are left out.
    def preview_lines
      selected_tax_rules.select { |rule| rule[:enabled] }.map do |rule|
        amount = rule[:rate_type] == "percentage" ? (PREVIEW_AMOUNT * rule[:amount] / 100).round(2) : rule[:amount].round(2)
        { name: rule[:name], detail: rate_label(rule), amount: amount }
      end
    end

    def preview_total
      PREVIEW_AMOUNT + preview_lines.sum { |line| line[:amount] }
    end

    def reservation_policies
      @reservation_policies ||= hotel.hotel_reservation_policies
        .includes(:transaction_code, :cancellation_tiers).ordered
    end

    def currency = hotel.default_currency.presence || "MYR"

    private

    def primary_tax_rules
      [
        { key: "primary:sst_tax", name: "SST 8%", rate_type: "percentage", amount: 8.to_d,
          enabled: hotel.sst_enabled?, group: "Primary Taxes" },
        { key: "primary:tourism_tax", name: "Tourism Tax", rate_type: "flat", amount: hotel.tourism_tax_amount.to_d,
          enabled: hotel.tourism_tax_enabled?, group: "Primary Taxes" }
      ]
    end

    def custom_tax_rules
      hotel.hotel_taxes.order(:enabled, :name).map do |tax|
        { key: "hotel_tax:#{tax.id}", name: tax.name, rate_type: tax.rate_type,
          amount: tax.amount.to_d, enabled: tax.enabled?, group: "Additional Taxes & Fees" }
      end
    end
  end
end

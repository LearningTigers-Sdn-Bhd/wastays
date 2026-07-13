# frozen_string_literal: true

module FolioRouting
  class RoutingMatrix
    Row = Data.define(:code, :rule, :target_folio, :children) do
      def included_children = children.select(&:included)
    end
    Child = Data.define(:key, :code, :label, :included, :rule, :target_folio)

    attr_reader :booking, :hotel

    def initialize(booking:)
      @booking = booking
      @hotel = booking.hotel
    end

    def rows
      @rows ||= routable_codes.map do |code|
        rule = rules_by_code[code.id]
        Row.new(
          code: code,
          rule: rule,
          target_folio: rule&.target_folio || primary_folio,
          children: tax_candidates.map { |candidate| child_for(code, candidate) }
        )
      end
    end

    def parties
      @parties ||= booking.booking_billing_parties.active
        .includes(:booking_folios, :booking_guest, hotel_corporate_account: :corporate_account)
        .order(:party_kind, :id).to_a
    end

    def folios
      @folios ||= booking.booking_folios.includes(:booking_billing_party).order(:folio_sequence, :id).to_a
    end

    private

    def primary_folio
      @primary_folio ||= booking.booking_folio || folios.first
    end

    def rules_by_code
      @rules_by_code ||= booking.folio_routing_rules.active.includes(:target_folio).index_by(&:transaction_code_id)
    end

    def routable_codes
      FolioRouting::RoutabilityPolicy.parent_codes(hotel: hotel).to_a
    end

    def tax_candidates
      @tax_candidates ||= begin
        primary = TransactionCodeTax::PRIMARY_TAX_KEYS.map do |key|
          { key: "primary:#{key}", primary_tax_key: key, code: hotel.transaction_codes.find { |code| code.system_key == key }, label: key == "sst_tax" ? "SST 8%" : "Tourism Tax" }
        end
        custom = hotel.hotel_taxes.enabled.includes(:transaction_code).map do |tax|
          { key: "hotel_tax:#{tax.id}", hotel_tax: tax, code: tax.transaction_code, label: tax.name }
        end
        (primary + custom).select { |candidate| candidate[:code] }
      end
    end

    def child_for(code, candidate)
      default = code.transaction_code_taxes.any? { |link| link.tax_rule_key == candidate[:key] }
      override = overrides_by_code.fetch(code.id, {})[candidate[:key]]
      included = override ? override.action == "include" : default
      rule = rules_by_code[candidate[:code].id]
      Child.new(key: candidate[:key], code: candidate[:code], label: candidate[:label], included: included,
        rule: rule, target_folio: rule&.target_folio)
    end

    def overrides_by_code
      @overrides_by_code ||= booking.booking_tax_inclusion_overrides.includes(:hotel_tax).group_by(&:transaction_code_id)
        .transform_values { |items| items.index_by(&:tax_key) }
    end
  end
end

# frozen_string_literal: true

# The taxes a charge can be assigned, expressed as the opaque rule keys
# ExtraCharges::Save understands: the two statutory taxes the hotel carries as
# columns, plus the property's own taxes and fees.
#
# Settings and onboarding both offer this list, so it lives here rather than in
# either controller. HotelPortal::RoomRevenuePresenter builds a similar list with
# its own labels and grouping for the room-revenue page; that page shows rates
# alongside each name, which this one deliberately does not.
class TaxRuleOptionsQuery
  def initialize(hotel)
    @hotel = hotel
  end

  def call
    primary_rules + hotel_tax_rules
  end

  # Label/value pairs for a select or multi-select. An inactive tax is still
  # assignable — it is stored and simply skipped at posting time — so it stays in
  # the list and says so rather than disappearing.
  def choices
    call.map do |rule|
      { label: "#{rule[:name]}#{" · Inactive" unless rule[:enabled]}", value: rule[:key] }
    end
  end

  private

  attr_reader :hotel

  def primary_rules
    [
      {
        key: "primary:sst_tax",
        name: "Service Tax (SST)",
        rate_type: "percentage",
        amount: 8.to_d,
        enabled: hotel.sst_enabled?
      },
      {
        key: "primary:tourism_tax",
        name: "Tourism Tax",
        rate_type: "flat",
        amount: hotel.tourism_tax_amount.to_d,
        enabled: hotel.tourism_tax_enabled?
      }
    ]
  end

  def hotel_tax_rules
    hotel.hotel_taxes.order(:name).map do |tax|
      {
        key: "hotel_tax:#{tax.id}",
        name: tax.name,
        rate_type: tax.rate_type,
        amount: tax.amount.to_d,
        enabled: tax.enabled?
      }
    end
  end
end

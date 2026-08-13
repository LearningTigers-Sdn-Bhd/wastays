# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Effective nightly price consistency" do
  let(:hotel) { create(:hotel, default_currency: "MYR") }
  let(:room_type) { create(:room_type, hotel: hotel, base_price: 100, max_adults: 2) }
  let(:standard_plan) { room_type.standard_rate_plan }
  let(:rate_plan) { create(:rate_plan, :custom, hotel: hotel, currency: "MYR") }
  let(:date) { Date.current }

  before do
    create(:room_inventory, room_type: room_type, date: date, quantity: 2, status: "open")
    create(:room_rate, room_type: room_type, rate_plan: standard_plan, date: date, price: 200, currency: "MYR")
  end

  {
    "fixed starting price" => [ "fixed", 175, 175 ],
    "percentage adjustment" => [ "multiplier", -10, 180 ],
    "amount adjustment" => [ "offset", 25, 225 ]
  }.each do |label, (mode, value, expected)|
    it "keeps the resolver, calendar, availability, stay total, and booking snapshot equal for #{label}" do
      assignment = create(
        :room_type_rate_plan,
        room_type: room_type,
        rate_plan: rate_plan,
        pricing_mode: mode,
        pricing_value: value
      )

      resolved = Rates::ResolveEffectiveNightlyPrice.call(
        room_type: room_type,
        rate_plan: rate_plan,
        date: date,
        room_type_rate_plan: assignment
      )

      stay_total = Bookings::CalculateStayPrice.new(
        room_type: room_type,
        rate_plan: rate_plan,
        check_in: date,
        check_out: date + 1.day,
        adults: 2
      ).call

      availability = BookingEngine::AvailabilityService.new(
        check_in: date,
        check_out: date + 1.day,
        adults: 2,
        children: 0,
        room_count: 1
      )
      availability.available_rooms_for_hotel(hotel)
      availability_total = availability.calculate_total_price(room_type, rate_plan: rate_plan, adults: 2, children: 0)

      calendar = HotelPortal::InventoryCalendarPresenter.new(
        hotel: hotel,
        start_date: date,
        end_date: date,
        display_currency: "MYR"
      )
      row = calendar.rows.find { |item| item.rate_row? && item.rate_plan_id == rate_plan.id }
      calendar_amount = calendar.cell_for(row, date)[:price]

      snapshot = Bookings::BuildFinancialSnapshot.new(
        hotel: hotel,
        room_type: room_type,
        rate_plan: rate_plan,
        check_in: date,
        check_out: date + 1.day,
        guest_country: "Malaysia",
        adults: 2
      ).call

      expect([ resolved.amount, stay_total, availability_total, calendar_amount, snapshot.room_total ])
        .to all(eq(expected.to_d))
    end
  end
end

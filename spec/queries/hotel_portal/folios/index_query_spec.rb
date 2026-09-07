# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Folios::IndexQuery, frozen_time: Time.zone.local(2026, 6, 18, 10) do
  let(:hotel) { create(:hotel, status: "live") }

  it "calculates financial signals and summary counts in the database" do
    balance = create_folio(name: "Balance Guest", charges: 120, payments: 20)
    refund = create_folio(name: "Refund Guest", payments: 80)
    adjusted = create_folio(name: "Adjusted Guest", adjustments: 15)
    closed = create_folio(name: "Closed Guest", status: "closed", updated_at: business_window.begin + 1.hour)

    query = described_class.new(hotel:, query: "", filter: "all")
    rows = query.page(offset: 0, limit: 25).index_by(&:id)

    expect(rows.fetch(balance.id).calculated_balance).to eq(100.to_d)
    expect(rows.fetch(refund.id).calculated_balance).to eq(-80.to_d)
    expect(rows.fetch(adjusted.id).calculated_adjusted).to be(true)
    expect(rows.fetch(closed.id).calculated_closed_today).to be(true)
    expect(query.summary_counts).to eq(
      "open" => 3,
      "balance_due" => 2,
      "refund_due" => 1,
      "closed_today" => 1
    )
  end

  it "searches every supported folio identity and keeps filter counts independent" do
    folio = create_folio(name: "Nur Aina", confirmation: "BK-SEARCH", room: "A-204", charges: 100)
    folio.booking.update!(guest_email: "aina@example.com", guest_phone: "60123456789", folio_account_reference: "FA-902")
    other = create_folio(name: "Other Guest", charges: 50)
    other.booking.update!(guest_email: "other@example.com", guest_phone: "60000000000")

    [ "Nur", "BK-SEARCH", "aina@example", "601234", folio.folio_number.to_s, "FA-902", "A-204" ].each do |term|
      query = described_class.new(hotel:, query: term, filter: "all")
      expect(query.page(offset: 0, limit: 25).map(&:id)).to include(folio.id)
      expect(query.filter_counts(HotelPortal::Folios::IndexPresenter::FILTERS).fetch("all")).to eq(2)
    end
  end

  it "preserves per-folio refund synchronization and hotel isolation" do
    booking = create(:booking, hotel: hotel)
    first = create(:booking_folio, booking:, hotel:)
    second = create(:booking_folio, :secondary, booking:, hotel:)
    refund = create(:refund_request, booking:, status: "completed", refund_amount: 40)
    create(
      :folio_transaction,
      booking_folio: first,
      transaction_type: "payment",
      category: "refund",
      amount: -40,
      metadata: { "refund_request_id" => refund.id }
    )
    other_hotel = create(:hotel, status: "live")
    create_folio(name: "Hidden Guest", hotel: other_hotel, charges: 30)

    query = described_class.new(hotel:, query: "", filter: "review", attention_only: true)

    expect(query.page(offset: 0, limit: 25).map(&:id)).to eq([ second.id ])
    expect(query.needs_attention_count).to eq(2)
  end

  it "uses stable page ordering without loading records outside the page" do
    folios = Array.new(26) do |index|
      create_folio(name: "Page #{index}", updated_at: Time.current - index.minutes)
    end
    query = described_class.new(hotel:, query: "", filter: "all")

    expect(query.collection.count).to eq(26)
    expect(query.page(offset: 25, limit: 25).map(&:id)).to eq([ folios.last.id ])
  end

  it "keeps query count constant as the folio dataset grows" do
    create_folio(name: "Baseline", charges: 100)
    baseline = count_queries { exercise_query }
    10.times { |index| create_folio(name: "Scaled #{index}", charges: 100) }

    expect(count_queries { exercise_query }).to eq(baseline)
  end

  private

  def create_folio(name:, hotel: self.hotel, confirmation: nil, room: nil, charges: 0, payments: 0, adjustments: 0, status: "open", updated_at: Time.current)
    booking = create(:booking, hotel:, guest_name: name, confirmation_token: confirmation || "BK-#{SecureRandom.hex(5)}")
    create(:booking_room, booking:, room_type: create(:room_type, hotel:), room_number: room) if room.present?
    folio = create(:booking_folio, booking:, hotel:, status:)
    create(:folio_transaction, booking_folio: folio, transaction_type: "charge", category: "accommodation", amount: charges) if charges.positive?
    create(:folio_transaction, booking_folio: folio, transaction_type: "payment", category: "cash", amount: payments) if payments.positive?
    create(:folio_transaction, booking_folio: folio, transaction_type: "adjustment", category: "adjustment", amount: adjustments) if adjustments.positive?
    folio.update_column(:updated_at, updated_at)
    folio
  end

  def business_window
    hotel.business_day_window_for(hotel.current_business_date)
  end

  def exercise_query
    query = described_class.new(hotel:, query: "", filter: "all")
    query.summary_counts
    query.filter_counts(HotelPortal::Folios::IndexPresenter::FILTERS)
    query.collection.count
    query.page(offset: 0, limit: 25).each { |folio| folio.booking.booking_rooms.to_a }
  end

  def count_queries(&block)
    count = 0
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      count += 1 unless payload[:name].in?([ "SCHEMA", "TRANSACTION" ])
    end
    block.call
    count
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end
end

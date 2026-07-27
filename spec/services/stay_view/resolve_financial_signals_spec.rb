# frozen_string_literal: true

require "rails_helper"

RSpec.describe StayView::ResolveFinancialSignals do
  let(:hotel) { create(:hotel) }

  def booking_record(booking)
    StayView::BookingRecord.new(
      booking_room_id: booking.id,
      booking_id: booking.id,
      room_type_id: 1,
      room_number: booking.id.to_s,
      status: booking.status,
      guest_name: booking.guest_name,
      check_in: booking.check_in.to_date,
      check_out: booking.check_out.to_date
    )
  end

  def signals_for(*bookings, scoped_hotel: hotel)
    described_class.call(hotel: scoped_hotel, bookings: bookings.map { |booking| booking_record(booking) })
  end

  def guest_folio(booking, name:, **folio_attributes)
    folio = create(:booking_folio, booking:, hotel: booking.hotel, **folio_attributes)
    booking_guest = create(:booking_guest, booking:, guest: create(:guest, name:), is_primary: true)
    folio.reload
    expect(folio.booking_billing_party).to eq(booking_guest.booking_billing_party)
    folio
  end

  def company_folio(
    booking, name:, account_type: "company", settlement_type: "cash_bank", direct_bill_enabled: false,
    account_status: "active", **folio_attributes
  )
    relationship = create(
      :hotel_corporate_account,
      hotel: booking.hotel,
      corporate_account: create(:account, :corporate, name:),
      account_type:,
      relationship_type: (direct_bill_enabled ? "direct_bill" : "standard"),
      status: "active"
    )
    party = create(
      :booking_billing_party,
      booking:,
      hotel: booking.hotel,
      hotel_corporate_account: relationship,
      account_type:
    )
    persisted_settlement_type = if settlement_type == "city_ledger" && (account_status != "active" || !direct_bill_enabled)
      "cash_bank"
    else
      settlement_type
    end
    terms = create(
      :booking_billing_terms,
      booking_billing_party: party,
      settlement_type: persisted_settlement_type,
      purchase_order_reference: ("PO-42" if persisted_settlement_type == "city_ledger")
    )
    terms.update_column(:settlement_type, settlement_type) if persisted_settlement_type != settlement_type
    folio = create(
      :booking_folio,
      booking:,
      hotel: booking.hotel,
      label: "#{name} Folio",
      folio_type: "external",
      payer_type: "company",
      is_primary: false,
      booking_billing_party: party,
      hotel_corporate_account: relationship,
      **folio_attributes
    )
    if account_status != "active"
      relationship.update_columns(status: account_status, suspended_at: Time.current, updated_at: Time.current)
    end
    [ folio, party, relationship ]
  end

  it "projects guest balances, credits, forecasts, and one overall settled state" do
    due_booking = create(:booking, hotel:, check_out: 3.days.from_now)
    due_folio = guest_folio(due_booking, name: "Ada Lovelace")
    create(:folio_transaction, booking_folio: due_folio, amount: 100)
    create(:folio_transaction, booking_folio: due_folio, transaction_type: :payment, category: "cash", amount: 40)
    create(:folio_transaction, booking_folio: due_folio, transaction_type: :adjustment, category: "adjustment", amount: 10)
    create(:folio_forecasted_charge, booking_folio: due_folio, stay_date: Date.current + 1.day, amount: 30)
    create(:folio_forecasted_charge, booking_folio: due_folio, stay_date: due_booking.check_out.to_date, amount: 999)
    secondary_due_folio = create(
      :booking_folio,
      booking: due_booking,
      hotel:,
      label: "Secondary Guest Folio",
      is_primary: false,
      booking_billing_party: due_folio.booking_billing_party
    )
    create(:folio_transaction, booking_folio: secondary_due_folio, amount: 15)

    credit_booking = create(:booking, hotel:)
    credit_folio = guest_folio(credit_booking, name: "Grace Hopper")
    create(:folio_transaction, booking_folio: credit_folio, transaction_type: :payment, category: "cash", amount: 25)

    settled_booking = create(:booking, hotel:)
    settled_folio = guest_folio(settled_booking, name: "Katherine Johnson")
    create(:folio_transaction, booking_folio: settled_folio, amount: 80)
    create(:folio_transaction, booking_folio: settled_folio, transaction_type: :payment, category: "cash", amount: 80)

    signals = signals_for(due_booking, credit_booking, settled_booking)

    expect(signals.fetch(due_booking.id).sole).to have_attributes(
      state: :balance_due,
      label: "Guest: Ada Lovelace · Balance due · MYR 115.00"
    )
    expect(signals.fetch(credit_booking.id).sole).to have_attributes(
      state: :credit,
      label: "Guest: Grace Hopper · Credit · MYR 25.00"
    )
    expect(signals.fetch(settled_booking.id).sole).to have_attributes(state: :settled, label: "Projected settled")
    expect(signals.values).to all(be_frozen)
  end

  it "keeps guest, company, and government responsibility separate" do
    booking = create(:booking, hotel:)
    guest = guest_folio(booking, name: "Ada Lovelace")
    additional_booking_guest = create(
      :booking_guest,
      booking:,
      guest: create(:guest, name: "Additional Guest"),
      is_primary: false
    )
    additional_guest = create(
      :booking_folio,
      booking:,
      hotel:,
      label: "Additional Guest Folio",
      is_primary: false,
      booking_billing_party: additional_booking_guest.booking_billing_party
    )
    company, = company_folio(booking, name: "Acme Sdn Bhd")
    government, = company_folio(booking, name: "Ministry of Tourism", account_type: "government")
    create(:folio_transaction, booking_folio: guest, amount: 100)
    create(:folio_transaction, booking_folio: additional_guest, amount: 50)
    create(:folio_transaction, booking_folio: company, amount: 200)
    create(:folio_transaction, booking_folio: government, amount: 300)

    labels = signals_for(booking).fetch(booking.id).map(&:label)

    expect(labels).to eq([
      "Guest: Ada Lovelace · Balance due · MYR 100.00",
      "Guest: Additional Guest · Balance due · MYR 50.00",
      "Company: Acme Sdn Bhd · Payment due · MYR 200.00",
      "Government: Ministry of Tourism · Payment due · MYR 300.00"
    ])
  end

  it "shows valid City Ledger as informational before and after AR transfer" do
    planned_booking = create(:booking, hotel:)
    planned, = company_folio(
      planned_booking,
      name: "Planned Corp",
      settlement_type: "city_ledger",
      direct_bill_enabled: true
    )
    create(:folio_transaction, booking_folio: planned, amount: 240)

    billed_booking = create(:booking, hotel:)
    billed, _party, relationship = company_folio(
      billed_booking,
      name: "Billed Corp",
      settlement_type: "city_ledger",
      direct_bill_enabled: true,
      status: "closed",
      closed_at: Time.current
    )
    create(:folio_transaction, booking_folio: billed, amount: 300)
    invoice = create(:ar_invoice, booking_folio: billed, hotel:, hotel_corporate_account: relationship, amount: 300)
    planned_sibling = create(
      :booking_folio,
      booking: billed_booking,
      hotel:,
      label: "Billed Corp Current Folio",
      folio_type: "external",
      payer_type: "company",
      is_primary: false,
      booking_billing_party: billed.booking_billing_party,
      hotel_corporate_account: relationship
    )
    create(:folio_transaction, booking_folio: planned_sibling, amount: 50)

    signals = signals_for(planned_booking, billed_booking)

    expect(signals.fetch(planned_booking.id).sole).to have_attributes(
      state: :direct_bill_planned,
      label: "Direct bill planned: Planned Corp · MYR 240.00",
      attention?: false
    )
    expect(signals.fetch(billed_booking.id)).to contain_exactly(
      have_attributes(state: :direct_billed, label: "Direct billed: Billed Corp · MYR 300.00", attention?: false),
      have_attributes(state: :direct_bill_planned, label: "Direct bill planned: Billed Corp · MYR 50.00", attention?: false)
    )

    %w[partially_paid paid overdue].each do |status|
      invoice.update!(status:, paid_amount: (status == "paid" ? 300 : 100), outstanding_amount: (status == "paid" ? 0 : 200))
      expect(signals_for(billed_booking).fetch(billed_booking.id).map(&:state)).to contain_exactly(
        :direct_billed, :direct_bill_planned
      )
    end
  end

  it "flags invalid and inconsistent Direct Bill states without exposing amounts" do
    suspended_booking = create(:booking, hotel:)
    suspended, = company_folio(
      suspended_booking,
      name: "Suspended Corp",
      settlement_type: "city_ledger",
      direct_bill_enabled: true,
      account_status: "suspended"
    )
    create(:folio_transaction, booking_folio: suspended, amount: 100)

    disabled_booking = create(:booking, hotel:)
    disabled, = company_folio(disabled_booking, name: "Disabled Corp", settlement_type: "cash_bank")
    disabled.booking_billing_party.billing_terms.update_column(:settlement_type, "city_ledger")
    create(:folio_transaction, booking_folio: disabled, amount: 100)

    missing_invoice_booking = create(:booking, hotel:)
    missing_invoice, = company_folio(
      missing_invoice_booking,
      name: "Missing Invoice Corp",
      settlement_type: "city_ledger",
      direct_bill_enabled: true,
      status: "closed",
      closed_at: Time.current
    )
    create(:folio_transaction, booking_folio: missing_invoice, amount: 100)

    open_invoice_booking = create(:booking, hotel:)
    open_invoice, _party, open_relationship = company_folio(
      open_invoice_booking,
      name: "Open Invoice Corp",
      settlement_type: "city_ledger",
      direct_bill_enabled: true
    )
    create(:ar_invoice, booking_folio: open_invoice, hotel:, hotel_corporate_account: open_relationship)

    void_invoice_booking = create(:booking, hotel:)
    void_invoice, _party, void_relationship = company_folio(
      void_invoice_booking,
      name: "Void Invoice Corp",
      settlement_type: "city_ledger",
      direct_bill_enabled: true,
      status: "closed",
      closed_at: Time.current
    )
    create(:ar_invoice, booking_folio: void_invoice, hotel:, hotel_corporate_account: void_relationship, status: "void")

    signals = signals_for(
      suspended_booking, disabled_booking, missing_invoice_booking, open_invoice_booking, void_invoice_booking
    )

    expect(signals.fetch(suspended_booking.id).sole.label).to eq("Direct bill review: Suspended Corp")
    expect(signals.fetch(disabled_booking.id).sole.label).to eq("Direct bill review: Disabled Corp")
    expect(signals.fetch(missing_invoice_booking.id).sole.label).to eq("Direct bill review: Missing Invoice Corp")
    expect(signals.fetch(open_invoice_booking.id).sole.label).to eq("Direct bill review: Open Invoice Corp")
    expect(signals.fetch(void_invoice_booking.id).sole.label).to eq("Direct bill review: Void Invoice Corp")
    expect(signals.values.flatten.map(&:label).join).not_to include("MYR")
  end

  it "uses review-only fallbacks for missing, unlinked, unsupported, and cross-hotel records without mutating parties" do
    missing = create(:booking, hotel:)

    unlinked = create(:booking, hotel:)
    unlinked_folio = create(:booking_folio, booking: unlinked, hotel:)
    create(:folio_transaction, booking_folio: unlinked_folio, amount: 987.65)

    house = create(:booking, hotel:)
    house_folio = create(
      :booking_folio,
      booking: house,
      hotel:,
      folio_type: "house",
      payer_type: "hotel",
      label: "House Folio"
    )
    create(:folio_transaction, booking_folio: house_folio, amount: 50)

    other_booking = create(:booking, hotel: create(:hotel))
    other_folio = create(:booking_folio, booking: other_booking, hotel: other_booking.hotel)
    create(:folio_transaction, booking_folio: other_folio, amount: 75)

    expect do
      @signals = signals_for(missing, unlinked, house, other_booking)
    end.not_to change(BookingBillingParty, :count)

    expect(@signals.values.flatten).to all(have_attributes(state: :review, label: "Financial review required"))
    expect(@signals.values.flatten.map(&:label).join).not_to include("987.65", "50.00", "75.00")
  end

  it "reviews mixed currencies for one party but permits different parties to use different currencies" do
    mixed_booking = create(:booking, hotel:)
    myr = guest_folio(mixed_booking, name: "Mixed Guest")
    usd = create(
      :booking_folio,
      booking: mixed_booking,
      hotel:,
      currency: "USD",
      label: "USD Guest Folio",
      is_primary: false,
      booking_billing_party: myr.booking_billing_party
    )
    create(:folio_transaction, booking_folio: myr, amount: 10)
    create(:folio_transaction, booking_folio: usd, amount: 5, currency: "USD")

    separate_booking = create(:booking, hotel:)
    guest = guest_folio(separate_booking, name: "MYR Guest")
    company, = company_folio(separate_booking, name: "USD Company", currency: "USD")
    create(:folio_transaction, booking_folio: guest, amount: 10)
    create(:folio_transaction, booking_folio: company, amount: 5, currency: "USD")

    signals = signals_for(mixed_booking, separate_booking)

    expect(signals.fetch(mixed_booking.id).sole.label).to eq("Financial review required: Mixed Guest")
    expect(signals.fetch(separate_booking.id).map(&:label)).to contain_exactly(
      "Guest: MYR Guest · Balance due · MYR 10.00",
      "Company: USD Company · Payment due · USD 5.00"
    )
  end

  it "excludes forecasts for closed folios and terminal bookings" do
    closed_booking = create(:booking, hotel:, check_out: 3.days.from_now)
    closed_folio = guest_folio(closed_booking, name: "Closed Guest")
    closed_folio.update_columns(status: "closed", closed_at: Time.current, updated_at: Time.current)
    create(:folio_forecasted_charge, booking_folio: closed_folio, stay_date: Date.current + 1.day, amount: 100)

    completed_booking = create(:booking, hotel:, status: "completed", check_out: 3.days.from_now)
    completed_folio = guest_folio(completed_booking, name: "Completed Guest")
    create(:folio_forecasted_charge, booking_folio: completed_folio, stay_date: Date.current + 1.day, amount: 100)

    signals = signals_for(closed_booking, completed_booking)
    expect(signals.fetch(closed_booking.id).sole.state).to eq(:settled)
    expect(signals.fetch(completed_booking.id).sole.state).to eq(:settled)
  end

  it "keeps grouped child bookings financially independent" do
    group = create(:group_booking, hotel:)
    first = create(:booking, hotel:, group_booking: group, group_position: 1)
    second = create(:booking, hotel:, group_booking: group, group_position: 2)
    first_folio = guest_folio(first, name: "First Child")
    second_folio = guest_folio(second, name: "Second Child")
    create(:folio_transaction, booking_folio: first_folio, amount: 120)
    create(:folio_transaction, booking_folio: second_folio, transaction_type: :payment, category: "cash", amount: 20)

    signals = signals_for(first, second)

    expect(signals.fetch(first.id).sole.label).to start_with("Guest: First Child · Balance due")
    expect(signals.fetch(second.id).sole.label).to start_with("Guest: Second Child · Credit")
  end

  it "uses a fixed query count as bookings, parties, and folios grow" do
    bookings = create_list(:booking, 4, hotel:)
    bookings.each_with_index do |booking, index|
      folio = guest_folio(booking, name: "Guest #{index}")
      create(:folio_transaction, booking_folio: folio, amount: 10)
      create(:folio_forecasted_charge, booking_folio: folio, stay_date: Date.current, amount: 5)
      company, = company_folio(booking, name: "Company #{index}")
      create(:folio_transaction, booking_folio: company, amount: 20)
    end

    queries = []
    callback = lambda do |_name, _start, _finish, _id, payload|
      next if payload[:cached] || %w[SCHEMA TRANSACTION].include?(payload[:name])

      queries << payload[:sql]
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      signals_for(*bookings)
    end

    financial_queries = queries.grep(
      /booking_folios|booking_billing_parties|booking_billing_terms|booking_guests|hotel_corporate_accounts|folio_transactions|folio_forecasted_charges|ar_invoices/
    )
    expect(financial_queries.size).to eq(8)
  end
end

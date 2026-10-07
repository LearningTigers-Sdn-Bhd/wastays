# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::UpdateStayService, "closed stay dates" do
  let(:closed_date) { Date.new(2026, 10, 6) }
  let(:open_date) { closed_date + 1.day }
  let(:hotel) { create(:hotel, time_zone: "Kuala Lumpur", accounting_business_date: open_date, sst_enabled: true) }
  let(:room_type) { create(:room_type, hotel: hotel, base_price: 108, quantity: 10) }
  let(:actor) { create(:user, account: hotel.account) }
  let(:booking) do
    create(:booking, hotel: hotel, status: "checked_in", guest_country: "Malaysia",
      check_in: hotel.hotel_time_zone.local(2026, 10, 7, 14),
      check_out: hotel.hotel_time_zone.local(2026, 10, 8, 12),
      checked_in_at: hotel.hotel_time_zone.local(2026, 10, 7, 14))
  end
  let!(:room) { create(:booking_room, booking: booking, room_type: room_type, rate_plan: room_type.standard_rate_plan, subtotal: 108) }
  let!(:folio) { create(:booking_folio, hotel: hotel, booking: booking) }
  let!(:audit) { create(:night_audit, hotel: hotel, business_date: closed_date, status: "completed") }

  before do
    create(:hotel_business_date, hotel: hotel, business_date: closed_date, status: "closed")
    create(:night_audit_financial_summary, night_audit: audit, room_revenue: 0)
    room_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
    room_code.update!(is_taxable: true)
    room_code.transaction_code_taxes.find_or_create_by!(primary_tax_key: "sst_tax")
    allow(actor).to receive(:has_permission?).with("manage_bookings", hotel: hotel).and_return(true)
    Bookings::InventoryManager.new(booking).deduct
    Folios::Forecasts::SyncForecastedCharges.call(booking_folio: folio)
    allow(Notifications::Dispatcher).to receive(:new).and_call_original
  end

  it "posts room and SST when a checked-in stay moves onto a completed audit date" do
    create(:folio_transaction, booking_folio: folio, transaction_type: "payment", category: "cash", amount: 116.64)

    result = update_dates(closed_date, open_date)

    expect(result).to be_success
    expect(folio.folio_transactions.charge.order(:category).pluck(:category, :amount)).to eq([
      [ "accommodation", 108.to_d ], [ "tax", "8.64".to_d ]
    ])
    expect(folio.folio_transactions.charge.pluck(:posting_date).uniq).to eq([ closed_date ])
    expect(folio.folio_transactions.charge.pluck(:user_id).uniq).to eq([ actor.id ])
    expect(folio.folio_forecasted_charges.forecast).not_to exist
    expect(Folios::Charges::NightlyChargeReconciliation.call(booking: booking.reload, business_date: closed_date)).to be_valid
    expect(audit.financial_summary.reload.room_revenue).to eq(108.to_d)
    expect(hotel.journal_batches.find_by!(business_date: closed_date).status).to eq("finalized")
    log = audit.night_audit_logs.find_by!(action_type: "completed_audit_repair")
    expect(log.metadata["reason"]).to include(booking.reservation_reference, closed_date.to_s, open_date.to_s)
    expect(folio.folio_transactions.charge.sum(:amount) - folio.folio_transactions.payment.sum(:amount)).to eq(0.to_d)
  end

  it "posts only closed nights and leaves open nights forecasted" do
    expect(update_dates(closed_date, open_date + 1.day)).to be_success

    expect(folio.folio_transactions.charge.pluck(:posting_date).uniq).to eq([ closed_date ])
    expect(folio.folio_forecasted_charges.forecast.pluck(:stay_date).uniq).to eq([ open_date ])
  end

  it "posts each completed night when a stay moves across multiple closed dates" do
    earlier = closed_date - 1.day
    create(:hotel_business_date, hotel: hotel, business_date: earlier, status: "closed")
    create(:night_audit, hotel: hotel, business_date: earlier, status: "completed")

    expect(update_dates(earlier, open_date)).to be_success
    expect(folio.folio_transactions.charge.group(:posting_date).sum(:amount)).to eq(
      earlier => "116.64".to_d, closed_date => "116.64".to_d
    )
    expect(folio.folio_forecasted_charges.forecast).not_to exist
    expect(hotel.journal_batches.pluck(:business_date)).to match_array([ earlier, closed_date ])
  end

  %w[due_out_detected checkout_required].each do |status|
    it "posts missing closed-night charges for #{status} stays" do
      booking.update_column(:status, status)

      expect(update_dates(closed_date, open_date)).to be_success
      expect(folio.folio_transactions.charge.sum(:amount)).to eq("116.64".to_d)
    end
  end

  it "leaves confirmed bookings forecasted on closed dates" do
    booking.update_column(:status, "confirmed")

    expect(update_dates(closed_date, open_date)).to be_success
    expect(folio.folio_transactions).not_to exist
    expect(folio.folio_forecasted_charges.forecast.pluck(:stay_date).uniq).to eq([ closed_date ])
  end

  it "rejects duplicate historical postings without reversing them automatically" do
    room_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
    key = Folios::Charges::ChargePostingKeys.nightly_charge_key(booking: booking, date: closed_date, charge_kind: "accommodation", identity: room.id)
    create(:folio_transaction, booking_folio: folio, posting_date: closed_date, amount: 108,
      transaction_code: room_code, metadata: { nightly_charge_key: key })
    create(:folio_transaction, booking_folio: folio, posting_date: closed_date, amount: 108,
      transaction_code: room_code, metadata: { reconciles_nightly_charge_key: key })

    result = update_dates(closed_date, open_date)

    expect(result).not_to be_success
    expect(result.errors.join).to include("accounting correction")
    expect(folio.folio_transactions.count).to eq(2)
    expect(folio.folio_transactions.where.not(voided_by_transaction_id: nil)).not_to exist
  end

  it "rolls back an unresolved route instead of leaving a historical forecast" do
    allow(Folios::Routing::ResolveTargetFolio).to receive(:call).and_return(
      Folios::Routing::RouteResult.failure("route unavailable", route_source: "primary_folio", route_metadata: {})
    )

    result = update_dates(closed_date, open_date)

    expect(result).not_to be_success
    expect(result.errors.join).to include("route unavailable")
    expect(booking.reload.check_in.in_time_zone(hotel.hotel_time_zone).to_date).to eq(open_date)
    expect(folio.folio_transactions).not_to exist
  end

  it "does not automatically post into a closed target folio" do
    folio.update!(status: "closed", closed_at: Time.current)

    result = update_dates(closed_date, open_date)

    expect(result).not_to be_success
    expect(folio.folio_transactions).not_to exist
  end

  it "rechecks the accounting guard after taking the locks" do
    allow(booking).to receive(:lock!).and_wrap_original do |original|
      original.call
      hotel.current_business_date_record.update!(status: "audit_running")
    end

    result = update_dates(closed_date, open_date)

    expect(result).not_to be_success
    expect(result.errors).to include(NightAudits::OperationalChangeGuard::ERROR_MESSAGE)
    expect(booking.reload.check_in.in_time_zone(hotel.hotel_time_zone).to_date).to eq(open_date)
    expect(folio.folio_transactions).not_to exist
  end

  it "does not duplicate charges when the same update is repeated" do
    expect(update_dates(closed_date, open_date)).to be_success

    expect { expect(update_dates(closed_date, open_date)).to be_success }.not_to change(FolioTransaction, :count)
  end

  it "keeps a valid catch-up posting and posts only the missing tax" do
    key = Folios::Charges::ChargePostingKeys.catch_up_charge_key(booking: booking, date: closed_date, charge_kind: "accommodation", identity: room.id)
    create(:folio_transaction, booking_folio: folio, posting_date: closed_date, amount: 108,
      transaction_code: hotel.transaction_codes.find_by!(system_key: "room_revenue"), catch_up_key: key)

    expect(update_dates(closed_date, open_date)).to be_success
    expect(folio.folio_transactions.charge.where(category: "accommodation").count).to eq(1)
    expect(folio.folio_transactions.charge.where(category: "tax").count).to eq(1)
  end

  it "rejects removing a closed night with posted charges" do
    expect(update_dates(closed_date, open_date)).to be_success
    count = folio.folio_transactions.count

    result = update_dates(open_date, open_date + 1.day)

    expect(result).not_to be_success
    expect(result.errors).to include(Bookings::PostClosedStayCharges::CORRECTION_REQUIRED)
    expect(booking.reload.check_in.in_time_zone(hotel.hotel_time_zone).to_date).to eq(closed_date)
    expect(folio.folio_transactions.count).to eq(count)
  end

  it "rejects repricing an existing posted closed night" do
    expect(update_dates(closed_date, open_date)).to be_success

    result = described_class.new(booking: booking, user: actor, params: { manual_rate_override: 200 }).call

    expect(result).not_to be_success
    expect(result.errors).to include(Bookings::PostClosedStayCharges::CORRECTION_REQUIRED)
    expect(booking.reload.total_amount).to eq("116.64".to_d)
    expect(folio.folio_transactions.charge.sum(:amount)).to eq("116.64".to_d)
  end

  it "requires booking permission for automatic historical posting" do
    allow(actor).to receive(:has_permission?).with("manage_bookings", hotel: hotel).and_return(false)

    result = update_dates(closed_date, open_date)

    expect(result).not_to be_success
    expect(result.errors).to include("You do not have permission to update this booking.")
    expect(folio.folio_transactions).not_to exist
    expect(booking.reload.check_in.in_time_zone(hotel.hotel_time_zone).to_date).to eq(open_date)
  end

  it "rejects a past night without an accounting record" do
    hotel.hotel_business_dates.find_by!(business_date: closed_date).destroy!

    result = update_dates(closed_date, open_date)

    expect(result).not_to be_success
    expect(result.errors.join).to include("Missing accounting record")
    expect(folio.folio_transactions).not_to exist
  end

  it "rejects a closed night without a completed audit" do
    audit.update!(status: "failed")

    result = update_dates(closed_date, open_date)

    expect(result).not_to be_success
    expect(result.errors.join).to include("Completed Night Audit is missing")
    expect(folio.folio_transactions).not_to exist
  end

  [ "posting", "summary", "journal" ].each do |step|
    it "rolls back the whole edit when #{step} fails" do
      case step
      when "posting"
        allow_any_instance_of(Folios::Transactions::InsertTransaction).to receive(:call).and_return(Folios::Transactions::TransactionResult.failure("posting failed"))
      when "summary"
        allow_any_instance_of(NightAudits::RecalculateFinancialSummary).to receive(:call).and_raise("summary failed")
      when "journal"
        allow(Financials::CreateJournalBatch).to receive(:call).and_raise("journal failed")
      end
      forecasts = folio.folio_forecasted_charges.pluck(:id, :status)
      inventory = room_type.room_inventories.order(:date).pluck(:date, :quantity)

      result = update_dates(closed_date, open_date)

      expect(result).not_to be_success
      expect(result.errors.join).to include("#{step} failed")
      expect(booking.reload.check_in.in_time_zone(hotel.hotel_time_zone).to_date).to eq(open_date)
      expect(folio.folio_transactions).not_to exist
      expect(folio.folio_forecasted_charges.pluck(:id, :status)).to eq(forecasts)
      expect(room_type.room_inventories.order(:date).pluck(:date, :quantity)).to eq(inventory)
      expect(audit.financial_summary.reload.room_revenue).to eq(0.to_d)
      expect(hotel.journal_batches).not_to exist
      expect(Notifications::Dispatcher).not_to have_received(:new)
    end
  end

  it "rolls back earlier group repairs when a later booking fails" do
    group = create(:group_booking, hotel: hotel)
    booking.update!(group_booking: group)
    second = create(:booking, hotel: hotel, group_booking: group, status: "checked_in", check_in: booking.check_in, check_out: booking.check_out)
    create(:booking_room, booking: second, room_type: room_type, rate_plan: room_type.standard_rate_plan, subtotal: 108)
    create(:booking_folio, hotel: hotel, booking: second)
    Bookings::InventoryManager.new(second).deduct
    allow(Financials::CreateJournalBatch).to receive(:call).and_call_original
    calls = 0
    allow(Financials::CreateJournalBatch).to receive(:call).and_wrap_original do |original, **args|
      calls += 1
      raise "second journal failed" if calls == 2
      original.call(**args)
    end

    result = Bookings::UpdateGroupStay.call(group_booking: group, booking_ids: [ booking.id, second.id ],
      params: { check_in: closed_date.to_s, check_out: open_date.to_s }, user: actor)

    expect(result).not_to be_success
    expect(result.error).to eq("second journal failed")
    expect(booking.reload.check_in.in_time_zone(hotel.hotel_time_zone).to_date).to eq(open_date)
    expect(second.reload.check_in.in_time_zone(hotel.hotel_time_zone).to_date).to eq(open_date)
    expect(FolioTransaction.where(booking_folio_id: group.bookings.joins(:booking_folios).select("booking_folios.id"))).not_to exist
    expect(hotel.journal_batches).not_to exist
    expect(Notifications::Dispatcher).not_to have_received(:new)
  end

  def update_dates(arrival, departure)
    described_class.new(booking: booking, user: actor, params: { check_in: arrival.to_s, check_out: departure.to_s }).call
  end
end

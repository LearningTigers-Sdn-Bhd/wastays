# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Group folio movements" do
  let(:hotel) { create(:hotel) }
  let(:group) { create(:group_booking, hotel:) }
  let(:booking) { create(:booking, hotel:, group_booking: group, status: "checked_in") }
  let(:sibling) { create(:booking, hotel:, group_booking: group, status: "checked_in") }
  let(:source) { create(:booking_folio, booking:, hotel:) }
  let(:target) { create(:booking_folio, booking: sibling, hotel:) }
  let(:actor) { create(:user, :superadmin) }
  let(:charge) { create(:folio_transaction, booking_folio: source, amount: 100) }

  def move(row = charge, **options)
    Folios::Transactions::MoveTransaction.call(transaction: row, target_folio: target, user: actor, reason: "Group consolidation", **options)
  end

  def transfer_attributes(rows = [ charge ], **options)
    { booking:, actor:, source_folio_ids: rows.map(&:booking_folio_id).uniq, transaction_ids: rows.map(&:id),
      target_folio_id: target.id, reason: "Group consolidation", idempotency_key: SecureRandom.uuid, **options }
  end

  def transfer(rows = [ charge ], **options)
    attributes = transfer_attributes(rows, **options)
    preview = Folios::TransferFolios.preview(**attributes)
    expect(preview).to be_success, preview.error
    [ Folios::TransferFolios.call(**attributes, preview_token: preview.preview_token), attributes, preview ]
  end

  it "offers group folios but excludes unrelated bookings and currencies" do
    unrelated = create(:booking_folio, hotel:, booking: create(:booking, hotel:))
    foreign_currency = create(:booking_folio, :secondary, hotel:, booking: sibling, currency: "USD")
    expect(Folios::DestinationPolicy.folios(booking:)).to include(source, target)
    expect(Folios::DestinationPolicy.folios(booking:)).not_to include(unrelated, foreign_currency)
    expect(Folios::DestinationPolicy.related?(booking, unrelated.booking)).to be(false)
  end

  it "moves charges across siblings while retaining source identity and immutable lineage" do
    result = move
    expect(result).to be_success, result.error
    expect(result.transaction).to have_attributes(booking_folio: target, source_booking: booking, moved_from_transaction: charge)
    expect(source.reload.outstanding_balance).to eq(0)
    expect(target.reload.outstanding_balance).to eq(100)
    expect(FolioOperationLog.last).to have_attributes(source_folio: source, target_folio: target)
  end

  it "splits inferred nightly taxes with exact monetary conservation" do
    code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
    parent = create(:folio_transaction, booking_folio: source, amount: 100, transaction_code: code)
    tax = create(:folio_transaction, booking_folio: source, amount: 0.01, category: "tax",
      metadata: { tax_line: { source_transaction_code_id: code.id }, stay_date: parent.posting_date.iso8601 })
    result = Folios::Transactions::SplitTransaction.call(transaction: parent, target_folio: target, user: actor,
      reason: "Split group", percent: 50)
    expect(result).to be_success, result.error
    expect(result.source_transactions.sum(&:amount) + result.target_transactions.sum(&:amount)).to eq(100.01.to_d)
    expect(tax.reload.voided_by_transaction_id).to be_present
  end

  it "settles the screenshot balances through one atomic bulk transfer" do
    create(:folio_transaction, booking_folio: target, amount: 1245)
    create(:folio_transaction, booking_folio: target, transaction_type: "payment", category: "booking_payment",
      amount: 4474, metadata: { payment_source: "bank" })
    rows = [ 1245, 992, 992 ].map do |amount|
      room_booking = create(:booking, hotel:, group_booking: group)
      folio = create(:booking_folio, hotel:, booking: room_booking)
      create(:folio_transaction, booking_folio: folio, amount:)
    end
    result, = transfer(rows)
    expect(result).to be_success, result.error
    expect(target.reload.outstanding_balance).to eq(0)
    expect(rows.map { |row| row.booking_folio.reload.outstanding_balance }).to eq([ 0, 0, 0 ])
  end

  it "returns the completed batch on an identical retry and rejects changed inputs" do
    result, attributes, preview = transfer
    expect(result).to be_success, result.error
    expect {
      retry_result = Folios::TransferFolios.call(**attributes, preview_token: preview.preview_token)
      expect(retry_result.transactions.map(&:id)).to eq(result.transactions.map(&:id))
    }.not_to change(FolioTransaction, :count)
    changed = Folios::TransferFolios.call(**attributes.merge(reason: "Different"), preview_token: preview.preview_token)
    expect(changed.error).to include("different transfer")
  end

  it "transfers charges, payments, prepayments and future routes with a blank reason" do
    booking.update!(check_in: hotel.current_business_date, check_out: hotel.current_business_date + 2.days)
    create(:booking_room, booking:, subtotal: 200)
    code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
    payment = create(:folio_transaction, booking_folio: source, transaction_type: "payment", category: "cash", amount: 40)
    deposit = create(:deposit, :prepayment, booking:, hotel:, amount: 60)
    application = Deposits::Apply.call(deposit:, booking_folio: source, amount: 60, actor:)
    expect(application).to be_success, application.error
    receipts_before = Receipt.count

    result, attributes, preview = transfer([ charge, payment, application.transaction ], reason: "  ", route_code_ids: [ code.id ])

    expect(result).to be_success, result.error
    expect(source.reload.outstanding_balance).to eq(0)
    expect(target.reload.outstanding_balance).to eq(0)
    expect(Receipt.count).to eq(receipts_before)
    expect(deposit.reload.applied_amount).to eq(60)
    expect(Bookings::PaymentProgress.new(booking).paid_total).to eq(100)
    expect(booking.folio_routing_rules.active.find_by!(transaction_code: code).target_folio).to eq(target)
    logs = FolioOperationLog.where(source_transaction_id: [ charge.id, payment.id, application.transaction.id ])
    expect(logs.pluck(:reason)).to all(eq("Folio transfer"))
    expect {
      expect(Folios::TransferFolios.call(**attributes, preview_token: preview.preview_token)).to be_success
    }.not_to change(FolioTransaction, :count)
    changed = Folios::TransferFolios.call(**attributes.merge(reason: "Folio transfer"), preview_token: preview.preview_token)
    expect(changed.error).to include("different transfer")
  end

  it "accepts a transfer without a reason parameter" do
    attributes = transfer_attributes.except(:reason)
    preview = Folios::TransferFolios.preview(**attributes)
    expect(preview).to be_success, preview.error
    result = Folios::TransferFolios.call(**attributes, preview_token: preview.preview_token)
    expect(result).to be_success, result.error
  end

  it "rejects a stale preview after another posting" do
    attributes = transfer_attributes
    preview = Folios::TransferFolios.preview(**attributes)
    create(:folio_transaction, booking_folio: source, amount: 5)
    expect {
      result = Folios::TransferFolios.call(**attributes, preview_token: preview.preview_token)
      expect(result.error).to include("preview changed")
    }.not_to change(FolioTransaction, :count)
    expect(charge.reload.voided_by_transaction_id).to be_nil
  end

  it "rolls the entire batch back if a later transfer fails" do
    other = create(:folio_transaction, booking_folio: source, amount: 25)
    attributes = transfer_attributes([ charge, other ])
    preview = Folios::TransferFolios.preview(**attributes)
    allow(Folios::Transactions::MoveTransaction).to receive(:call).and_call_original
    allow(Folios::Transactions::MoveTransaction).to receive(:call).with(hash_including(transaction: other))
      .and_return(Folios::Transactions::MoveResult.failure("Posting blocked", transactions: []))
    expect {
      expect(Folios::TransferFolios.call(**attributes, preview_token: preview.preview_token)).not_to be_success
    }.not_to change(FolioTransaction, :count)
    expect(charge.reload.voided_by_transaction_id).to be_nil
    expect(FolioTransferBatch.count).to eq(0)
  end

  it "splits a manual payment without changing credit, issuing receipts, or counting new cash" do
    payment = create(:folio_transaction, booking_folio: source, transaction_type: "payment", category: "cash", amount: 100,
      metadata: { payment_source: "cash" })
    before_receipts = Receipt.count
    result = Folios::Transactions::SplitTransaction.call(transaction: payment, target_folio: target, user: actor,
      reason: "Allocate group payment", amount: 40)
    expect(result).to be_success, result.error
    expect(source.reload.outstanding_balance).to eq(-60)
    expect(target.reload.outstanding_balance).to eq(-40)
    expect(Bookings::PaymentProgress.new(booking).paid_total).to eq(100)
    expect(Bookings::PaymentProgress.new(sibling).paid_total).to eq(0)
    expect(Receipt.count).to eq(before_receipts)
    expect(payment.reload.receipt).to be_present
    expect(result.target_transactions.first.source_booking).to eq(booking)
    report = HotelPortal::Reports::CashierSalesReport.new(hotel:, start_date: hotel.current_business_date, end_date: hotel.current_business_date).call
    expect(report.all_totals[:total_collected]).to eq(100)
    expect(report.all_totals[:total_refunded]).to eq(0)
  end

  it "moves linked staff payments while rejecting actual gateway payments" do
    manual = create(:payment_transaction, booking:, gateway: "manual", event_source: "manual_booking")
    payment = create(:folio_transaction, booking_folio: source, transaction_type: "payment", category: "gateway_payment", amount: 100,
      metadata: { payment_transaction_id: manual.id })
    expect(move(payment)).to be_success
    gateway = create(:folio_transaction, booking_folio: source, transaction_type: "payment", category: "gateway_payment", amount: 100,
      metadata: { payment_source: "gateway" })
    expect(move(gateway).error).to include("Gateway")
  end

  it "splits a prepayment application using immutable deposit movements" do
    deposit = create(:deposit, :prepayment, booking:, hotel:, amount: 100)
    application = Deposits::Apply.call(deposit:, booking_folio: source, amount: 100, actor:)
    expect(application).to be_success, application.error
    original_receipt = deposit.receipt
    result = Folios::Transactions::SplitTransaction.call(transaction: application.transaction, target_folio: target,
      user: actor, reason: "Allocate prepayment", amount: 40)
    expect(result).to be_success, result.error
    expect(deposit.reload.available_amount).to eq(0)
    expect(deposit.applied_amount).to eq(100)
    expect(application.movement.reload.reversal).to be_present
    expect(deposit.receipt).to eq(original_receipt)
    expect(Bookings::PaymentProgress.new(booking).paid_total).to eq(100)
    expect(Bookings::PaymentProgress.new(sibling).paid_total).to eq(0)
  end

  it "rejects closed, foreign, unsupported and permission-less operations without posting" do
    charge
    target.update!(status: "closed")
    expect { expect(move).not_to be_success }.not_to change(FolioTransaction, :count)
    target.update_columns(status: "open")
    unauthorized = create(:user)
    expect { expect(move(user: unauthorized)).not_to be_success }.not_to change(FolioTransaction, :count)
    security = create(:folio_transaction, booking_folio: source, transaction_type: "payment", category: "security_deposit", amount: 100)
    expect(move(security).error).to include("security")
  end

  it "routes future charges and forecasts to the master while retaining source identity" do
    booking.update!(check_in: hotel.current_business_date, check_out: hotel.current_business_date + 2.days)
    create(:booking_room, booking:, subtotal: 200)
    code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
    result, = transfer(route_code_ids: [ code.id ])
    expect(result).to be_success, result.error
    expect(booking.folio_routing_rules.active.find_by!(transaction_code: code).target_folio).to eq(target)
    forecasts = FolioForecastedCharge.forecast.where(source_booking: booking, charge_kind: "accommodation")
    expect(forecasts).not_to be_empty
    expect(forecasts.pluck(:booking_folio_id).uniq).to eq([ target.id ])
    expect(Folios::Lifecycle::IncomingRouteBlocker.call(folio: target)).to include(booking.formatted_reservation_number)
  end

  it "recognises moved and split nightly charges without reporting missing or duplicate charges" do
    date = hotel.current_business_date
    booking.update!(check_in: date, check_out: date + 1.day, tax_lines: [])
    room = create(:booking_room, booking:, subtotal: 100)
    code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
    key = Folios::Charges::ChargePostingKeys.nightly_charge_key(booking:, date:, charge_kind: "accommodation", identity: room.id)
    parent = create(:folio_transaction, booking_folio: source, amount: 100, transaction_code: code,
      metadata: { nightly_charge_key: key, stay_date: date.iso8601 })
    result = Folios::Transactions::SplitTransaction.call(transaction: parent, target_folio: target, user: actor, reason: "Group split", percent: 40)
    expect(result).to be_success, result.error
    report = Folios::Charges::NightlyChargeReconciliation.call(booking:, business_date: date)
    expect(report).to be_valid, report.issues.inspect
    Folios::Forecasts::SyncForecastedCharges.call(booking_folio: source)
    expect(FolioForecastedCharge.forecast.where(source_booking: booking, charge_kind: "accommodation")).to be_empty
  end
  it "handles two submitted copies of one reviewed transfer without duplicate postings" do
    attributes = transfer_attributes
    preview = Folios::TransferFolios.preview(**attributes)
    gate = Queue.new
    workers = 2.times.map do
      Thread.new do
        gate.pop
        ActiveRecord::Base.connection_pool.with_connection do
          Folios::TransferFolios.call(**attributes.merge(booking: Booking.find(booking.id)), preview_token: preview.preview_token)
        end
      end
    end
    2.times { gate << true }
    results = workers.map(&:value)
    expect(results).to all(be_success)
    expect(results.map { |result| result.transactions.map(&:id) }.uniq.size).to eq(1)
    expect(target.reload.outstanding_balance).to eq(100)
  ensure
    workers&.each { |worker| worker.kill if worker.alive? }
  end

  it "keeps revenue totals and source attribution unchanged by a charge transfer" do
    charge
    date = hotel.current_business_date
    before = HotelPortal::Reports::DailyRevenueReport.new(hotel:, start_date: date, end_date: date).call
    expect(move).to be_success
    after = HotelPortal::Reports::DailyRevenueReport.new(hotel:, start_date: date, end_date: date).call
    expect(after.totals).to eq(before.totals)
    expect(after.source_rows).to eq(before.source_rows)
  end

  it "shows incoming forecasts beyond the destination booking's checkout date" do
    date = hotel.current_business_date
    sibling.update!(check_out: date + 1.day)
    booking.update!(check_out: date + 5.days)
    forecast = create(:folio_forecasted_charge, booking_folio: target, source_booking: booking, stay_date: date + 3.days)
    expect(target.projected_forecasts).to include(forecast)
  end

  it "reroutes scheduled extra forecasts without changing their source or amount" do
    create(:booking_room, booking:, subtotal: 100)
    code = create(:transaction_code, hotel:, kind: "charge", category: "other")
    forecast = create(:folio_forecasted_charge, booking_folio: source, charge_kind: "extra_charge", amount: 30,
      metadata: { transaction_code_id: code.id })
    FolioRoutingRule.create!(booking:, hotel:, transaction_code: code, target_folio: target)
    Folios::Routing::RefreshBookingForecasts.call(booking:)
    expect(forecast.reload.status).to eq("superseded")
    expect(target.folio_forecasted_charges.forecast.find_by!(identity: forecast.identity)).to have_attributes(source_booking: booking, amount: 30)
  end

  it "shows incoming transfers in the destination activity log" do
    expect(move).to be_success
    presenter = HotelPortal::Folios::ShowPresenter.new(booking: sibling, hotel:, user: actor, active_folio_id: target.id)
    expect(presenter.activity_log_rows).not_to be_empty
  end

  it "prevents a master from closing while an active sibling still has future routes" do
    code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
    FolioRoutingRule.create!(booking:, hotel:, transaction_code: code, target_folio: target)
    result = Folios::Lifecycle::CloseFolio.call(folio: target, user: actor)
    expect(result.error).to include("route future charges", booking.formatted_reservation_number, code.code)
    expect(target.reload).to be_open
  end
  it "rejects AR history, unrelated bookings and mismatched currencies" do
    charge
    foreign = create(:booking_folio, hotel:, booking: create(:booking, hotel:))
    expect(move(target_folio: foreign).error).to include("same booking or group")
    other_currency = create(:booking_folio, hotel:, booking: sibling, is_primary: false, currency: "USD")
    expect(move(target_folio: other_currency).error).to include("same currency")
    ar_target = create(:booking_folio, :secondary, hotel:, booking: sibling)
    create(:ar_invoice, booking_folio: ar_target, hotel:)
    expect(move(target_folio: ar_target).error).to include("AR correction")
  end

  it "preserves paid instalments and deadlines when a manual payment moves" do
    stage = booking.payment_instalments.create!(position: 1, kind: "deposit", status: "paid", amount: 100,
      due_at: 1.day.from_now, paid_at: Time.current, paid_by: actor)
    payment = create(:folio_transaction, booking_folio: source, transaction_type: "payment", category: "cash", amount: 100,
      metadata: { payment_source: "cash" })
    stage.update!(payment_folio_transaction: payment)
    original_state = stage.reload.attributes
    expect(move(payment)).to be_success
    expect(stage.reload.attributes).to eq(original_state)
    expect(Bookings::PaymentProgress.new(booking).paid_total).to eq(100)
  end

  it "skips moved nightly charges on audit and catch-up retries" do
    date = hotel.current_business_date - 1.day
    booking.update!(check_in: date, check_out: date + 1.day, tax_lines: [])
    room = create(:booking_room, booking:, subtotal: 100)
    audit = create(:night_audit, hotel:, business_date: date, status: "completed")
    code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
    key = Folios::Charges::ChargePostingKeys.nightly_charge_key(booking:, date:, charge_kind: "accommodation", identity: room.id)
    row = create(:folio_transaction, booking_folio: source, amount: 100, transaction_code: code, posting_date: date,
      metadata: { nightly_charge_key: key, stay_date: date.iso8601 })
    expect(move(row)).to be_success
    expect {
      Folios::Charges::PostNightlyCharges.call(night_audit: audit, user: actor)
      Folios::Charges::ProcessCatchUpCharges.call(booking:, user: actor)
    }.not_to change(FolioTransaction, :count)
    expect(Folios::Charges::NightlyChargeReconciliation.call(booking:, business_date: date)).to be_valid
  end
  it "moves only the taxes linked to the selected parent" do
    code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
    first = create(:folio_transaction, booking_folio: source, amount: 100, transaction_code: code)
    second = create(:folio_transaction, booking_folio: source, amount: 200, transaction_code: code)
    first_tax = create(:folio_transaction, booking_folio: source, category: "tax", amount: 8, parent_transaction: first,
      metadata: { tax_line: { source_transaction_code_id: code.id }, parent_transaction_id: first.id })
    second_tax = create(:folio_transaction, booking_folio: source, category: "tax", amount: 16, parent_transaction: second,
      metadata: { tax_line: { source_transaction_code_id: code.id }, parent_transaction_id: second.id })
    expect(move(first)).to be_success
    expect(first_tax.reload.voided_by_transaction_id).to be_present
    expect(second_tax.reload.voided_by_transaction_id).to be_nil
    expect(source.reload.outstanding_balance).to eq(216)
    expect(target.reload.outstanding_balance).to eq(108)
  end
end

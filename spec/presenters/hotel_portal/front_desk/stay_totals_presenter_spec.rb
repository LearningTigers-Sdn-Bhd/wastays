require "rails_helper"

RSpec.describe HotelPortal::FrontDesk::StayTotalsPresenter do
  let(:hotel) { create(:hotel, status: "approved") }
  let(:booking) { create(:booking, hotel:, total_amount: 540, check_in: Date.current, check_out: Date.current + 3) }
  let(:folio) { booking.booking_folios.first || create(:booking_folio, booking:, hotel:) }

  def post(transaction_type, category, amount, on: folio)
    create(:folio_transaction, booking_folio: on, transaction_type:, category:, amount:)
  end

  def forecast(stay_date, amount, on: folio, status: "forecast")
    create(:folio_forecasted_charge, booking_folio: on, stay_date:, amount:, status:, identity: "#{stay_date}-#{amount}")
  end

  def presenter
    described_class.new(booking.reload)
  end

  it "reports zero on a folio with no transactions" do
    expect(presenter.charges).to eq(0)
    expect(presenter.paid).to eq(0)
    expect(presenter.balance).to eq(0)
  end

  it "subtracts payments from charges instead of adding them" do
    post(:charge, "accommodation", 540)
    post(:payment, "cash", 200)

    expect(presenter.charges).to eq(540)
    expect(presenter.paid).to eq(200)
    expect(presenter.balance).to eq(340)
  end

  it "settles to a zero balance once the stay is paid in full" do
    post(:charge, "accommodation", 540)
    post(:payment, "cash", 540)

    expect(presenter.balance).to eq(0)
  end

  it "counts refunds as negative payments, raising the balance" do
    post(:charge, "accommodation", 540)
    post(:payment, "cash", 540)
    post(:payment, "refund", -100)

    expect(presenter.paid).to eq(440)
    expect(presenter.balance).to eq(100)
  end

  it "folds adjustments into the charged side" do
    post(:charge, "accommodation", 540)
    post(:adjustment, "discount", -40)

    expect(presenter.charges).to eq(500)
    expect(presenter.balance).to eq(500)
  end

  it "counts nights that are forecast but not yet posted" do
    post(:charge, "accommodation", 180)
    forecast(Date.current + 1, 180)
    forecast(Date.current + 2, 180)

    expect(presenter.posted).to eq(180)
    expect(presenter.upcoming).to eq(360)
    expect(presenter.charges).to eq(540)
    expect(presenter.balance).to eq(540)
  end

  it "ignores forecasts that are already actualized or past the departure date" do
    forecast(Date.current, 180, status: "actualized")
    forecast(Date.current + 1, 180, status: "superseded")
    forecast(Date.current + 5, 180)
    forecast(Date.current + 2, 180)

    expect(presenter.upcoming).to eq(180)
  end

  it "ignores forecasts on a closed folio" do
    forecast(Date.current + 1, 180)
    folio.update_columns(status: "closed")

    expect(presenter.upcoming).to eq(0)
  end

  it "ignores forecasts once the stay is over or called off" do
    forecast(Date.current + 1, 180)
    booking.update_columns(status: "cancelled")

    expect(presenter.upcoming).to eq(0)
    expect(presenter.balance).to eq(0)
  end

  it "matches BookingFolio#projected_outstanding_balance across every folio on the booking" do
    second_folio = create(:booking_folio, booking:, hotel:)
    post(:charge, "accommodation", 180)
    post(:payment, "cash", 200)
    post(:charge, "fb", 60, on: second_folio)
    post(:adjustment, "discount", -10, on: second_folio)
    forecast(Date.current + 1, 180)
    forecast(Date.current + 2, 180, on: second_folio)

    expected = booking.reload.booking_folios.sum { |record| record.projected_outstanding_balance.to_d }
    expect(presenter.balance).to eq(expected)
    expect(presenter.charges - presenter.paid).to eq(presenter.balance)
  end

  it "reads preloaded transactions without issuing further queries" do
    post(:charge, "accommodation", 540)
    post(:payment, "cash", 200)

    preloaded = Booking.where(id: booking.id).includes(booking_folios: [ :folio_transactions, :folio_forecasted_charges ]).first
    subject = described_class.new(preloaded)

    queries = 0
    callback = ->(*, payload) { queries += 1 unless payload[:name].in?([ "SCHEMA", "TRANSACTION" ]) }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      subject.balance
    end

    expect(queries).to eq(0)
  end
end

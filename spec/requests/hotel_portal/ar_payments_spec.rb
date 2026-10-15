# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::ArPayments", type: :request do
  let(:hotel) { create(:hotel, status: "live") }
  let(:other_hotel) { create(:hotel, status: "live") }
  let(:user) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account) }
  let(:view_reports) { Permission.find_or_create_by!(slug: "view_reports") { |permission| permission.name = "View Reports" } }
  let(:manage_ar_payments) { Permission.find_or_create_by!(slug: "manage_ar_payments") { |permission| permission.name = "Manage AR Payments" } }

  before do
    role.permissions << [ view_reports, manage_ar_payments ]
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  it "renders the redesigned index with metrics, filters, statuses, and scoped rows" do
    payment = create(:ar_payment, hotel: hotel, hotel_corporate_account: create(:hotel_corporate_account, hotel: hotel), amount: 500, reference_number: "BANK-AR-500")
    hidden = create(:ar_payment, hotel: other_hotel, hotel_corporate_account: create(:hotel_corporate_account, hotel: other_hotel), amount: 999, reference_number: "BANK-HIDDEN")

    get hotel_ar_payments_path(hotel)

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Received This Month")
    expect(response.body).to include("Bank Transfers This Month")
    expect(response.body).to include("Pending Submissions")
    expect(response.body).to include("BANK-AR-500")
    expect(response.body).not_to include(hidden.reference_number)
    expect(response.body).to include(hotel_ar_payment_path(hotel, payment))
  end

  it "combines confirmed payments and pending submissions into one Payment Record list" do
    relationship = create(:hotel_corporate_account, hotel: hotel)
    payment = create(:ar_payment, hotel: hotel, hotel_corporate_account: relationship, amount: 250, reference_number: "COMBINED-PAY")
    submission = create(:ar_payment_submission, hotel: hotel, hotel_corporate_account: relationship, amount: 175, reference_number: "COMBINED-SLIP")
    approved_submission = create(:ar_payment_submission, hotel: hotel, hotel_corporate_account: relationship, amount: 90, reference_number: "COMBINED-APPROVED", status: "approved", ar_payment: payment, reviewed_by: user, reviewed_at: Time.current)

    get hotel_ar_payments_path(hotel)

    expect(response).to have_http_status(:success)
    expect(response.body).to include("COMBINED-PAY")
    expect(response.body).to include("COMBINED-SLIP")
    expect(response.body).to include("Pending Review")
    expect(response.body).not_to include("COMBINED-APPROVED")
    expect(response.body).to include(new_hotel_ar_payment_path(hotel, ar_payment_submission_id: submission.id))
  end

  it "flags a pending submission on the list once its booking has been voided" do
    relationship = create(:hotel_corporate_account, hotel: hotel)
    booking = create(:booking, hotel: hotel, hotel_corporate_account: relationship, status: "confirmed")
    create(:ar_payment_submission, hotel: hotel, hotel_corporate_account: relationship,
                                   booking: booking, auto_invoice: nil, reference_number: "VOIDED-BOOKING-SLIP")
    booking.transition_status_to!("voided", event: "void")

    get hotel_ar_payments_path(hotel)

    expect(response.body).to include("VOIDED-BOOKING-SLIP")
    expect(response.body).to include("Booking voided")
  end

  # The action this page leads to, so the warning has to sit here too -- not
  # only on the submission's own read-only page, one click behind this one.
  it "warns on the record-payment screen when a pending slip's booking has been voided" do
    relationship = create(:hotel_corporate_account, hotel: hotel)
    booking = create(:booking, hotel: hotel, hotel_corporate_account: relationship, status: "confirmed")
    submission = create(:ar_payment_submission, hotel: hotel, hotel_corporate_account: relationship,
                                                booking: booking, auto_invoice: nil)
    booking.transition_status_to!("voided", event: "void")

    get new_hotel_ar_payment_path(hotel, ar_payment_submission_id: submission.id)

    expect(response.body).to include(booking.formatted_reservation_number)
    expect(response.body).to include("Voided")
    expect(response.body).to include("Recording this payment will")
  end

  it "does not warn on the record-payment screen when the booking is still live" do
    relationship = create(:hotel_corporate_account, hotel: hotel)
    booking = create(:booking, hotel: hotel, hotel_corporate_account: relationship, status: "confirmed")
    submission = create(:ar_payment_submission, hotel: hotel, hotel_corporate_account: relationship,
                                                booking: booking, auto_invoice: nil)

    get new_hotel_ar_payment_path(hotel, ar_payment_submission_id: submission.id)

    expect(response.body).not_to include("Recording this payment will")
  end

  it "filters by query, account, and date" do
    payment = create(:ar_payment, hotel: hotel, hotel_corporate_account: create(:hotel_corporate_account, hotel: hotel), amount: 200, received_at: Date.current, reference_number: "FILTER-ME")
    create(:ar_payment, hotel: hotel, hotel_corporate_account: create(:hotel_corporate_account, hotel: hotel), amount: 300, reference_number: "HIDE-ME")

    get hotel_ar_payments_path(hotel), params: {
      query: "FILTER-ME",
      hotel_corporate_account_id: payment.hotel_corporate_account_id,
      received_from: Date.current.iso8601,
      received_to: Date.current.iso8601
    }

    expect(response.body).to include("FILTER-ME")
    expect(response.body).not_to include("HIDE-ME")
  end

  it "paginates the merged payment record and hydrates the selected page" do
    relationship = create(:hotel_corporate_account, hotel: hotel)
    payments = Array.new(26) do |index|
      create(
        :ar_payment,
        hotel: hotel,
        hotel_corporate_account: relationship,
        reference_number: "PAY-PAGE-#{index}",
        received_at: Date.current - index.days
      )
    end

    get hotel_ar_payments_path(hotel), params: { page: 2 }

    expect(response.body).to include(payments.last.reference_number)
    expect(response.body).not_to include(payments.first.reference_number)
  end

  it "shows payment details, active and reversed history, and eligible invoices" do
    payment = create(:ar_payment, hotel: hotel, hotel_corporate_account: create(:hotel_corporate_account, hotel: hotel), amount: 500, notes: "Bank receipt")
    invoice = create_invoice(relationship: payment.hotel_corporate_account, amount: 500)
    allocation = create(:ar_payment_allocation, ar_payment: payment, ar_invoice: invoice, amount: 100)
    create(:ar_payment_allocation_reversal, ar_payment_allocation: allocation, reversed_by: user, reason: "Wrong invoice")

    get hotel_ar_payment_path(hotel, payment)

    expect(response).to have_http_status(:success)
    expect(response.body).to include(payment.reference_number)
    expect(response.body).to include("Payment record")
    expect(response.body).to include("Allocation ledger")
    expect(response.body).to include("Wrong invoice")
    expect(response.body).to include("Open invoices")
    expect(response.body).to include(invoice.formatted_invoice_number)
  end

  it "shows each open invoice's guest name and source references with its allocation limit" do
    payment = create(:ar_payment, hotel: hotel, hotel_corporate_account: create(:hotel_corporate_account, hotel: hotel), amount: 500)
    invoices = [
      create_invoice(relationship: payment.hotel_corporate_account, amount: 300),
      create_invoice(relationship: payment.hotel_corporate_account, amount: 800)
    ]
    invoices.first.booking.update!(guest_name: "Alex & <Taylor>")
    invoices.last.booking.update!(guest_name: "Jordan Lee")

    get hotel_ar_payment_path(hotel, payment)

    expect(response).to have_http_status(:success)
    doc = Nokogiri::HTML(response.body)
    rows = doc.css("section[data-controller='ar-payment-form'] tbody tr")
    expect(rows.size).to eq(2)

    invoices.each do |invoice|
      row = rows.find { |candidate| candidate.at_css("td").text == invoice.formatted_invoice_number }
      source = row.css("td")[1]
      expect(source.css("p").map(&:text)).to eq([
        invoice.booking.guest_name,
        "#{invoice.booking.confirmation_token} · #{invoice.booking_folio.folio_reference_display}"
      ])

      input = row.at_css("input[type='number']")
      expect(input["name"]).to eq("allocations[#{invoice.id}]")
      expect(input["max"].to_d).to eq([ invoice.outstanding_amount, payment.amount ].min)
    end

    expect(response.body).to include("Alex &amp; &lt;Taylor&gt;")
    expect(rows.css("taylor")).to be_empty
  end

  it "shows the guest name for each allocation in the ledger and each remittance suggestion" do
    relationship = create(:hotel_corporate_account, hotel: hotel)
    invoice = create_invoice(relationship: relationship, amount: 243)
    invoice.booking.update!(guest_name: "Yang Chun Yan")
    payment = create(:ar_payment, hotel: hotel, hotel_corporate_account: relationship, amount: 243,
                                  metadata: { "source" => "corporate_portal_gateway", "remittance_suggestions" => [
                                    { "ar_invoice_id" => invoice.id, "invoice_label" => invoice.formatted_invoice_number, "due_on" => invoice.due_on.iso8601,
                                      "outstanding_amount" => "243.0", "suggested_amount" => "243.0" }
                                  ] })
    create(:ar_payment_allocation, ar_payment: payment, ar_invoice: invoice, amount: 243)

    get hotel_ar_payment_path(hotel, payment)

    expect(response).to have_http_status(:success)
    doc = Nokogiri::HTML(response.body)
    ledger_row = doc.css("[data-testid='allocation-history'] tbody tr").first
    expect(ledger_row.css("td")[0].text).to include(invoice.formatted_invoice_number, "Yang Chun Yan")
    expect(doc.css("[data-testid='allocation-history'] article").first.text).to include("Yang Chun Yan")
    suggestion_row = doc.css("table").find { |table| table.text.include?("Outstanding snapshot") }.css("tbody tr").first
    expect(suggestion_row.css("td")[1].text).to eq("Yang Chun Yan")
  end

  it "records a fully unapplied payment" do
    expect {
      post hotel_ar_payments_path(hotel), params: {
        ar_payment: {
          hotel_corporate_account_id: create(:hotel_corporate_account, hotel: hotel).id,
          amount: "500.00",
          currency: hotel.default_currency,
          reference_number: "UNAPPLIED-1",
          received_at: Date.current.iso8601,
          payment_method: "bank_transfer"
        },
        allocations: {}
      }
    }.to change(ArPayment, :count).by(1)

    expect(response).to redirect_to(hotel_ar_payment_path(hotel, ArPayment.last))
    expect(ArPayment.last.unallocated_amount).to eq(500.to_d)
  end

  # Approving a booking's remittance slip through the ordinary "record a
  # payment" screen has to reach the booking's own folio, not only the AR
  # ledger -- otherwise the desk still finds the stay unpaid at checkout
  # despite the hotel having already told the agent it was settled.
  it "posts a booking prepayment slip's approval to the booking's own folio" do
    relationship = create(:hotel_corporate_account, hotel: hotel, account_type: "travel_agent")
    booking = create(:booking, hotel: hotel, hotel_corporate_account: relationship,
                               status: "confirmed", payment_status: "pending",
                               payment_due_at: 6.hours.from_now, total_amount: 300.0, currency: hotel.default_currency)
    folio = create(:booking_folio, booking: booking, hotel: hotel, currency: hotel.default_currency)
    submission = create(:ar_payment_submission, hotel: hotel, hotel_corporate_account: relationship, booking: booking,
                                                auto_invoice: nil, amount: 300.0, currency: hotel.default_currency)

    post hotel_ar_payments_path(hotel), params: {
      ar_payment_submission_id: submission.id,
      ar_payment: {
        hotel_corporate_account_id: relationship.id,
        amount: "300.00",
        currency: hotel.default_currency,
        reference_number: submission.reference_number,
        received_at: Date.current.iso8601,
        payment_method: "bank_transfer"
      },
      allocations: {}
    }

    expect(submission.reload.status).to eq("approved")
    expect(booking.reload).to have_attributes(payment_status: "captured", payment_due_at: nil)
    expect(folio.folio_transactions.payment.sum(:amount)).to eq(300.to_d)
  end

  it "shows guest names and source references on the record-payment form" do
    relationship = create(:hotel_corporate_account, hotel: hotel)
    invoices = [
      create_invoice(relationship: relationship, amount: 250),
      create_invoice(relationship: relationship, amount: 300)
    ]
    invoices.first.booking.update!(guest_name: "Alex & <Taylor>")
    invoices.last.booking.update!(guest_name: "Jordan Lee")

    get new_hotel_ar_payment_path(hotel), params: { ar_invoice_id: invoices.first.id }

    expect(response).to have_http_status(:success)
    rows = Nokogiri::HTML(response.body).css("#ar_payment_invoice_allocations tbody tr")
    expect(rows.size).to eq(2)
    invoices.each do |invoice|
      row = rows.find { |candidate| candidate.at_css("td").text == invoice.formatted_invoice_number }
      expect(row.css("td")[1].css("p").map(&:text)).to eq([
        invoice.booking.guest_name,
        "#{invoice.booking.confirmation_token} · #{invoice.booking_folio.folio_reference_display}"
      ])
      input = row.at_css("input[type='number']")
      expect(input["name"]).to eq("allocations[#{invoice.id}]")
      expect(input["max"].to_d).to eq(invoice.outstanding_amount)
      expect(input["value"]).to eq(invoice == invoices.first ? invoice.outstanding_amount.to_s : nil)
    end
    expect(response.body).to include("Alex &amp; &lt;Taylor&gt;")
  end

  it "shows guest names for the selected submission invoices while preserving hidden allocations" do
    relationship = create(:hotel_corporate_account, hotel: hotel)
    invoices = [
      create_invoice(relationship: relationship, amount: 300),
      create_invoice(relationship: relationship, amount: 400)
    ]
    invoices.first.booking.update!(guest_name: "Alex Taylor")
    invoices.last.booking.update!(guest_name: "Jordan Lee")
    unselected = create_invoice(relationship: relationship, amount: 500)
    submission = build(:ar_payment_submission, hotel: hotel, hotel_corporate_account: relationship,
                       submitted_by: create(:user, :corporate, account: relationship.corporate_account), amount: 250, auto_invoice: nil)
    amounts = [ 100, 150 ]
    invoices.each_with_index do |invoice, index|
      submission.ar_payment_submission_allocations.build(ar_invoice: invoice, amount: amounts[index])
    end
    submission.save!

    get new_hotel_ar_payment_path(hotel), params: { ar_payment_submission_id: submission.id }

    expect(response).to have_http_status(:success)
    frame = Nokogiri::HTML(response.body).at_css("#ar_payment_invoice_allocations")
    rows = frame.css("tbody tr")
    expect(rows.size).to eq(2)
    expect(frame.css("input[type='number']")).to be_empty
    expect(frame.text).not_to include(unselected.formatted_invoice_number)
    invoices.each_with_index do |invoice, index|
      row = rows.find { |candidate| candidate.at_css("td").text == invoice.formatted_invoice_number }
      expect(row.css("td")[1].css("p").map(&:text)).to eq([
        invoice.booking.guest_name,
        "#{invoice.booking.confirmation_token} · #{invoice.booking_folio.folio_reference_display}"
      ])
      expect(row.css("td")[3].text).to include("#{invoice.currency} #{format('%.2f', amounts[index])}")
      input = frame.at_css("input[name='allocations[#{invoice.id}]']")
      expect(input["type"]).to eq("hidden")
      expect(input["value"].to_d).to eq(amounts[index].to_d)
    end
  end

  it "refreshes eligible invoices and guest names for the selected corporate account" do
    relationship = create(:hotel_corporate_account, hotel: hotel)
    invoices = [
      create_invoice(relationship: relationship, amount: 250),
      create_invoice(relationship: relationship, amount: 300)
    ]
    invoices.first.booking.update!(guest_name: "Alex Taylor")
    invoices.last.booking.update!(guest_name: "Jordan Lee")
    hidden_relationship = create(:hotel_corporate_account, hotel: hotel)
    hidden_invoice = create_invoice(relationship: hidden_relationship, amount: 300)
    hidden_invoice.booking.update!(guest_name: "Hidden Guest")

    get eligible_invoices_hotel_ar_payments_path(hotel), params: { hotel_corporate_account_id: relationship.id }

    expect(response).to have_http_status(:success)
    rows = Nokogiri::HTML(response.body).css("#ar_payment_invoice_allocations tbody tr")
    expect(rows.size).to eq(2)
    invoices.each do |invoice|
      row = rows.find { |candidate| candidate.at_css("td").text == invoice.formatted_invoice_number }
      expect(row.css("td")[1].css("p").map(&:text)).to eq([
        invoice.booking.guest_name,
        "#{invoice.booking.confirmation_token} · #{invoice.booking_folio.folio_reference_display}"
      ])
      input = row.at_css("input[type='number']")
      expect(input["name"]).to eq("allocations[#{invoice.id}]")
      expect(input["max"].to_d).to eq(invoice.outstanding_amount)
      expect(input["value"]).to be_nil
    end
    expect(response.body).not_to include(hidden_invoice.formatted_invoice_number)
    expect(response.body).not_to include("Hidden Guest")
    expect(response.body).to include("ar_payment_invoice_allocations")
  end

  it "allocates remaining balance and reverses the allocation" do
    payment = create(:ar_payment, hotel: hotel, hotel_corporate_account: create(:hotel_corporate_account, hotel: hotel), amount: 400)
    invoice = create_invoice(relationship: payment.hotel_corporate_account, amount: 500)

    post hotel_ar_payment_allocations_path(hotel, payment), params: { allocations: { invoice.id => "400.00" } }

    allocation = payment.ar_payment_allocations.last
    expect(response).to redirect_to(hotel_ar_payment_path(hotel, payment))
    expect(invoice.reload.outstanding_amount).to eq(100.to_d)

    post hotel_ar_payment_allocation_reversal_path(hotel, payment, allocation), params: { reason: "Wrong invoice" }

    expect(response).to redirect_to(hotel_ar_payment_path(hotel, payment))
    expect(invoice.reload.outstanding_amount).to eq(500.to_d)
    expect(allocation.reload).to be_reversed
  end

  it "voids an unallocated payment and drops it from the month total" do
    payment = create(:ar_payment, hotel: hotel, hotel_corporate_account: create(:hotel_corporate_account, hotel: hotel), amount: 400)

    get hotel_ar_payment_path(hotel, payment)
    expect(response.body).to include("Void payment")

    post hotel_ar_payment_void_path(hotel, payment), params: { reason: "Recorded in error" }

    expect(response).to redirect_to(hotel_ar_payment_path(hotel, payment))
    expect(payment.reload).to be_voided

    follow_redirect!
    expect(response.body).to include("payment-voided-notice")
    expect(response.body).to include("Recorded in error")
    expect(response.body).not_to include("Void this payment?")
  end

  it "hides the void action while the payment has an active allocation" do
    payment = create(:ar_payment, hotel: hotel, hotel_corporate_account: create(:hotel_corporate_account, hotel: hotel), amount: 400)
    invoice = create_invoice(relationship: payment.hotel_corporate_account, amount: 500)
    post hotel_ar_payment_allocations_path(hotel, payment), params: { allocations: { invoice.id => "400.00" } }

    get hotel_ar_payment_path(hotel, payment)

    expect(response.body).not_to include("Void this payment?")
    expect(response.body).to include("void-blocked-hint")

    post hotel_ar_payment_void_path(hotel, payment), params: { reason: "Nope" }
    expect(flash[:alert]).to eq("Reverse the active allocations before voiding this payment.")
    expect(payment.reload).not_to be_voided
  end

  it "does not let view_reports void a payment" do
    role.permissions.delete(manage_ar_payments)
    payment = create(:ar_payment, hotel: hotel, hotel_corporate_account: create(:hotel_corporate_account, hotel: hotel), amount: 400)

    post hotel_ar_payment_void_path(hotel, payment), params: { reason: "Nope" }

    expect(payment.reload).not_to be_voided
  end

  it "keeps view_reports read-only" do
    role.permissions.delete(manage_ar_payments)
    relationship = create(:hotel_corporate_account, hotel: hotel)

    get hotel_ar_payments_path(hotel)
    expect(response).to have_http_status(:success)
    expect(response.body).not_to include("Record Received Payment")

    post hotel_ar_payments_path(hotel), params: {
      ar_payment: {
        hotel_corporate_account_id: relationship.id,
        amount: "100.00",
        currency: hotel.default_currency,
        reference_number: "DENIED",
        received_at: Date.current.iso8601,
        payment_method: "cash"
      }
    }
    expect(response).to have_http_status(:forbidden).or have_http_status(:redirect)

    payment = create(:ar_payment, hotel: hotel, hotel_corporate_account: relationship, amount: 100)
    invoice = create_invoice(relationship: relationship, amount: 100)
    post hotel_ar_payment_allocations_path(hotel, payment), params: { allocations: { invoice.id => "100.00" } }
    expect(response).to have_http_status(:forbidden).or have_http_status(:redirect)
  end

  def create_invoice(relationship:, amount:)
    booking = create(:booking, hotel: hotel)
    folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel, hotel_corporate_account: relationship)
    create(:ar_invoice, hotel: hotel, booking_folio: folio, hotel_corporate_account: relationship, amount: amount, paid_amount: 0, outstanding_amount: amount, currency: hotel.default_currency)
  end

  describe "reviewing a slip sent for a booking with a payment schedule" do
    let(:relationship) { create(:hotel_corporate_account, hotel: hotel, account_type: "travel_agent") }
    let(:booking) do
      create(:booking, hotel: hotel, hotel_corporate_account: relationship, status: "confirmed", payment_status: "pending",
                       total_amount: 1000, currency: "MYR", check_in: 60.days.from_now, check_out: 62.days.from_now)
    end

    before { Bookings::CreatePaymentSchedule.call(booking: booking) }

    def review(amount)
      submission = create(:ar_payment_submission, hotel: hotel, hotel_corporate_account: relationship, booking: booking, amount: amount)
      get new_hotel_ar_payment_path(hotel, ar_payment_submission_id: submission.id)
      Nokogiri::HTML(response.body)
    end

    it "shows what the slip says beside what is due now and the booking total" do
      doc = review(500)

      values = doc.css("[data-testid='slip-amount-check'] dd").map { |value| value.text.squish }
      expect(values).to eq([ "MYR 500.00", "MYR 500.00 (deposit)", "MYR 1,000.00" ])
      expect(doc.at_css("[role='alert']")).to be_nil
    end

    it "warns when the slip says less than the deposit" do
      doc = review(100)

      expect(doc.at_css("p[role='alert']").text).to include("This slip says MYR 100.00", "must be at least MYR 500.00")
    end

    it "warns when the slip says more than is owed" do
      doc = review(1500)

      expect(doc.at_css("p[role='alert']").text).to include("more than the MYR 1000.00 still owed")
    end
  end
end

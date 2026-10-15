# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Group folio transfers", type: :request do
  let(:hotel) { create(:hotel, status: "live") }
  let(:group) { create(:group_booking, hotel:) }
  let(:booking) { create(:booking, hotel:, group_booking: group, status: "checked_in") }
  let(:sibling) { create(:booking, hotel:, group_booking: group, status: "checked_in") }
  let(:source) { create(:booking_folio, hotel:, booking:) }
  let(:target) { create(:booking_folio, hotel:, booking: sibling, label: "Master A8") }
  let(:charge) { create(:folio_transaction, booking_folio: source, amount: 100) }
  let(:user) { create(:user) }
  let(:role) { create(:role, account: hotel.account) }
  let(:headers) { { "Turbo-Frame" => "folio_action_sheet" } }

  before do
    create(:user_hotel_access, user:, hotel:, role:)
    role.permissions << Permission.find_or_create_by!(slug: "view_bookings") { |permission| permission.name = "View bookings" }
    role.permissions << Permission.find_or_create_by!(slug: "manage_folio_movements") { |permission| permission.name = "Manage folio movements" }
    sign_in_as(user)
  end

  def path(**params)
    hotel_folio_action_transfer_folios_path(hotel, booking, **params)
  end

  def draft
    { source_folio_ids: [ source.id.to_s ], transaction_ids: [ charge.id.to_s ], target_folio_id: target.id.to_s,
      reason: "Group payment in master", idempotency_key: SecureRandom.uuid }
  end

  it "renders the sheet with current charges selected and payments unselected" do
    charge
    target
    payment = create(:folio_transaction, booking_folio: source, transaction_type: "payment", category: "cash", amount: 50)
    get path(active_folio_id: source.id), headers: headers
    expect(response).to have_http_status(:success)
    document = Nokogiri::HTML(response.body)
    expect(document.at_css("turbo-frame#folio_action_sheet dialog#folio-transfer-sheet")).to be_present
    expect(document.at_css("input[name='folio_transfer[transaction_ids][]'][value='#{charge.id}']")[:checked]).to be_present
    expect(document.at_css("input[name='folio_transfer[transaction_ids][]'][value='#{payment.id}']")[:checked]).to be_nil
    expect(document.at_css("input#folio-transfer-source-#{source.id}")[:type]).to eq("hidden")
    expect(document.at_css("input#folio-transfer-entry-#{payment.id}")[:class]).to include("panel-checkbox__input")
    expect(document.at_css("[data-folio-id='#{source.id}']")[:class]).to include("panel-card", "overflow-hidden")
    expect(response.body).to include("1. Choose the receiving folio", "2. Choose what to move", "3. Review the transfer", "Payment credits must be selected individually.")
    expect(document.at_css("input[name='folio_transfer[reason]']")[:required]).to be_nil
    expect(response.body).to include("Reason (optional)")
    expect(response.body).to include("Master A8")
  end

  it "previews, confirms, and completes a transfer without another posting on retry" do
    attributes = draft
    post path, params: { workflow_step: "preview", folio_transfer: attributes }, headers: headers
    expect(response).to have_http_status(:success)
    document = Nokogiri::HTML(response.body)
    token = document.at_css("input[name='preview_token']")[:value]
    expect(response.body).to include("Confirm transfer")
    expect(charge.reload.voided_by_transaction_id).to be_nil
    submission = { workflow_step: "apply", folio_transfer: attributes, preview_token: token }
    post path, params: submission, headers: headers.merge("Accept" => "text/vnd.turbo-stream.html")
    expect(response.body).to include('action="complete_sheet"')
    expect(target.reload.outstanding_balance).to eq(100)
    expect { post path, params: submission, headers: headers }.not_to change(FolioTransaction, :count)
  end

  it "shows taxes inside their charge row and separately selectable surcharges inside their payment row" do
    tax = create(:folio_transaction, booking_folio: source, category: "tax", amount: 6, parent_transaction: charge,
      metadata: { tax_line: { name: "SST 6%" } })
    payment = create(:folio_transaction, booking_folio: source, transaction_type: "payment", category: "cash", amount: 102.12,
      description: "Card payment", metadata: { payment_operation_key: "card-payment" })
    surcharge = create(:folio_transaction, booking_folio: source, amount: 2, description: "Card surcharge", operation_key: "card-payment",
      metadata: { posting_source: "payment_surcharge" })
    fee_tax = create(:folio_transaction, booking_folio: source, category: "tax", amount: 0.12, parent_transaction: surcharge)
    get path(active_folio_id: source.id), headers: headers

    expect(response).to have_http_status(:success)
    document = Nokogiri::HTML(response.body)
    parent = document.at_css("[data-folio-transfer-row-id='#{charge.id}']")
    expect(parent.at_css("[data-folio-transfer-tax-id='#{tax.id}']")).to be_present
    expect(parent.text).to include("SST 6%", "Charge + tax", "MYR 106.00")
    expect(document.at_css("input[value='#{tax.id}'][name='folio_transfer[transaction_ids][]']")).to be_nil
    payment_row = document.at_css("[data-folio-transfer-row-id='#{payment.id}']")
    fee = payment_row.at_css("[data-folio-transfer-row-id='#{surcharge.id}']")
    expect(fee.at_css("input#folio-transfer-entry-#{surcharge.id}")).to be_present
    expect(fee.at_css("[data-folio-transfer-tax-id='#{fee_tax.id}']")).to be_present
    expect(payment_row.text).to include("Select it separately to move it with the payment.")
    expect(document.css("[data-folio-transfer-row-id='#{surcharge.id}']").size).to eq(1)
    expect(document.at_css("dialog#folio-transfer-sheet")[:class]).to include("w-[48rem]")
  end

  it "reviews and confirms a transfer without a reason" do
    attributes = draft.except(:reason)
    post path, params: { workflow_step: "preview", folio_transfer: attributes }, headers: headers
    expect(response).to have_http_status(:success)
    expect(response.body).not_to include("Reason:")
    token = Nokogiri::HTML(response.body).at_css("input[name='preview_token']")[:value]

    post path, params: { workflow_step: "apply", folio_transfer: attributes, preview_token: token }, headers: headers.merge("Accept" => "text/vnd.turbo-stream.html")
    expect(response.body).to include('action="complete_sheet"')
    expect(target.reload.outstanding_balance).to eq(100)
  end

  it "keeps selected routing codes in component inputs when returning to edit" do
    code = hotel.transaction_codes.find_by!(code: "ROOM")
    post path, params: { workflow_step: "edit", folio_transfer: draft.merge(route_code_ids: [ code.id.to_s ]) }, headers: headers

    expect(response).to have_http_status(:success)
    document = Nokogiri::HTML(response.body)
    trigger = document.at_css("#folio-transfer-future-routing-trigger")
    expect(trigger["aria-expanded"]).to eq("true")
    expect(trigger.at_css("svg.panel-collapsible__indicator")).to be_present
    input = document.at_css("input#folio-transfer-route-code-#{code.id}")
    expect(input[:class]).to include("panel-checkbox__input")
    expect(input[:name]).to eq("folio_transfer[route_code_ids][]")
    expect(input[:value]).to eq(code.id.to_s)
    expect(input[:checked]).to be_present
    expect(document.at_css("label[for='#{input[:id]}']").text).to include("Room Revenue", "ROOM")
  end

  it "keeps included taxes inside their parent row on the review screen" do
    tax = create(:folio_transaction, booking_folio: source, category: "tax", amount: 6, parent_transaction: charge,
      metadata: { tax_line: { name: "SST 6%" } })
    post path, params: { workflow_step: "preview", folio_transfer: draft }, headers: headers

    expect(response).to have_http_status(:success)
    document = Nokogiri::HTML(response.body)
    row = document.at_css("[data-folio-transfer-row-id='#{charge.id}']")
    expect(row.at_css("[data-folio-transfer-tax-id='#{tax.id}']")).to be_present
    expect(row.text).to include("Included taxes", "Charge + tax", "MYR 106.00")
    expect(document.at_css("[data-folio-transfer-row-id='#{tax.id}']")).to be_nil
  end

  it "keeps selections and reason after a stale preview" do
    attributes = draft
    post path, params: { workflow_step: "preview", folio_transfer: attributes }, headers: headers
    token = Nokogiri::HTML(response.body).at_css("input[name='preview_token']")[:value]
    create(:folio_transaction, booking_folio: source, amount: 20)
    post path, params: { workflow_step: "apply", folio_transfer: attributes, preview_token: token }, headers: headers
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("preview changed", "Group payment in master")
    expect(charge.reload.voided_by_transaction_id).to be_nil
  end

  it "does not expose unrelated hotel bookings in the destination selector" do
    unrelated = create(:booking_folio, hotel:, booking: create(:booking, hotel:), label: "Unrelated folio")
    target
    get path(active_folio_id: source.id), headers: headers
    expect(response.body).not_to include(unrelated.label)
  end

  it "forbids a user without movement permission" do
    role.permissions.delete(Permission.find_by!(slug: "manage_folio_movements"))
    get path, headers: headers
    expect(response).to have_http_status(:redirect)
    expect(flash[:alert]).to include("not authorized")
  end

  it "shows sibling targets on the individual Move and Split sheets" do
    target
    get hotel_folio_action_move_transaction_path(hotel, booking, charge), headers: headers
    expect(response.body).to include("Master A8")
    get hotel_folio_action_split_transaction_path(hotel, booking, charge), headers: headers
    expect(response.body).to include("Master A8", "folio-split-preview")
  end
end

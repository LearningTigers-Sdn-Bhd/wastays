# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Group folio transfer sheets", type: :system, js: true do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account:, status: "live") }
  let(:user) { create(:user, account:, role: "hotel_staff") }
  let(:role) { create(:role, account:) }
  let(:group) { create(:group_booking, hotel:) }
  let(:booking) { create(:booking, hotel:, group_booking: group) }
  let(:sibling) { create(:booking, hotel:, group_booking: group) }
  let!(:source) { create(:booking_folio, hotel:, booking:) }
  let!(:target) { create(:booking_folio, hotel:, booking: sibling, label: "Master A8") }
  let!(:charge) { create(:folio_transaction, booking_folio: source, amount: 100, description: "Group room charge") }

  before do
    driven_by(:cuprite)
    %w[view_bookings manage_folio_movements].each do |slug|
      role.permissions << Permission.find_or_create_by!(slug:) { |permission| permission.name = slug.humanize }
    end
    create(:user_hotel_access, user:, hotel:, role:)
    sign_in_through_ui(user)
  end

  it "reviews and transfers a room charge from More Actions into the master folio" do
    visit hotel_booking_workspace_path(hotel, booking, tab: "folio_operations", folio_id: source.id)
    click_button "More Actions"
    click_link "Transfer Folio"
    expect(page).to have_css("dialog#folio-transfer-sheet[open]")
    within("dialog#folio-transfer-sheet") do
      routing_toggle = "#folio-transfer-future-routing-trigger"
      expect(page).to have_css("#{routing_toggle}[aria-expanded='false']")
      find(routing_toggle).click
      expect(page).to have_css("#{routing_toggle}[aria-expanded='true']")
      expect(page).to have_css("#folio-transfer-future-routing-content input.panel-checkbox__input")
      find(routing_toggle).click
      expect(page).to have_css("#{routing_toggle}[aria-expanded='false']")
      find("[data-controller~='ui--select-menu'] button").click
      find("[role='option']", text: "Master A8").click
      expect(page).to have_text("1 charge selected from 1 folio.")
      within("[data-folio-id='#{target.id}']") do
        expect(page).to have_text("Receiving folio")
        expect(page).to have_no_css("input[type='checkbox']")
      end
      expect(page).to have_field("Reason (optional)", with: "")
      click_button "Review transfer"
      expect(page).to have_text("Review transfer to")
      expect(page).to have_text("Group room charge")
      expect(charge.reload.voided_by_transaction_id).to be_nil
      click_button "Confirm transfer"
    end
    expect(page).to have_no_css("dialog#folio-transfer-sheet[open]")
    expect(source.reload.outstanding_balance).to eq(0)
    expect(target.reload.outstanding_balance).to eq(100)
  end

  it "makes payment-only selection explicit and selects charges across other folios" do
    payment_booking = create(:booking, hotel:, group_booking: group)
    payment_folio = create(:booking_folio, hotel:, booking: payment_booking, label: "Room 201 credit")
    payment = create(:folio_transaction, booking_folio: payment_folio, transaction_type: "payment", category: "cash", amount: 1782, description: "Group prepayment credit")

    visit hotel_booking_workspace_path(hotel, payment_booking, tab: "folio_operations", folio_id: payment_folio.id)
    click_button "More Actions"
    click_link "Transfer Folio"
    within("dialog#folio-transfer-sheet") do
      expect(page).to have_text("No entries selected. Choose charges or payment credits above.")
      within("[data-folio-id='#{payment_folio.id}']") do
        expect(page).to have_css("input[type='checkbox']", count: 1)
        expect(page).to have_unchecked_field("Group prepayment credit")
        expect(page).to have_text("No transferable charges. To move a payment credit, select it below.")
      end
      find("[data-controller~='ui--select-menu'] button").click
      find("[role='option']", text: "Master A8").click
      check "Group prepayment credit"
      expect(page).to have_text("1 payment credit selected from 1 folio.")
      expect(page).to have_css("#folio-transfer-source-#{payment_folio.id}:not(:disabled)", visible: :all)
      click_button "Select charges from all folios"
      expect(page).to have_checked_field("Group room charge")
      expect(page).to have_checked_field("Group prepayment credit")
      expect(page).to have_text("1 charge and 1 payment credit selected from 2 folios.")
      click_button "Clear entries"
      expect(page).to have_unchecked_field("Group prepayment credit")
      expect(page).to have_unchecked_field("Group room charge")
      expect(page).to have_text("No entries selected.")
      expect(page).to have_css("#folio-transfer-source-#{payment_folio.id}:disabled", visible: :all)
      check "Group prepayment credit"
      find("[data-controller~='ui--select-menu'] button").click
      find("[role='option']", text: "Room 201 credit").click
      expect(page).to have_text("No entries selected.")
      expect(page).to have_css("#folio-transfer-source-#{payment_folio.id}:disabled", visible: :all)
      expect(page).to have_css("#folio-transfer-entry-#{payment.id}:disabled:not(:checked)", visible: :all)
      within("[data-folio-id='#{target.id}']") do
        expect(page).to have_text("No posted entries to move.")
      end
      page.current_window.resize_to(390, 844)
      fits_viewport = page.evaluate_script(<<~JS)
        Array.from(document.querySelectorAll('#folio-transfer-sheet [data-folio-transfer-target="destination"], #folio-transfer-sheet .panel-card')).every(element => {
          const bounds = element.getBoundingClientRect()
          return bounds.left >= 0 && bounds.right <= window.innerWidth
        })
      JS
      expect(fits_viewport).to eq(true)
    end
  end

  it "shows the partial split preview and preserves the remainder on the source" do
    visit hotel_booking_workspace_path(hotel, booking, tab: "folio_operations", folio_id: source.id)
    find("#folio-row-actions-#{charge.id} button").click
    click_link "Split"
    within("dialog#folio-split-transaction-sheet") do
      find("[data-controller~='ui--select-menu'] button").click
      find("[role='option']", text: "Master A8").click
      fill_in "Amount", with: "40"
      expect(page).to have_text("Destination: MYR 40.00")
      expect(page).to have_text("Source remainder: MYR 60.00")
      fill_in "Reason", with: "Split the group charge"
      click_button "Split transaction"
    end
    expect(page).to have_no_css("dialog#folio-split-transaction-sheet[open]")
    expect(source.reload.outstanding_balance).to eq(60)
    expect(target.reload.outstanding_balance).to eq(40)
  end

  it "keeps taxes inside charge rows and leaves surcharges behind when only a payment is selected" do
    tax = create(:folio_transaction, booking_folio: source, category: "tax", amount: 6, parent_transaction: charge,
      metadata: { tax_line: { name: "SST 6%" } })
    payment = create(:folio_transaction, booking_folio: source, transaction_type: "payment", category: "cash", amount: 102.12,
      description: "Card payment", metadata: { payment_operation_key: "card-payment" })
    surcharge = create(:folio_transaction, booking_folio: source, amount: 2, description: "Card surcharge", operation_key: "card-payment",
      metadata: { posting_source: "payment_surcharge" })
    fee_tax = create(:folio_transaction, booking_folio: source, category: "tax", amount: 0.12, parent_transaction: surcharge,
      metadata: { tax_line: { name: "SST 6%" } })

    visit hotel_booking_workspace_path(hotel, booking, tab: "folio_operations", folio_id: source.id)
    click_button "More Actions"
    click_link "Transfer Folio"
    within("dialog#folio-transfer-sheet") do
      within("[data-folio-transfer-row-id='#{charge.id}']") do
        expect(page).to have_css("[data-folio-transfer-tax-id='#{tax.id}']")
        expect(page).to have_text("SST 6%")
        expect(page).to have_text("Charge + tax")
        expect(page).to have_text("MYR 106.00")
        expect(page).to have_css("input[type='checkbox']", count: 1)
      end
      within("[data-folio-transfer-row-id='#{payment.id}']") do
        expect(page).to have_field("Card surcharge")
        expect(page).to have_css("[data-folio-transfer-tax-id='#{fee_tax.id}']")
      end
      find("[data-controller~='ui--select-menu'] button").click
      find("[role='option']", text: "Master A8").click
      click_button "Clear entries"
      check "Card payment"
      expect(page).to have_unchecked_field("Card surcharge")
      expect(page).to have_text("1 payment credit selected from 1 folio.")
      fill_in "Reason (optional)", with: "Move the credit only"
      click_button "Review transfer"
      expect(page).to have_text("Card payment")
      expect(page).to have_no_text("Card surcharge")
      click_button "Confirm transfer"
    end
    expect(page).to have_no_css("dialog#folio-transfer-sheet[open]")
    expect(target.reload.outstanding_balance).to eq(-102.12.to_d)
    expect(surcharge.reload).not_to be_reversed
    expect(fee_tax.reload).not_to be_reversed
  end
end

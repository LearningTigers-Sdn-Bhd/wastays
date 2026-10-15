# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Bookings::AgentPaymentsPresenter do
  include_context "with a scheduled agent booking"

  let(:role) { create(:role, account: hotel.account) }
  let(:desk) { create(:user, account: hotel.account) }
  let(:presenter) { described_class.new(booking: booking.reload, user: desk, hotel: hotel) }

  def grant(*slugs)
    slugs.each { |slug| role.permissions << Permission.find_or_create_by!(slug: slug) { |permission| permission.name = slug.titleize } }
    UserHotelAccess.find_or_create_by!(user: desk, hotel: hotel) { |access| access.role = role }
  end

  it "lists each stage with its amount, due date in the hotel's zone, and state" do
    row = presenter.rows.first

    expect(row).to have_attributes(stage: "Deposit", amount: "MYR 500.00", status_label: "Owed", badge_variant: :warning)
    expect(row.due).to match(/\A\d{2} \w{3} \d{4}, \d{1,2}\.\d{2}(am|pm) \+08\z/)
    expect(presenter.total_label).to eq("MYR 1,000.00")
    expect(presenter.owed_label).to eq("MYR 1,000.00")
  end

  it "offers no action to a user without the permission for it" do
    expect(presenter.rows.flat_map { |row| [ row.can_mark_paid, row.can_refund, row.can_reopen ] }).to all(be(false))
  end

  it "offers Mark paid only on the first stage still owed" do
    grant("post_folio_payments")

    expect(presenter.rows.map(&:can_mark_paid)).to eq([ true, false ])
  end

  it "describes a paid stage with who and when, and offers Refund with the refund permission" do
    grant("execute_folio_refunds")
    Bookings::PaymentInstalments::MarkPaid.call(instalment: deposit, user: staff, payment_method: "cash", reference: "R-1")

    row = presenter.rows.first
    expect(row).to have_attributes(status_label: "Paid", badge_variant: :success, can_refund: true)
    expect(row.detail).to include("Paid", "by #{staff.name}", "cash", "R-1")
    expect(presenter.paid_label).to eq("MYR 500.00")
  end

  it "describes a refunded stage with the reason, and offers Reopen with the permission" do
    grant("manage_ar_payments")
    pay(500)
    Bookings::PaymentInstalments::Refund.call(instalment: deposit, user: staff, refund_source: "cash", reason: "Paid twice")

    row = presenter.rows.first
    expect(row).to have_attributes(status_label: "Refunded", can_reopen: true, can_mark_paid: false)
    expect(row.detail).to include("Refunded", "Paid twice")
  end

  it "offers nothing on a cancelled booking" do
    grant("post_folio_payments", "manage_ar_payments")
    booking.update_columns(status: "cancelled")

    expect(presenter.rows.map(&:can_mark_paid)).to all(be(false))
  end

  it "suggests the hotel's usual hold as the date for a reopened stage" do
    expect(presenter.default_reopen_date).to be >= presenter.earliest_reopen_date
  end
end

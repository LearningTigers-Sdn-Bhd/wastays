# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Hotels::OnboardingOverviewPresenter do
  let(:states) do
    Onboarding::SectionCatalog.keys.index_with { { "state" => "complete" } }.merge(
      "staff_setup" => { "state" => "skipped" },
      "taxes_fees" => { "state" => "in_progress" },
      "rooms" => { "state" => "needs_attention" }
    )
  end
  let(:snapshot) do
    {
      "property" => {
        "name" => "Garden Hotel", "address" => "1 Beach Road", "city" => "Kota Belud",
        "country" => "Malaysia", "default_currency" => "MYR", "sell_mode" => "per_room", "photo_count" => 6
      },
      "sections" => states,
      "staff" => [ { "name" => "Ari" } ],
      "taxes" => [ { "name" => "Tourism tax" }, { "name" => "Service tax" } ],
      "rooms" => [ { "name" => "Garden Room", "quantity" => 4 }, { "name" => "Suite", "quantity" => 2 } ],
      "rates" => { "coverage" => { "configured_percentage" => "100.0", "end_date" => "2027-08-12", "complete" => true } },
      "commercial" => {
        "extra_charges" => [ { "name" => "Breakfast" } ],
        "discounts" => [],
        "payment_methods" => [ { "name" => "Cash" }, { "name" => "Card" } ],
        "corporate_accounts" => [ { "company_name" => "Acme" } ]
      },
      "ota_handover" => [ {
        "channel_name" => "Booking.com", "credentials_supplied" => true,
        "username" => "private-user", "password" => "private-password"
      } ]
    }
  end
  let(:deliveries) do
    [
      instance_double(OnboardingDelivery, delivery_type: "staff_invitation", status: "sent"),
      instance_double(OnboardingDelivery, delivery_type: "corporate_invitation", status: "held"),
      instance_double(OnboardingDelivery, delivery_type: "staff_invitation", status: "processing"),
      instance_double(OnboardingDelivery, delivery_type: "corporate_invitation", status: "failed"),
      instance_double(OnboardingDelivery, delivery_type: "admin_submitted", status: "sent")
    ]
  end
  let(:submission) { instance_double(OnboardingSubmission, snapshot:, deliveries:) }

  subject(:presenter) { described_class.new(submission:) }

  it "builds five catalog-ordered groups with twelve submitted setup rows" do
    expect(presenter.groups.map { |group| [ group.key, group.label ] }).to eq([
      [ "property", "Property" ],
      [ "team", "Team" ],
      [ "finance", "Finance" ],
      [ "rooms_rates", "Rooms & rates" ],
      [ "commercial", "Commercial" ]
    ])

    rows = presenter.groups.flat_map(&:rows)
    expect(rows.map { |row| row.definition.key }).to eq(Onboarding::SectionCatalog.keys.excluding("review"))
    expect(rows.map(&:title)).to eq(
      Onboarding::SectionCatalog.all.excluding(Onboarding::SectionCatalog.fetch("review")).map do |definition|
        HotelPortal::OnboardingPresenter::SECTION_CONTENT.fetch(definition.key).first
      end
    )
  end

  it "summarizes the immutable submission snapshot and normalizes every supported state" do
    rows = presenter.groups.flat_map(&:rows).index_by { |row| row.definition.key }

    expect(rows.fetch("property_profile")).to have_attributes(
      summary: "Kota Belud, Malaysia · MYR", status_label: "Complete", status_variant: :success
    )
    expect(rows.fetch("staff_setup")).to have_attributes(
      summary: "1 staff member", status_label: "Deferred", status_variant: :warning
    )
    expect(rows.fetch("taxes_fees")).to have_attributes(
      summary: "2 property taxes or fees", status_label: "In progress", status_variant: :info
    )
    expect(rows.fetch("rooms")).to have_attributes(
      summary: "2 room types · 6 rooms", status_label: "Needs attention", status_variant: :destructive
    )
    expect(rows.fetch("rates_availability").summary).to eq("Coverage through 12 Aug 2027")
    expect(rows.fetch("extra_charges").summary).to eq("1 extra charge")
    expect(rows.fetch("discounts").summary).to eq("No discounts")
    expect(rows.fetch("payment_methods").summary).to eq("2 payment methods")
    expect(rows.fetch("corporate_accounts").summary).to eq("1 corporate account")
    expect(rows.fetch("channel_manager").summary).to eq("1 channel handover")
  end

  it "builds submitted setup and inventory metrics without using current hotel records" do
    expect(presenter.metrics.map(&:to_h)).to eq([
      { label: "Required setup", value: "5 of 7", detail: "2 remaining", detail_variant: :warning },
      { label: "Optional decisions", value: "5 of 5", detail: "1 deferred", detail_variant: :success },
      { label: "Rooms", value: "6", detail: "2 room types", detail_variant: :neutral },
      { label: "Rate coverage", value: "100%", detail: "Through 12 Aug 2027", detail_variant: :success }
    ])
  end

  it "provides property, room, commercial, invitation, and safe channel evidence rows" do
    expect(presenter.property_rows.map { |row| [ row.label, row.value ] }).to eq([
      [ "Name", "Garden Hotel" ], [ "Address", "1 Beach Road" ], [ "Location", "Kota Belud, Malaysia" ],
      [ "Currency", "MYR" ], [ "Sell mode", "Per room" ], [ "Photos", "6" ]
    ])
    expect(presenter.room_rows.map { |row| [ row.name, row.quantity ] })
      .to eq([ [ "Garden Room", "4" ], [ "Suite", "2" ] ])
    expect(presenter.commercial_rows.map { |row| [ row.label, row.value ] }).to eq([
      [ "Extra charges", "1" ], [ "Discounts", "0" ], [ "Payment methods", "2" ], [ "Corporate accounts", "1" ]
    ])
    expect(presenter.handover_rows.map { |row| [ row.label, row.value ] }).to eq([
      [ "Invitation delivery", "1 sent · 1 held · 1 pending · 1 failed" ],
      [ "Booking.com", "Credentials supplied" ]
    ])
    expect(presenter.handover_rows.to_s).not_to include("private-user", "private-password")
  end

  it "uses safe fallbacks for missing collections, unknown states, and malformed coverage dates" do
    fallback = described_class.new(
      submission: instance_double(
        OnboardingSubmission,
        snapshot: { "sections" => { "property_profile" => { "state" => "unknown" } },
                    "rates" => { "coverage" => { "configured_percentage" => "invalid", "end_date" => "not-a-date" } } },
        deliveries: []
      )
    )
    rows = fallback.groups.flat_map(&:rows).index_by { |row| row.definition.key }

    expect(rows.values.map(&:status_label).uniq).to eq([ "Not started" ])
    expect(rows.fetch("property_profile").summary).to eq("Property details saved")
    expect(rows.fetch("staff_setup").summary).to eq("No additional staff")
    expect(rows.fetch("rooms").summary).to eq("0 room types · 0 rooms")
    expect(rows.fetch("rates_availability").summary).to eq("Rate coverage saved")
    expect(rows.fetch("channel_manager").summary).to eq("No channel handover")
    expect(fallback.metrics.map(&:to_h)).to eq([
      { label: "Required setup", value: "0 of 7", detail: "7 remaining", detail_variant: :warning },
      { label: "Optional decisions", value: "0 of 5", detail: "0 deferred", detail_variant: :warning },
      { label: "Rooms", value: "0", detail: "0 room types", detail_variant: :neutral },
      { label: "Rate coverage", value: "Not supplied", detail: "No coverage date", detail_variant: :warning }
    ])
    expect(fallback.property_rows.map(&:value)).to eq(Array.new(6, "Not supplied"))
    expect(fallback.room_rows).to be_empty
    expect(fallback.commercial_rows.map(&:value)).to eq([ "0", "0", "0", "0" ])
    expect(fallback.handover_rows.map { |row| [ row.label, row.value ] }).to eq([
      [ "Invitation delivery", "No invitations created" ],
      [ "Channel handover", "No channels submitted" ]
    ])
  end
end

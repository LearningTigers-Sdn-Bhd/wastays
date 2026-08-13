# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260813150000_normalize_hotel_lifecycle_statuses")

RSpec.describe NormalizeHotelLifecycleStatuses do
  subject(:migration) { described_class.new }

  def run!
    ActiveRecord::Migration.suppress_messages { migration.up }
  end

  # The model now rejects the legacy vocabulary, so seed it past validation.
  def hotel_on(status, column: :status)
    create(:hotel).tap { |hotel| hotel.update_column(column, status) }
  end

  it "folds every legacy setup status into setup" do
    hotels = described_class::LEGACY_SETUP.to_h { |status| [ status, hotel_on(status) ] }

    run!

    hotels.each do |legacy, hotel|
      expect(hotel.reload.status).to eq("setup"), "expected #{legacy} to become setup"
    end
  end

  it "renames approved to live" do
    hotel = hotel_on("approved")

    run!

    expect(hotel.reload.status).to eq("live")
  end

  it "leaves canonical statuses untouched" do
    canonical = Hotel::STATUSES.to_h { |status| [ status, hotel_on(status) ] }

    run!

    canonical.each do |status, hotel|
      expect(hotel.reload.status).to eq(status)
    end
  end

  it "normalizes the status stashed by suspension" do
    hotel = hotel_on("suspended")
    hotel.update_column(:pre_suspension_status, "inventory_incomplete")
    approved = hotel_on("suspended")
    approved.update_column(:pre_suspension_status, "approved")

    run!

    expect(hotel.reload.pre_suspension_status).to eq("setup")
    expect(approved.reload.pre_suspension_status).to eq("live")
  end

  it "is idempotent" do
    hotel = hotel_on("registered")

    run!
    run!

    expect(hotel.reload.status).to eq("setup")
  end

  it "cannot be rolled back" do
    expect { migration.down }.to raise_error(ActiveRecord::IrreversibleMigration)
  end
end

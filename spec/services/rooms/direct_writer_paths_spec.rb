# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Direct numbered-room writers" do
  WRITER_PATHS = %w[
    db/demo_seeds.rb
    db/seeds/per_pax_hotel_seeder.rb
    db/seeds/three_month_active_hotel_seeder.rb
    lib/tasks/generate_hotel_dataset.rake
  ].freeze

  it "routes every supported seed and dataset path through physical-room synchronization" do
    WRITER_PATHS.each do |path|
      source = Rails.root.join(path).read

      expect(source).to include("Rooms::SyncFromRoomType.call!"), "Expected #{path} to synchronize physical rooms"
    end
  end
end

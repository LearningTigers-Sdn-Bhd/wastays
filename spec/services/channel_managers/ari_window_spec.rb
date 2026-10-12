# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChannelManagers::AriWindow do
  let(:cache_store) { ActiveSupport::Cache::MemoryStore.new }

  before { allow(Rails).to receive(:cache).and_return(cache_store) }

  def change(date, room_type_id)
    {
      "min_date" => date, "max_date" => date,
      "sync_availability" => true, "sync_rates" => false, "sync_restrictions" => false,
      "room_type_windows" => { room_type_id.to_s => { "min" => date, "max" => date } },
      "rate_plan_windows" => {}, "rate_plan_fields" => {}
    }
  end

  describe ".merge" do
    it "widens the dates, ORs the flags and unions per-room and per-plan windows" do
      base = change("2026-11-05", 1).merge("rate_plan_fields" => { "9" => [ "price" ] })
      other = change("2026-11-07", 2).merge(
        "sync_rates" => true,
        "room_type_windows" => { "1" => { "min" => "2026-11-07", "max" => "2026-11-07" } },
        "rate_plan_fields" => { "9" => [ "price", "min_stay" ] }
      )

      merged = described_class.merge(base, other)

      expect(merged).to include(
        "min_date" => "2026-11-05", "max_date" => "2026-11-07",
        "sync_availability" => true, "sync_rates" => true, "sync_restrictions" => false,
        "room_type_windows" => { "1" => { "min" => "2026-11-05", "max" => "2026-11-07" } },
        "rate_plan_fields" => { "9" => [ "price", "min_stay" ] }
      )
    end
  end

  describe "#add" do
    it "asks for a flush only when none is pending" do
      outbox = described_class.new(42)

      expect(outbox.add(change("2026-11-05", 1))).to be(true)
      expect(outbox.add(change("2026-11-06", 1))).to be(false)
    end
  end

  describe "#claim and #restore" do
    it "empties the outbox and puts a failed push back alongside newer changes" do
      outbox = described_class.new(42)
      outbox.add(change("2026-11-05", 1))

      claimed = outbox.claim
      expect(outbox.claim).to be_nil

      outbox.add(change("2026-11-20", 2))
      outbox.restore(claimed)

      expect(outbox.claim).to include(
        "min_date" => "2026-11-05", "max_date" => "2026-11-20",
        "room_type_windows" => {
          "1" => { "min" => "2026-11-05", "max" => "2026-11-05" },
          "2" => { "min" => "2026-11-20", "max" => "2026-11-20" }
        }
      )
    end
  end

  # Real threads on their own connections, so the advisory lock is what keeps
  # the nights of one booking from overwriting each other.
  context "when several workers buffer at the same moment" do
    self.use_transactional_tests = false

    let(:slow_cache) do
      store = cache_store
      Class.new(SimpleDelegator) do
        def read(*)
          value = super
          sleep 0.05
          value
        end
      end.new(store)
    end

    before { allow(Rails).to receive(:cache).and_return(slow_cache) }

    it "keeps every night of a multi-night booking" do
      nights = %w[2026-11-05 2026-11-06 2026-11-07]

      nights.map do |night|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            described_class.new(42).add(change(night, 1))
          end
        end
      end.each(&:join)

      window = described_class.new(42).claim
      expect(window).to include("min_date" => "2026-11-05", "max_date" => "2026-11-07")
      expect(window["room_type_windows"]["1"]).to eq("min" => "2026-11-05", "max" => "2026-11-07")
    end
  end
end

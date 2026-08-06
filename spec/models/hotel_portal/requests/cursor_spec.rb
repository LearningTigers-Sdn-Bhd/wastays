require "rails_helper"

RSpec.describe HotelPortal::Requests::Cursor do
  let(:at) { Time.zone.parse("2026-07-31 09:30:00.123456") }

  describe "travelling in a link" do
    it "round-trips through a param" do
      cursor = described_class.new(at: at, source: "housekeeping", id: 42)

      parsed = described_class.parse(cursor.to_param)

      expect(parsed.at).to eq(at)
      expect(parsed.source).to eq("housekeeping")
      expect(parsed.id).to eq(42)
    end

    it "keeps sub-second precision, because rows share a second" do
      cursor = described_class.parse(described_class.new(at: at, source: "complaint", id: 1).to_param)

      expect(cursor.at.usec).to eq(at.usec)
    end

    it "refuses anything it cannot read rather than guessing" do
      expect(described_class.parse(nil)).to be_nil
      expect(described_class.parse("")).to be_nil
      expect(described_class.parse("nonsense")).to be_nil
      expect(described_class.parse("not-a-time|housekeeping|1")).to be_nil
      expect(described_class.parse("2026-07-31|housekeeping")).to be_nil
    end
  end

  describe ".sort" do
    def row(at:, source:, id:)
      { sort_at: at, sort_source: source, request_id: id }
    end

    it "puts the newest first" do
      rows = [ row(at: at - 1.hour, source: "a", id: 1), row(at: at, source: "a", id: 2) ]

      expect(described_class.sort(rows).map { |r| r[:request_id] }).to eq([ 2, 1 ])
    end

    # Ids only tell rows apart inside their own table, so two tables sharing an
    # instant need something between the instant and the id.
    it "breaks a tie by kind, then by id descending" do
      rows = [
        row(at: at, source: "housekeeping", id: 1),
        row(at: at, source: "checkout", id: 9),
        row(at: at, source: "housekeeping", id: 7),
        row(at: at, source: "complaint", id: 3)
      ]

      expect(described_class.sort(rows).map { |r| [ r[:sort_source], r[:request_id] ] }).to eq(
        [ [ "checkout", 9 ], [ "complaint", 3 ], [ "housekeeping", 7 ], [ "housekeeping", 1 ] ]
      )
    end
  end

  describe "#predicate_for" do
    subject(:cursor) { described_class.new(at: at, source: "complaint", id: 5) }

    it "asks its own kind for older rows, and for smaller ids at the same instant" do
      sql, binds = cursor.predicate_for(table: "complaint_requests", column: "requested_at", source: "complaint")

      expect(sql).to eq(
        "complaint_requests.requested_at < :cursor_at OR " \
        "(complaint_requests.requested_at = :cursor_at AND complaint_requests.id < :cursor_id)"
      )
      expect(binds).to eq(cursor_at: at, cursor_id: 5)
    end

    # A kind sorting before the cursor's has already had its turn at that instant.
    it "excludes the cursor's instant for a kind that sorts before it" do
      sql, binds = cursor.predicate_for(table: "check_out_requests", column: "requested_at", source: "checkout")

      expect(sql).to eq("check_out_requests.requested_at < :cursor_at")
      expect(binds).to eq(cursor_at: at)
    end

    # A kind sorting after the cursor's has not, so it keeps the instant.
    it "includes the cursor's instant for a kind that sorts after it" do
      sql, binds = cursor.predicate_for(table: "housekeeping_requests", column: "completed_at", source: "housekeeping")

      expect(sql).to eq("housekeeping_requests.completed_at <= :cursor_at")
      expect(binds).to eq(cursor_at: at)
    end
  end

  # The predicate and the sort have to agree, or a page boundary drops a row or
  # shows it twice.
  describe "the predicate agrees with the sort" do
    it "keeps exactly the rows that sort after the cursor" do
      rows = [
        { sort_at: at, sort_source: "checkout", request_id: 9 },
        { sort_at: at, sort_source: "complaint", request_id: 7 },
        { sort_at: at, sort_source: "complaint", request_id: 5 },
        { sort_at: at, sort_source: "complaint", request_id: 2 },
        { sort_at: at, sort_source: "housekeeping", request_id: 8 },
        { sort_at: at - 1.second, sort_source: "checkout", request_id: 1 }
      ]
      ordered = described_class.sort(rows)
      cursor = described_class.new(at: at, source: "complaint", id: 5)
      expected_after = ordered.drop(ordered.index { |r| r[:sort_source] == "complaint" && r[:request_id] == 5 } + 1)

      kept = rows.select do |candidate|
        case candidate[:sort_source] <=> cursor.source
        when 0 then candidate[:sort_at] < cursor.at || (candidate[:sort_at] == cursor.at && candidate[:request_id] < cursor.id)
        when -1 then candidate[:sort_at] < cursor.at
        else candidate[:sort_at] <= cursor.at
        end
      end

      expect(described_class.sort(kept)).to eq(expected_after)
    end
  end
end
